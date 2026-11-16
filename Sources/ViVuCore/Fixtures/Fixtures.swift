import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Deterministic synthetic test pictures (docs/TECH_SPEC.md §11.4): a "sky" with a gradient,
/// faint noise and point-like stars, so sparse sampling would visibly drop detail.
public enum FixtureContent {
    @inline(__always) static func hash(_ x: Int, _ y: Int, _ seed: Int) -> UInt32 {
        var h = UInt32(truncatingIfNeeded: x &* 374_761_393 &+ y &* 668_265_263 &+ seed &* 1_442_695_041)
        h = (h ^ (h >> 13)) &* 1_274_126_177
        return h ^ (h >> 16)
    }

    /// Fills `count` pixels of row `y` from column `x0` as interleaved RGB.
    public static func fillRow(y: Int, x0: Int, count: Int, width: Int, height: Int, seed: Int = 1,
                               into rgb: UnsafeMutablePointer<UInt8>) {
        let gy = Double(y) / Double(max(1, height - 1))
        for i in 0..<count {
            let x = x0 + i
            let gx = Double(x) / Double(max(1, width - 1))
            let h = hash(x, y, seed)
            let noise = Int(h & 15)
            var r = Int(20 + 60 * gx) + noise
            var g = Int(10 + 40 * gy) + noise
            var b = Int(40 + 50 * (1 - gx) * gy) + noise
            if h % 997 == 0 { r = 255; g = 250; b = 235 }          // star
            // Grid lines every 1000 px make alignment errors visible.
            if x % 1000 == 0 || y % 1000 == 0 { r = 200; g = 60; b = 60 }
            rgb[i * 3] = UInt8(min(r, 255)); rgb[i * 3 + 1] = UInt8(min(g, 255)); rgb[i * 3 + 2] = UInt8(min(b, 255))
        }
    }
}

/// Writes 8-bit RGB PSD/PSB files with a composite image only.
public enum PSBWriter {
    public enum Compression: Sendable { case raw, rle }

    /// `rowProvider(channel... )` not needed: content comes from `fill(y, rgb)` for full rows.
    public static func write(to url: URL, width: Int, height: Int, large: Bool, compression: Compression,
                             fill: @Sendable (_ y: Int, _ rgb: UnsafeMutablePointer<UInt8>) -> Void) throws {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        var header = Data()
        header.append(contentsOf: Array("8BPS".utf8))
        header.appendBE(UInt64(large ? 2 : 1), 2)
        header.append(contentsOf: [0, 0, 0, 0, 0, 0])
        header.appendBE(3, 2)                       // channels
        header.appendBE(UInt64(height), 4)
        header.appendBE(UInt64(width), 4)
        header.appendBE(8, 2)                       // depth
        header.appendBE(3, 2)                       // RGB
        header.appendBE(0, 4)                       // color mode data
        header.appendBE(0, 4)                       // image resources
        header.appendBE(0, large ? 8 : 4)           // layer and mask info
        header.appendBE(compression == .rle ? 1 : 0, 2)
        try handle.write(contentsOf: header)

        let countWidth = large ? 4 : 2
        let tableOffset = UInt64(header.count)
        if compression == .rle {
            try handle.write(contentsOf: Data(count: 3 * height * countWidth))
        }
        var counts = [Int](repeating: 0, count: 3 * height)
        let batch = 256
        for c in 0..<3 {
            var y = 0
            while y < height {
                let n = min(batch, height - y)
                let base = y
                var chunks = [[UInt8]](repeating: [], count: n)
                chunks.withUnsafeMutableBufferPointer { out in
                    let outBase = out.baseAddress!
                    nonisolated(unsafe) let outPtr = outBase
                    DispatchQueue.concurrentPerform(iterations: n) { r in
                        let rgb = UnsafeMutablePointer<UInt8>.allocate(capacity: width * 3)
                        defer { rgb.deallocate() }
                        fill(base + r, rgb)
                        var plane = [UInt8](repeating: 0, count: width)
                        for x in 0..<width { plane[x] = rgb[x * 3 + c] }
                        if compression == .rle {
                            var packed: [UInt8] = []
                            packed.reserveCapacity(width + width / 64)
                            plane.withUnsafeBufferPointer { PackBits.pack($0, into: &packed) }
                            outPtr[r] = packed
                        } else {
                            outPtr[r] = plane
                        }
                    }
                }
                var data = Data()
                for r in 0..<n {
                    counts[c * height + base + r] = chunks[r].count
                    data.append(contentsOf: chunks[r])
                }
                try handle.write(contentsOf: data)
                y += n
            }
        }
        if compression == .rle {
            var table = Data(capacity: counts.count * countWidth)
            for n in counts { table.appendBE(UInt64(n), countWidth) }
            try handle.seek(toOffset: tableOffset)
            try handle.write(contentsOf: table)
        }
    }
}

