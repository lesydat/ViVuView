import Foundation

/// An image that can be read piece by piece, at any power-of-two downscale (docs/TECH_SPEC.md §4.3).
public protocol RegionSource: AnyObject, Sendable {
    var meta: ImageMeta { get }
    /// Level k is the image shrunk 2^k times; level 0 is full size. `maxLevel` is the coarsest useful level.
    var maxLevel: Int { get }
    /// Reads `rect` (level-0 pixels, stored space) shrunk to `outSize` by exact area mean.
    /// Blocking and thread-safe.
    func read(rect: PixelRect, outSize: PixelSize) throws -> PixelBuffer
}

public extension RegionSource {
    var fullSize: PixelSize { meta.storedSize }

    /// Size of the whole image at `level`.
    func levelSize(_ level: Int) -> PixelSize {
        PixelSize(width: max(1, (fullSize.width + (1 << level) - 1) >> level),
                  height: max(1, (fullSize.height + (1 << level) - 1) >> level))
    }

    /// Reads `rect` (level-0 pixels) at `level`.
    func read(rect: PixelRect, level: Int) throws -> PixelBuffer {
        let clipped = rect.intersection(PixelRect(size: fullSize))
        guard !clipped.isEmpty else { throw DecodeError.corrupt("vùng đọc rỗng") }
        let out = PixelSize(width: max(1, (clipped.width + (1 << level) - 1) >> level),
                            height: max(1, (clipped.height + (1 << level) - 1) >> level))
        return try read(rect: clipped, outSize: out)
    }

    /// Whole image fitted so its long side is at most `longSide` (exact area mean).
    func fit(longSide: Int) throws -> PixelBuffer {
        let scale = min(1, Double(longSide) / Double(fullSize.longSide))
        let out = PixelSize(width: max(1, Int((Double(fullSize.width) * scale).rounded())),
                            height: max(1, Int((Double(fullSize.height) * scale).rounded())))
        return try read(rect: PixelRect(size: fullSize), outSize: out)
    }

    static func maxLevel(for size: PixelSize, smallestLongSide: Int = 256) -> Int {
        var level = 0
        while (size.longSide >> (level + 1)) >= smallestLongSide { level += 1 }
        return level
    }
}

/// Box mapping for exact area-mean downscaling: output index i covers source [start(i), start(i+1)).
/// Every source pixel lands in exactly one output pixel (docs/TECH_SPEC.md §4.4: no sparse sampling).
public struct BoxMap: Sendable {
    public let starts: [Int]   // count = outCount + 1, relative to the region origin

    public init(sourceCount: Int, outCount: Int) {
        precondition(outCount > 0 && sourceCount >= outCount, "BoxMap only shrinks")
        starts = (0...outCount).map { $0 * sourceCount / outCount }
    }

    /// For each source index, its output index.
    public func inverse() -> [Int32] {
        var map = [Int32](repeating: 0, count: starts.last!)
        for i in 0..<(starts.count - 1) {
            for s in starts[i]..<starts[i + 1] { map[s] = Int32(i) }
        }
        return map
    }
}
