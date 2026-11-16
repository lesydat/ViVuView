import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum DecodeError: Error, Equatable, CustomStringConvertible {
    case cannotOpen
    case unsupported
    case corrupt(String)
    case cancelled

    public var description: String {
        switch self {
        case .cannotOpen: "không mở được file"
        case .unsupported: "định dạng không hỗ trợ"
        case .corrupt(let why): "file hỏng (\(why))"
        case .cancelled: "đã huỷ"
        }
    }
}

/// The ImageIO paths of the staged pipeline (docs/TECH_SPEC.md §4.2).
/// Every result is already in oriented space (EXIF orientation applied) and Display P3.
public enum ImageIODecoder {
    static var sourceOptions: CFDictionary { [kCGImageSourceShouldCache: false] as CFDictionary }

    public static func source(_ url: URL) throws -> CGImageSource {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { throw DecodeError.cannotOpen }
        guard CGImageSourceGetCount(source) > 0 else { throw DecodeError.unsupported }
        return source
    }

    /// Header-only facts. Typically well under 1 ms once the file is in the page cache.
    public static func meta(_ url: URL) throws -> ImageMeta {
        let source = try source(url)
        return try meta(source: source, url: url)
    }

    public static func meta(source: CGImageSource, url: URL) throws -> ImageMeta {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let h = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue, w > 0, h > 0
        else { throw DecodeError.unsupported }
        let orientation = (props[kCGImagePropertyOrientation] as? NSNumber)?.uint8Value ?? 1
        let hasAlpha = (props[kCGImagePropertyHasAlpha] as? NSNumber)?.boolValue ?? false
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        return ImageMeta(storedSize: PixelSize(width: w, height: h), orientation: orientation,
                         frameCount: CGImageSourceGetCount(source), hasAlpha: hasAlpha,
                         uti: (CGImageSourceGetType(source) as String?) ?? "public.image",
                         fileSize: Int64(values?.fileSize ?? 0),
                         modificationDate: values?.contentModificationDate)
    }

    /// Stage 0: the thumbnail or preview embedded in the file, if any. Never decodes the full image.
    public static func embeddedPreview(_ url: URL, maxPixel: Int? = nil) -> PixelBuffer? {
        guard let source = try? source(url) else { return nil }
        return embeddedPreview(source: source, maxPixel: maxPixel)
    }

    public static func embeddedPreview(source: CGImageSource, maxPixel: Int? = nil) -> PixelBuffer? {
        var options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: false,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        if let maxPixel { options[kCGImageSourceThumbnailMaxPixelSize] = maxPixel }
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return PixelBuffer.drawing(image)
    }

    /// Stage 1: decoded so the long side is about `maxPixel` (screen size).
    /// For JPEG the request is rounded up to a ½, ¼, ⅛ step of the original so the decoder can
    /// downscale inside the DCT instead of resampling (docs/TECH_SPEC.md §4.2).
    /// `preferEmbedded` (RAW): use the embedded preview when present instead of developing the RAW.
    public static func screenDecode(_ url: URL, maxPixel: Int, preferEmbedded: Bool = false,
                                     index: Int = 0) throws -> PixelBuffer {
        let source = try source(url)
        let meta = try meta(source: source, url: url)
        let request = decodeSize(longSide: meta.storedSize.longSide, target: maxPixel, uti: meta.uti)
        return try thumbnail(source: source, index: index, maxPixel: request, alwaysFromImage: !preferEmbedded)
    }

    /// Stage 2: full resolution.
    public static func fullDecode(_ url: URL, index: Int = 0) throws -> PixelBuffer {
        let source = try source(url)
        let meta = try meta(source: source, url: url)
        return try thumbnail(source: source, index: index, maxPixel: meta.storedSize.longSide, alwaysFromImage: true)
    }

    /// Decode with ImageIO's own subsampling factor (2, 4 or 8); used for files too large for RAM at full size.
    public static func subsampledDecode(_ url: URL, factor: Int) throws -> PixelBuffer {
        let source = try source(url)
        let meta = try meta(source: source, url: url)
        let target = max(1, meta.storedSize.longSide / factor)
        return try thumbnail(source: source, index: 0, maxPixel: target, alwaysFromImage: true)
    }

    static func thumbnail(source: CGImageSource, index: Int, maxPixel: Int, alwaysFromImage: Bool) throws -> PixelBuffer {
        let options: [CFString: Any] = [
            alwaysFromImage ? kCGImageSourceCreateThumbnailFromImageAlways : kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixel),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary) else {
            throw DecodeError.corrupt("ImageIO không decode được")
        }
        guard let buffer = PixelBuffer.drawing(image) else { throw DecodeError.corrupt("ảnh rỗng") }
        return buffer
    }

    /// Size to ask ImageIO for. JPEG: the smallest of full, ½, ¼, ⅛ that is still ≥ target.
    public static func decodeSize(longSide: Int, target: Int, uti: String) -> Int {
        guard target < longSide else { return longSide }
        guard uti == UTType.jpeg.identifier else { return target }
        var size = longSide
        for _ in 0..<3 where (size + 1) / 2 >= target { size = (size + 1) / 2 }
        return size
    }
}