/// Writes tiled, uncompressed 8-bit RGB TIFF or BigTIFF, optionally with reduced-resolution IFDs
/// (overviews, the way GDAL stores them inside the file).
public enum TIFFWriter {
    public static func write(to url: URL, width: Int, height: Int, tile: Int = 512, bigTIFF: Bool, overviews: Int,
                             fill: @Sendable (_ level: Int, _ y: Int, _ levelWidth: Int, _ rgb: UnsafeMutablePointer<UInt8>) -> Void) throws {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        let header: Data = {
            var d = Data([0x49, 0x49])
            if bigTIFF { d.appendLE(43, 2); d.appendLE(8, 2); d.appendLE(0, 2); d.appendLE(0, 8) }
            else { d.appendLE(42, 2); d.appendLE(0, 4) }
            return d
        }()
        try handle.write(contentsOf: header)
        var offset = UInt64(header.count)

        struct Level { var width, height: Int; var tileOffsets: [UInt64]; var tileCounts: [UInt64] }
        var levels: [Level] = []
        for level in 0...overviews {
            let lw = max(1, width >> level), lh = max(1, height >> level)
            let across = (lw + tile - 1) / tile, down = (lh + tile - 1) / tile
            var info = Level(width: lw, height: lh, tileOffsets: [], tileCounts: [])
            let tileBytes = tile * tile * 3
            for ty in 0..<down {
                // Generate one band of `tile` rows, then cut it into tiles.
                var band = [UInt8](repeating: 0, count: across * tile * tile * 3)
                band.withUnsafeMutableBufferPointer { buf in
                    nonisolated(unsafe) let base = buf.baseAddress!
                    DispatchQueue.concurrentPerform(iterations: tile) { r in
                        let y = ty * tile + r
                        guard y < lh else { return }
                        let row = UnsafeMutablePointer<UInt8>.allocate(capacity: lw * 3)
                        defer { row.deallocate() }
                        fill(level, y, lw, row)
                        for tx in 0..<across {
                            let x0 = tx * tile, n = min(tile, lw - x0)
                            (base + tx * tileBytes + r * tile * 3).update(from: row + x0 * 3, count: n * 3)
                        }
                    }
                }
                try handle.write(contentsOf: band)
                for _ in 0..<across {
                    info.tileOffsets.append(offset)
                    info.tileCounts.append(UInt64(tileBytes))
                    offset += UInt64(tileBytes)
                }
            }
            levels.append(info)
        }

        // IFDs after the pixel data, chained level 0 → overviews.
        var ifdOffsets: [UInt64] = []
        var blob = Data()
        let entrySize = bigTIFF ? 20 : 12
        func ifdSize(_ entries: Int) -> Int { (bigTIFF ? 8 : 2) + entries * entrySize + (bigTIFF ? 8 : 4) }
        let entries = 12
        for (i, level) in levels.enumerated() {
            let ifdStart = offset + UInt64(blob.count)
            ifdOffsets.append(ifdStart)
            let arraysStart = ifdStart + UInt64(ifdSize(entries))
            let longType: UInt64 = bigTIFF ? 16 : 4, longWidth = bigTIFF ? 8 : 4
            let bpsOffset = arraysStart
            let offsetsOffset = bpsOffset + 6
            let countsOffset = offsetsOffset + UInt64(level.tileOffsets.count * longWidth)
            let nextIFD = countsOffset + UInt64(level.tileCounts.count * longWidth)
            var d = Data()
            d.appendLE(UInt64(entries), bigTIFF ? 8 : 2)
            func entry(_ tag: UInt64, _ type: UInt64, _ count: UInt64, _ value: UInt64) {
                d.appendLE(tag, 2); d.appendLE(type, 2); d.appendLE(count, bigTIFF ? 8 : 4); d.appendLE(value, bigTIFF ? 8 : 4)
            }
            entry(254, 4, 1, i == 0 ? 0 : 1)                 // NewSubfileType: reduced resolution
            entry(256, 4, 1, UInt64(level.width))
            entry(257, 4, 1, UInt64(level.height))
            // BitsPerSample 8,8,8: 6 bytes, inline in BigTIFF's 8-byte value, out of line in classic TIFF.
            entry(258, 3, 3, bigTIFF ? (8 | 8 << 16 | 8 << 32) : bpsOffset)
            entry(259, 3, 1, 1)                              // no compression
            entry(262, 3, 1, 2)                              // RGB
            entry(277, 3, 1, 3)
            entry(284, 3, 1, 1)                              // chunky
            entry(322, 3, 1, UInt64(tile))
            entry(323, 3, 1, UInt64(tile))
            entry(324, longType, UInt64(level.tileOffsets.count), level.tileOffsets.count == 1 ? level.tileOffsets[0] : offsetsOffset)
            entry(325, longType, UInt64(level.tileCounts.count), level.tileCounts.count == 1 ? level.tileCounts[0] : countsOffset)
            d.appendLE(i == levels.count - 1 ? 0 : nextIFD, bigTIFF ? 8 : 4)
            d.appendLE(8, 2); d.appendLE(8, 2); d.appendLE(8, 2)
            for o in level.tileOffsets { d.appendLE(o, longWidth) }
            for c in level.tileCounts { d.appendLE(c, longWidth) }
            blob.append(d)
        }
        try handle.write(contentsOf: blob)
        try handle.seek(toOffset: bigTIFF ? 8 : 4)
        var first = Data()
        first.appendLE(ifdOffsets[0], bigTIFF ? 8 : 4)
        try handle.write(contentsOf: first)
    }
}

