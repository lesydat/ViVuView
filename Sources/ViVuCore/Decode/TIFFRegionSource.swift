import CoreGraphics
import CTIFFShim
import Foundation
import UniformTypeIdentifiers

/// Huge TIFF / BigTIFF / GeoTIFF read piece by piece with libtiff (docs/TECH_SPEC.md §4.4, tier L-A).
/// Uses the file's own reduced-resolution images (overview IFDs, SubIFDs, GDAL `.ovr`) as levels, reads only
/// the blocks a request touches, and averages them exactly with `BandedAreaMean`.
/// 8-bit images go through libtiff's RGBA interface (palette, YCbCr/JPEG, CMYK, 1-bit …); 16-bit, 32-bit,
/// float and multi-band images are read raw and mapped to 8 bits by a contrast stretch (`Stretch`).
/// Declines (`DecodeError.unsupported`) planar-separate data and anything libtiff cannot describe.
public final class TIFFRegionSource: RegionSource, @unchecked Sendable {
    // Sendable: immutable after init except `stretch`, which is guarded by `stretchLock`; handles come from
    // `HandlePool`, one per thread at a time.

    public let meta: ImageMeta
    public let maxLevel: Int
    public let levels: [Level]
    public let iccProfile: Data?
    /// Mapping of high-bit-depth samples to 8 bits; nil for plain 8-bit images.
    public let stretchRange: Stretch?
    private let stretchLock = NSLock()
    private var stretchOn = TIFFRegionSource.stretchByDefault

    /// The last choice of key E, used by every reader opened afterwards (the app reopens files often).
    nonisolated(unsafe) private static var defaultStretch = true
    private static let defaultLock = NSLock()
    public static var stretchByDefault: Bool {
        get { defaultLock.withLock { defaultStretch } }
        set { defaultLock.withLock { defaultStretch = newValue } }
    }
    private let pools: [HandlePool]

    public struct Level: Sendable {
        public let width: Int
        public let height: Int
        /// Full width / this width.
        public let downscale: Double
        let file: Int
        let directory: Directory
        let info: vv_dir_info
        var tiled: Bool { info.tiled != 0 }
        /// Block size: a tile, or a band of strips across the whole width.
        var blockWidth: Int { tiled ? Int(info.tile_width) : width }
        var blockHeight: Int {
            if tiled { return Int(info.tile_height) }
            let rows = Int(info.rows_per_strip == 0 || info.rows_per_strip > UInt32(height) ? UInt32(height) : info.rows_per_strip)
            return max(1, rows)
        }
    }

    enum Directory: Sendable, Equatable {
        case index(UInt32)
        case subIFD(UInt64)
    }

    public var hasOverviews: Bool { levels.count > 1 }

