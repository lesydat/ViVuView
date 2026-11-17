import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// One thumbnail kept compressed in RAM (docs/TECH_SPEC.md §7, tier 1). Nothing is ever written to disk.
public struct CompressedThumbnail: Sendable {
    public let data: Data
    /// Size of the thumbnail pixels.
    public let size: PixelSize
    /// Oriented size of the original image (for layouts).
    public let imageSize: PixelSize
}

/// Thread-safe RAM store of compressed thumbnails, LRU by bytes (default 384 MB ≈ 9,000 images).
public final class ThumbnailStore: @unchecked Sendable {
    // Sendable: all state is guarded by `lock`.
    private let lock = NSLock()
    private var cache: ByteLRU<URL, CompressedThumbnail>

    public static let longSide = 640

    public init(budgetBytes: Int) {
        cache = ByteLRU(budget: budgetBytes)
    }

    public func get(_ url: URL) -> CompressedThumbnail? { lock.withLock { cache.value(for: url) } }
    public func contains(_ url: URL) -> Bool { lock.withLock { cache.contains(url) } }
    public func put(_ thumb: CompressedThumbnail, for url: URL) {
        lock.withLock { _ = cache.insert(thumb, for: url, cost: thumb.data.count + 128) }
    }
    public func setBudget(_ bytes: Int) { lock.withLock { _ = cache.setBudget(bytes) } }
    public var totalBytes: Int { lock.withLock { cache.totalCost } }
    public var count: Int { lock.withLock { cache.count } }

    /// Decodes a 640 px thumbnail from the file and compresses it (JPEG q80, PNG when it has alpha).
    /// Returns the pixels too so the caller can upload them right away.
    public static func make(_ url: URL) throws -> (CompressedThumbnail, PixelBuffer) {
        // Huge TIFF/PSB: ImageIO would take seconds and gigabytes; the own reader uses overviews or one pass.
        if let own = SourceFactory.openOwnReader(url), let pixels = try? own.fit(longSide: longSide) {
            let data = try encode(pixels, alpha: false)
            return (CompressedThumbnail(data: data, size: pixels.size, imageSize: own.meta.orientedSize), pixels)
        }
        if VectorImage.isVector(url) {
            let (pixels, meta) = try VectorImage.render(url, longSide: longSide)
            return (CompressedThumbnail(data: try encode(pixels, alpha: true), size: pixels.size, imageSize: meta.orientedSize), pixels)
        }
        let source = try ImageIODecoder.source(url)
        let meta = try ImageIODecoder.meta(source: source, url: url)
        let request = ImageIODecoder.decodeSize(longSide: meta.storedSize.longSide, target: longSide, uti: meta.uti)
        var pixels = try ImageIODecoder.viaThumbnailAPI(source: source, index: 0, maxPixel: request, fromImage: true)
        if pixels.size.longSide > longSide * 3 / 2 {
            // A JPEG halving step can leave it up to 2× too big: shrink once more on the CPU.
            pixels = try pixels.scaled(toLongSide: longSide)
        }
        let data = try encode(pixels, alpha: meta.hasAlpha)
        return (CompressedThumbnail(data: data, size: pixels.size, imageSize: meta.orientedSize), pixels)
    }

    static func encode(_ pixels: PixelBuffer, alpha: Bool) throws -> Data {
        guard let image = pixels.makeImage() else { throw DecodeError.corrupt("thumbnail") }
        let data = NSMutableData()
        let type = alpha ? UTType.png : UTType.jpeg
        guard let dest = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else {
            throw DecodeError.corrupt("thumbnail")
        }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw DecodeError.corrupt("thumbnail") }
        return data as Data
    }

    /// Back to pixels (≈1 ms for a 640 px JPEG).
    public static func decode(_ thumb: CompressedThumbnail) throws -> PixelBuffer {
        guard let source = CGImageSourceCreateWithData(thumb.data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
        else { throw DecodeError.corrupt("thumbnail") }
        return try PixelBuffer.converting(image, orientation: 1)
    }
}

public extension PixelBuffer {
    /// High-quality shrink with vImage.
    func scaled(toLongSide target: Int) throws -> PixelBuffer {
        let f = Double(target) / Double(max(width, height))
        guard f < 1 else { return self }
        let out = PixelBuffer(width: max(1, Int((Double(width) * f).rounded())), height: max(1, Int((Double(height) * f).rounded())))
        var src = vImage, dst = out.vImage
        let error = vImageScale_ARGB8888(&src, &dst, nil, vImage_Flags(kvImageHighQualityResampling))
        guard error == kvImageNoError else { throw DecodeError.corrupt("thu nhỏ thất bại") }
        return out
    }
}

import Accelerate