/// Small images through ImageIO (JPEG, PNG, HEIC…), for folders of many files.
public enum ImageWriter {
    public static func write(_ buffer: PixelBuffer, to url: URL, type: UTType, quality: Double = 0.85,
                             orientation: UInt8 = 1) throws {
        guard let image = buffer.makeImage(),
              let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)
        else { throw DecodeError.unsupported }
        let props: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality,
                                      kCGImagePropertyOrientation: orientation]
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw DecodeError.corrupt("ghi ảnh thất bại") }
    }

    /// A synthetic picture with the fixture pattern, `label` decides the hue shift.
    public static func pattern(size: PixelSize, seed: Int) -> PixelBuffer {
        let buffer = PixelBuffer(width: size.width, height: size.height)
        let row = UnsafeMutablePointer<UInt8>.allocate(capacity: size.width * 3)
        defer { row.deallocate() }
        for y in 0..<size.height {
            FixtureContent.fillRow(y: y, x0: 0, count: size.width, width: size.width, height: size.height, seed: seed, into: row)
            let dst = buffer.data.advanced(by: y * buffer.bytesPerRow).assumingMemoryBound(to: UInt8.self)
            for x in 0..<size.width {
                let shift = UInt8(truncatingIfNeeded: seed &* 37)
                dst[x * 4] = row[x * 3 + 2] &+ shift
                dst[x * 4 + 1] = row[x * 3 + 1]
                dst[x * 4 + 2] = row[x * 3] &+ shift / 2
                dst[x * 4 + 3] = 255
            }
        }
        return buffer
    }
}

extension Data {
    mutating func appendBE(_ value: UInt64, _ width: Int) {
        for i in stride(from: width - 1, through: 0, by: -1) { append(UInt8(truncatingIfNeeded: value >> (8 * UInt64(i)))) }
    }

    mutating func appendLE(_ value: UInt64, _ width: Int) {
        for i in 0..<width { append(UInt8(truncatingIfNeeded: value >> (8 * UInt64(i)))) }
    }
}

/// Small committed fixtures for tests and smoke scripts (`vivu-bench test-fixtures Tests/Fixtures`).
public enum TestFixtures {
    /// 300×200 stored picture: red block top-left, green block top-right, blue band at the bottom,
    /// so every EXIF orientation looks different.
    public static func orientationPattern() -> PixelBuffer {
        let buffer = PixelBuffer(width: 300, height: 200)
        for y in 0..<200 {
            let row = buffer.data.advanced(by: y * buffer.bytesPerRow).assumingMemoryBound(to: UInt8.self)
            for x in 0..<300 {
                var (r, g, b): (UInt8, UInt8, UInt8) = (230, 230, 230)
                if y < 80 && x < 100 { (r, g, b) = (220, 30, 30) }
                if y < 80 && x >= 200 { (r, g, b) = (30, 200, 30) }
                if y >= 150 { (r, g, b) = (30, 30, 220) }
                row[x * 4] = b; row[x * 4 + 1] = g; row[x * 4 + 2] = r; row[x * 4 + 3] = 255
            }
        }
        return buffer
    }

    public static func write(to dir: URL) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let pattern = orientationPattern()
        for o in UInt8(1)...8 {
            try ImageWriter.write(pattern, to: dir.appendingPathComponent("orientation-\(o).jpg"), type: .jpeg,
                                  quality: 0.95, orientation: o)
        }
        try Data("this is not an image".utf8).write(to: dir.appendingPathComponent("not-an-image.jpg"))
        let small = ImageWriter.pattern(size: PixelSize(width: 640, height: 400), seed: 3)
        try ImageWriter.write(small, to: dir.appendingPathComponent("pattern.png"), type: .png)
    }
}