    public init(url: URL) throws {
        let mainPool = try HandlePool(path: url.path)
        var pools = [mainPool]
        var levels: [Level] = []
        let handle = try mainPool.take()
        defer { mainPool.give(handle) }

        // Main image: the first directory that is not reduced-resolution or a mask.
        let count = Int(vv_directory_count(handle.tiff))
        var main: (Directory, vv_dir_info)?
        var reduced: [(Directory, vv_dir_info)] = []
        for i in 0..<count {
            guard vv_set_directory(handle.tiff, UInt32(i)) == 1 else { continue }
            var info = vv_dir_info()
            guard vv_dir_info_get(handle.tiff, &info) == 1 else { continue }
            if info.subfile_type & 4 != 0 { continue }             // transparency mask
            if info.subfile_type & 1 != 0 {
                reduced.append((.index(UInt32(i)), info))
            } else if main == nil {
                main = (.index(UInt32(i)), info)
                // SubIFDs of the main image are often its overviews.
                var offsets = [UInt64](repeating: 0, count: 32)
                let n = Int(vv_subifds(handle.tiff, &offsets, 32))
                for offset in offsets.prefix(min(n, 32)) {
                    guard vv_set_subdirectory(handle.tiff, offset) == 1 else { continue }
                    var sub = vv_dir_info()
                    if vv_dir_info_get(handle.tiff, &sub) == 1 { reduced.append((.subIFD(offset), sub)) }
                }
                _ = vv_set_directory(handle.tiff, UInt32(i))
            }
        }
        guard let (mainDir, mainInfo) = main else { throw DecodeError.unsupported }
        try Self.check(mainInfo)
        let fullW = Int(mainInfo.width), fullH = Int(mainInfo.height)
        levels.append(Level(width: fullW, height: fullH, downscale: 1, file: 0, directory: mainDir, info: mainInfo))

        // GDAL external overviews next to the file.
        let ovr = URL(fileURLWithPath: url.path + ".ovr")
        if FileManager.default.fileExists(atPath: ovr.path), let ovrPool = try? HandlePool(path: ovr.path),
           let h = try? ovrPool.take() {
            for i in 0..<Int(vv_directory_count(h.tiff)) where vv_set_directory(h.tiff, UInt32(i)) == 1 {
                var info = vv_dir_info()
                if vv_dir_info_get(h.tiff, &info) == 1, info.subfile_type & 4 == 0, info.width < mainInfo.width,
                   info.samples_per_pixel == mainInfo.samples_per_pixel, (try? Self.check(info)) != nil {
                    levels.append(Level(width: Int(info.width), height: Int(info.height),
                                        downscale: Double(fullW) / Double(max(1, info.width)), file: 1,
                                        directory: .index(UInt32(i)), info: info))
                }
            }
            ovrPool.give(h)
            pools.append(ovrPool)
        }
        for (dir, info) in reduced {
            guard info.samples_per_pixel == mainInfo.samples_per_pixel, info.bits_per_sample == mainInfo.bits_per_sample,
                  info.width < mainInfo.width, info.planar_config == mainInfo.planar_config,
                  (try? Self.check(info)) != nil else { continue }
            levels.append(Level(width: Int(info.width), height: Int(info.height),
                                downscale: Double(fullW) / Double(max(1, info.width)), file: 0, directory: dir, info: info))
        }
        levels.sort { $0.downscale < $1.downscale }
        self.levels = levels
        self.pools = pools

        var iccData: UnsafeRawPointer?
        var iccLength: UInt32 = 0
        _ = Self.select(handle, levels[0].directory)
        iccProfile = vv_icc_profile(handle.tiff, &iccData, &iccLength) == 1 && iccData != nil
            ? Data(bytes: iccData!, count: Int(iccLength)) : nil

        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        meta = ImageMeta(storedSize: PixelSize(width: fullW, height: fullH), orientation: 1, frameCount: 1, hasAlpha: false,
                         uti: UTType.tiff.identifier, fileSize: Int64(values?.fileSize ?? 0),
                         modificationDate: values?.contentModificationDate)
        maxLevel = Self.maxLevel(for: meta.storedSize)

        // High bit depth: stretch from a coarse level.
        if Self.needsRawPath(mainInfo) {
            let coarse = levels.last!
            stretchRange = try Self.measureStretch(pool: pools[coarse.file], level: coarse)
        } else {
            stretchRange = nil
        }
    }

    /// Turns the contrast stretch of high-bit-depth images on or off (key E).
    public var stretchEnabled: Bool {
        get { stretchLock.withLock { stretchOn } }
        set {
            stretchLock.withLock { stretchOn = newValue }
            Self.stretchByDefault = newValue
        }
    }

    public var colorSpace: CGColorSpace? {
        iccProfile.flatMap { CGColorSpace(iccData: $0 as CFData) }.flatMap { $0.model == .rgb ? $0 : nil }
    }

    static func check(_ info: vv_dir_info) throws {
        guard info.planar_config == 1 || info.samples_per_pixel == 1 else { throw DecodeError.unsupported }   // planar separate
        guard info.width > 0, info.height > 0 else { throw DecodeError.corrupt("kích thước 0") }
        if needsRawPath(info) {
            guard [1, 2, 3].contains(Int(info.sample_format)) || info.sample_format == 0,
                  [8, 16, 32, 64].contains(Int(info.bits_per_sample)),
                  info.photometric == 1 || info.photometric == 2 || info.photometric == 0 else { throw DecodeError.unsupported }
        }
    }

    /// 8-bit with ≤ 4 samples goes through libtiff's RGBA interface; everything else is read raw.
    static func needsRawPath(_ info: vv_dir_info) -> Bool {
        info.bits_per_sample > 8 || info.samples_per_pixel > 4 || info.sample_format == 3
            || (info.bits_per_sample == 8 && info.sample_format == 2)
    }

