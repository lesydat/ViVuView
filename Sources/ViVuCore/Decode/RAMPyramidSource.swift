import Accelerate
import Foundation

/// A fully decoded image kept in RAM with halved levels (docs/TECH_SPEC.md §4.3, tiers M and L-B).
/// Pixels are already oriented, so stored space = oriented space. Reads are copies / vImage scales.
public final class RAMPyramidSource: RegionSource {
    public let meta: ImageMeta
    public let maxLevel: Int
    /// Level k = image shrunk 2^k times relative to `fullSize` (level 0 may itself be subsampled: `baseFactor`).
    private let levels: [PixelBuffer]
    /// How much smaller level 0 is than the real image (1, or 2/4/8 for tier L-B).
    public let baseFactor: Int

    public var byteCount: Int { levels.reduce(0) { $0 + $1.byteCount } }

    /// - Parameters:
    ///   - pixels: the decoded image (oriented), possibly subsampled by `baseFactor`.
    ///   - meta: facts of the real image; `meta.orientedSize` is the full size the viewer uses.
    public init(pixels: PixelBuffer, meta: ImageMeta, baseFactor: Int = 1, smallestLongSide: Int = 512) throws {
        var oriented = meta
        oriented.storedSize = meta.orientedSize
        oriented.orientation = 1
        self.meta = oriented
        self.baseFactor = baseFactor
        var levels = [pixels]
        while let last = levels.last, last.size.longSide / 2 >= smallestLongSide {
            let next = PixelBuffer(width: max(1, last.width / 2), height: max(1, last.height / 2))
            var src = last.vImage, dst = next.vImage
            let error = vImageScale_ARGB8888(&src, &dst, nil, vImage_Flags(kvImageHighQualityResampling))
            guard error == kvImageNoError else { throw DecodeError.corrupt("dựng pyramid thất bại") }
            levels.append(next)
        }
        self.levels = levels
        // Viewer levels are relative to the full image: level k of the viewer uses buffer k - log2(baseFactor).
        let baseShift = Int(log2(Double(max(1, baseFactor))))
        maxLevel = levels.count - 1 + baseShift
    }

    public func read(rect: PixelRect, outSize: PixelSize) throws -> PixelBuffer {
        let full = meta.storedSize
        let region = rect.intersection(PixelRect(size: full))
        guard !region.isEmpty else { throw DecodeError.corrupt("vùng đọc rỗng") }
        // Pick the finest buffer level that is still at least as detailed as the output.
        let shrink = Double(region.width) / Double(max(1, outSize.width))
        let baseShift = Int(log2(Double(max(1, baseFactor))))
        var k = max(0, Int(floor(log2(max(shrink, 1)))) - baseShift)
        k = min(k, levels.count - 1)
        let buffer = levels[k]
        let f = Double(full.width) / Double(buffer.width)
        let x0 = min(buffer.width - 1, Int(Double(region.x) / f))
        let y0 = min(buffer.height - 1, Int(Double(region.y) / f))
        let x1 = min(buffer.width, max(x0 + 1, Int((Double(region.maxX) / f).rounded(.up))))
        let y1 = min(buffer.height, max(y0 + 1, Int((Double(region.maxY) / f).rounded(.up))))
        let out = PixelBuffer(width: outSize.width, height: outSize.height)
        var src = vImage_Buffer(data: buffer.data.advanced(by: y0 * buffer.bytesPerRow + x0 * 4),
                                height: vImagePixelCount(y1 - y0), width: vImagePixelCount(x1 - x0), rowBytes: buffer.bytesPerRow)
        var dst = out.vImage
        if x1 - x0 == outSize.width && y1 - y0 == outSize.height {
            for row in 0..<outSize.height {
                memcpy(out.data.advanced(by: row * out.bytesPerRow), src.data.advanced(by: row * buffer.bytesPerRow), outSize.width * 4)
            }
        } else {
            let error = vImageScale_ARGB8888(&src, &dst, nil, vImage_Flags(kvImageHighQualityResampling))
            guard error == kvImageNoError else { throw DecodeError.corrupt("đọc vùng thất bại") }
        }
        return out
    }
}

/// How an image is shown, from its size (docs/TECH_SPEC.md §4.1). Thresholds live in `Tuning`.
public enum ImageTier: Equatable, Sendable {
    /// One texture.
    case single
    /// Decoded once into RAM as a pyramid, shown with tiles.
    case ramPyramid
    /// Too big for RAM at full size: decoded subsampled by `factor`, shown with tiles.
    case subsampled(factor: Int)

    public static func classify(_ size: PixelSize, maxTextureSide: Int, physicalMemory: UInt64 = ProcessInfo.processInfo.physicalMemory) -> ImageTier {
        if size.megapixels <= Tuning.singleTextureMegapixels && size.longSide <= maxTextureSide { return .single }
        let budget = Double(physicalMemory) / Tuning.pyramidMemoryDivisor
        let bytes = Double(size.area) * 4 * 4 / 3
        if bytes <= budget { return .ramPyramid }
        for f in [2, 4, 8, 16] where bytes / Double(f * f) <= budget { return .subsampled(factor: f) }
        return .subsampled(factor: 32)
    }
}