    /// 8-bit unsigned RGB or grayscale without colour tricks: decoded bytes are already what we need, so skip
    /// libtiff's RGBA conversion (one less pass over a multi-GB image).
    static func isPlain8Bit(_ info: vv_dir_info) -> Bool {
        info.bits_per_sample == 8 && (info.sample_format == 1 || info.sample_format == 0)
            && ((info.photometric == 2 && (3...4).contains(info.samples_per_pixel))
                || (info.photometric == 1 && (1...2).contains(info.samples_per_pixel)))
            && info.compression != 6 && info.compression != 7     // JPEG-in-TIFF may be YCbCr: RGBA path
    }

    // MARK: Reading

    public func read(rect: PixelRect, outSize: PixelSize) throws -> PixelBuffer {
        let region = rect.intersection(PixelRect(size: meta.storedSize))
        guard !region.isEmpty else { throw DecodeError.corrupt("vùng đọc rỗng") }
        let shrink = Double(region.width) / Double(max(1, outSize.width))
        // The coarsest file level that is still at least as detailed as the output.
        let level = levels.last { $0.downscale <= shrink * 1.001 } ?? levels[0]
        let ds = level.downscale
        let lx0 = Int((Double(region.x) / ds).rounded(.down)), ly0 = Int((Double(region.y) / ds).rounded(.down))
        let lx1 = min(level.width, max(lx0 + 1, Int((Double(region.maxX) / ds).rounded(.up))))
        let ly1 = min(level.height, max(ly0 + 1, Int((Double(region.maxY) / ds).rounded(.up))))
        let levelRegion = PixelRect(x: lx0, y: ly0, width: lx1 - lx0, height: ly1 - ly0)
        let pool = pools[level.file]
        let stretch = stretchEnabled ? stretchRange : stretchRange.map { Stretch.linear(for: $0.kind) }
        let buffer = try BandedAreaMean.downscale(region: levelRegion, outSize: outSize, bandHeight: level.blockHeight) { band, emit in
            let handle = try pool.take()
            defer { pool.give(handle) }
            guard Self.select(handle, level.directory) else { throw DecodeError.corrupt("không chọn được IFD") }
            try Self.decodeBand(band, level: level, region: levelRegion, handle: handle, stretch: stretch, emit: emit)
        }
        try ColorConvert.toDisplayP3(buffer, from: colorSpace)
        return buffer
    }

    static func select(_ handle: TIFFHandle, _ directory: Directory) -> Bool {
        if handle.current == directory { return true }
        let ok: Bool
        switch directory {
        case .index(let i): ok = vv_set_directory(handle.tiff, i) == 1
        case .subIFD(let offset): ok = vv_set_subdirectory(handle.tiff, offset) == 1
        }
        handle.current = ok ? directory : nil
        return ok
    }

    /// Decodes the blocks of one band (a row of tiles, or one strip band) that meet `region`.
    static func decodeBand(_ band: Int, level: Level, region: PixelRect, handle: TIFFHandle, stretch: Stretch?,
                           emit: BandedAreaMean.Emit) throws {
        let bw = level.blockWidth, bh = level.blockHeight
        let y0 = band * bh
        let h = min(bh, level.height - y0)
        guard h > 0 else { return }
        let firstCol = region.x / bw, lastCol = (region.maxX - 1) / bw
        let rgb = UnsafeMutablePointer<UInt8>.allocate(capacity: bw * bh * 3)
        defer { rgb.deallocate() }
        for col in firstCol...lastCol {
            let x0 = col * bw
            let w = min(bw, level.width - x0)
            if needsRawPath(level.info) || isPlain8Bit(level.info) {
                try readRaw(level: level, handle: handle, x0: x0, y0: y0, w: w, h: h, stretch: stretch, into: rgb)
            } else {
                try readRGBA(handle: handle, x0: x0, y0: y0, w: w, h: h, into: rgb)
            }
            emit(x0, y0, w, h, rgb, w * 3)
        }
    }

    /// 8-bit path through libtiff's RGBA interface.
    static func readRGBA(handle: TIFFHandle, x0: Int, y0: Int, w: Int, h: Int, into rgb: UnsafeMutablePointer<UInt8>) throws {
        let raster = UnsafeMutablePointer<UInt32>.allocate(capacity: w * h)
        defer { raster.deallocate() }
        guard vv_read_rgba_rect(handle.tiff, UInt32(x0), UInt32(y0), UInt32(w), UInt32(h), raster) == 1 else {
            throw DecodeError.corrupt("libtiff không đọc được khối")
        }
        for i in 0..<(w * h) {
            let p = raster[i]
            rgb[i * 3] = UInt8(truncatingIfNeeded: p)
            rgb[i * 3 + 1] = UInt8(truncatingIfNeeded: p >> 8)
            rgb[i * 3 + 2] = UInt8(truncatingIfNeeded: p >> 16)
        }
    }

    /// Raw path: decode the block's samples and map them to 8-bit RGB.
    static func readRaw(level: Level, handle: TIFFHandle, x0: Int, y0: Int, w: Int, h: Int, stretch: Stretch?,
                        into rgb: UnsafeMutablePointer<UInt8>) throws {
        let info = level.info
        let size = level.tiled ? vv_tile_size(handle.tiff) : vv_strip_size(handle.tiff)
        guard size > 0 else { throw DecodeError.corrupt("kích thước khối") }
        let spp = Int(info.samples_per_pixel), bytes = Int(info.bits_per_sample) / 8
        let blockW = level.tiled ? Int(info.tile_width) : level.width
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: 16)
        defer { raw.deallocate() }
        let stretch = stretch ?? Stretch.linear(for: Stretch.Kind(info))
        let lut = stretch.lut8   // used for 8-bit signed only
        // Strips: one strip band may consist of several strips when rows_per_strip < block height.
        var row = 0
        while row < h {
            let n: Int64 = level.tiled ? vv_read_tile(handle.tiff, UInt32(x0), UInt32(y0), raw, size)
                                       : vv_read_strip(handle.tiff, UInt32(y0 + row), raw, size)
            guard n > 0 else { throw DecodeError.corrupt("libtiff không đọc được khối") }
            let rowsHere = level.tiled ? h : min(h - row, Int(info.rows_per_strip == 0 ? UInt32(level.height) : info.rows_per_strip))
            if bytes == 1 && info.sample_format != 2 && spp <= 4 {
                // Fast 8-bit path: copy / expand bytes directly.
                for r in 0..<rowsHere {
                    let src = (raw + r * blockW * spp).assumingMemoryBound(to: UInt8.self)
                    let dst = rgb + (row + r) * w * 3
                    switch spp {
                    case 3: dst.update(from: src, count: w * 3)
                    case 4: for x in 0..<w { dst[x * 3] = src[x * 4]; dst[x * 3 + 1] = src[x * 4 + 1]; dst[x * 3 + 2] = src[x * 4 + 2] }
                    default: for x in 0..<w { let v = src[x * spp]; dst[x * 3] = v; dst[x * 3 + 1] = v; dst[x * 3 + 2] = v }
                    }
                }
                row += rowsHere
                continue
            }
            for r in 0..<rowsHere {
                let srcRow = raw + r * blockW * spp * bytes
                let dst = rgb + (row + r) * w * 3
                for x in 0..<w {
                    let base = srcRow + x * spp * bytes
                    for c in 0..<3 {
                        let s = spp >= 3 ? c : 0
                        let v = sample(base + s * bytes, bits: Int(info.bits_per_sample), format: Int(info.sample_format))
                        dst[x * 3 + c] = bytes == 1 && info.sample_format != 2 ? UInt8(clamping: Int(v)) : stretch.map(v, lut: lut)
                    }
                }
            }
            row += rowsHere
        }
    }

    @inline(__always)
    static func sample(_ p: UnsafeRawPointer, bits: Int, format: Int) -> Double {
        switch (bits, format) {
        case (8, 2): return Double(p.load(as: Int8.self))
        case (8, _): return Double(p.load(as: UInt8.self))
        case (16, 2): return Double(p.loadUnaligned(as: Int16.self))
        case (16, _): return Double(p.loadUnaligned(as: UInt16.self))
        case (32, 3): return Double(p.loadUnaligned(as: Float.self))
        case (32, 2): return Double(p.loadUnaligned(as: Int32.self))
        case (32, _): return Double(p.loadUnaligned(as: UInt32.self))
        case (64, 3): return p.loadUnaligned(as: Double.self)
        default: return 0
        }
    }

    /// 2nd–98th percentile of samples from a coarse level (docs/TECH_SPEC.md §4.4).
    static func measureStretch(pool: HandlePool, level: Level) throws -> Stretch {
        let handle = try pool.take()
        defer { pool.give(handle) }
        guard select(handle, level.directory) else { throw DecodeError.corrupt("IFD") }
        let info = level.info
        var values: [Double] = []
        let size = level.tiled ? vv_tile_size(handle.tiff) : vv_strip_size(handle.tiff)
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(max(size, 1)), alignment: 16)
        defer { raw.deallocate() }
        let spp = Int(info.samples_per_pixel), bytes = Int(info.bits_per_sample) / 8
        let bw = level.blockWidth, bh = level.blockHeight
        let blocksAcross = (level.width + bw - 1) / bw, blocksDown = (level.height + bh - 1) / bh
        let step = max(1, Int(sqrt(Double(blocksAcross * blocksDown) / 64)))   // ~64 blocks sampled
        var by = 0
        while by < blocksDown {
            var bx = 0
            while bx < blocksAcross {
                let n = level.tiled ? vv_read_tile(handle.tiff, UInt32(bx * bw), UInt32(by * bh), raw, size)
                                    : vv_read_strip(handle.tiff, UInt32(by * bh), raw, size)
                if n > 0 {
                    let count = Int(n) / (spp * bytes)
                    let stride = max(1, count / 4096)
                    for i in Swift.stride(from: 0, to: count, by: stride) {
                        let v = sample(raw + i * spp * bytes, bits: Int(info.bits_per_sample), format: Int(info.sample_format))
                        if v.isFinite { values.append(v) }
                    }
                }
                bx += step
            }
            by += step
        }
        return Stretch.percentile(values, kind: Stretch.Kind(info))
    }
}

/// libtiff handles, one per concurrent reader.
final class HandlePool: @unchecked Sendable {
    // Sendable: `free` is guarded by `lock`; a handle is used by one thread at a time.
    let path: String
    private let lock = NSLock()
    private var free: [TIFFHandle] = []

    init(path: String) throws {
        self.path = path
        let first = try TIFFHandle(path: path)
        free.append(first)
    }

    func take() throws -> TIFFHandle {
        if let handle = lock.withLock({ free.popLast() }) { return handle }
        return try TIFFHandle(path: path)
    }

    func give(_ handle: TIFFHandle) { lock.withLock { free.append(handle) } }
}

final class TIFFHandle {
    let tiff: OpaquePointer
    var current: TIFFRegionSource.Directory?

    init(path: String) throws {
        guard let t = vv_open(path) else { throw DecodeError.unsupported }
        tiff = t
    }

    deinit { vv_close(tiff) }
}

/// Maps high-bit-depth samples to 8 bits (docs/TECH_SPEC.md §4.4).
public struct Stretch: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case unsigned(bits: Int), signed(bits: Int), float

        init(_ info: vv_dir_info) {
            switch info.sample_format {
            case 3: self = .float
            case 2: self = .signed(bits: Int(info.bits_per_sample))
            default: self = .unsigned(bits: Int(info.bits_per_sample))
            }
        }
    }

    public let low: Double
    public let high: Double
    public let kind: Kind

    /// The full range of the sample type (stretch off).
    public static func linear(for kind: Kind) -> Stretch {
        switch kind {
        case .unsigned(let bits): return Stretch(low: 0, high: pow(2, Double(min(bits, 32))) - 1, kind: kind)
        case .signed(let bits): return Stretch(low: -pow(2, Double(bits - 1)), high: pow(2, Double(bits - 1)) - 1, kind: kind)
        case .float: return Stretch(low: 0, high: 1, kind: kind)
        }
    }

    public static func percentile(_ values: [Double], kind: Kind, low lowP: Double = 0.02, high highP: Double = 0.98) -> Stretch {
        guard values.count > 16 else { return linear(for: kind) }
        let sorted = values.sorted()
        let lo = sorted[Int(Double(sorted.count - 1) * lowP)]
        var hi = sorted[Int(Double(sorted.count - 1) * highP)]
        if hi <= lo { hi = lo + 1 }
        return Stretch(low: lo, high: hi, kind: kind)
    }

    /// Lookup table for 8-bit signed input (index = value + 128).
    var lut8: [UInt8] { (0..<256).map { map(Double($0 - 128), lut: []) } }

    @inline(__always)
    func map(_ v: Double, lut: [UInt8]) -> UInt8 {
        let t = (v - low) / (high - low)
        guard t.isFinite else { return 0 }
        return UInt8(clamping: Int((min(max(t, 0), 1) * 255).rounded()))
    }
}
