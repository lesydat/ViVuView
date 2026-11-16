import Accelerate
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
        case .cannotOpen: String(localized: "không mở được file")
        case .unsupported: String(localized: "định dạng không hỗ trợ")
        case .corrupt(let why): String(localized: "file hỏng (\(why))")
        case .cancelled: String(localized: "đã huỷ")
        }
    }
}

/// The ImageIO paths of the staged pipeline (docs/TECH_SPEC.md §4.2, rules from docs/SPIKES.md).
/// Every result is in oriented space (EXIF orientation applied) and Display P3 BGRA8.
public enum ImageIODecoder {
    static var sourceOptions: CFDictionary { [kCGImageSourceShouldCache: false] as CFDictionary }

    public static func source(_ url: URL) throws -> CGImageSource {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { throw DecodeError.cannotOpen }
        guard CGImageSourceGetCount(source) > 0 else { throw DecodeError.unsupported }
        return source
    }

    /// Header-only facts.
    public static func meta(_ url: URL) throws -> ImageMeta {
        try meta(source: try source(url), url: url)
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

    /// Small thumbnail (for ThumbnailCache, the filmstrip and stage 0). Always decodes from the image if needed.
    public static func thumbnail(_ url: URL, maxPixel: Int) throws -> PixelBuffer {
        let source = try source(url)
        let meta = try meta(source: source, url: url)
        let request = decodeSize(longSide: meta.storedSize.longSide, target: maxPixel, uti: meta.uti)
        return try viaThumbnailAPI(source: source, index: 0, maxPixel: request, fromImage: true)
    }

    /// Stage 1: sharp at screen size. `screenLongSide` is the long side of the largest view, in device pixels.
    /// `preferEmbedded` (RAW): use the embedded preview instead of developing the RAW.
    public static func screenDecode(_ url: URL, screenLongSide: Int, preferEmbedded: Bool = false,
                                    index: Int = 0) throws -> (PixelBuffer, ImageMeta) {
        let source = try source(url)
        let meta = try meta(source: source, url: url)
        let long = meta.storedSize.longSide
        if preferEmbedded, UTType(meta.uti)?.conforms(to: .rawImage) == true {
            return (try viaThumbnailAPI(source: source, index: index, maxPixel: screenLongSide, fromImage: false), meta)
        }
        if meta.uti == UTType.jpeg.identifier {
            let step = decodeSize(longSide: long, target: screenLongSide, uti: meta.uti)
            if step >= long { return (try viaFullImage(source: source, index: index, orientation: meta.orientation), meta) }
            return (try viaThumbnailAPI(source: source, index: index, maxPixel: step, fromImage: true), meta)
        }
        if Double(long) <= Double(screenLongSide) * 1.5 {
            return (try viaFullImage(source: source, index: index, orientation: meta.orientation), meta)
        }
        return (try viaThumbnailAPI(source: source, index: index, maxPixel: screenLongSide, fromImage: true), meta)
    }

    /// Stage 2: full resolution.
    public static func fullDecode(_ url: URL, index: Int = 0) throws -> PixelBuffer {
        let source = try source(url)
        let meta = try meta(source: source, url: url)
        return try viaFullImage(source: source, index: index, orientation: meta.orientation)
    }

    /// ImageIO's own subsampling, for files too large for RAM at full size (tier L-B).
    public static func subsampledDecode(_ url: URL, factor: Int) throws -> PixelBuffer {
        let source = try source(url)
        let meta = try meta(source: source, url: url)
        return try viaThumbnailAPI(source: source, index: 0, maxPixel: max(1, meta.storedSize.longSide / factor), fromImage: true)
    }

    static func viaThumbnailAPI(source: CGImageSource, index: Int, maxPixel: Int, fromImage: Bool) throws -> PixelBuffer {
        let options: [CFString: Any] = [
            fromImage ? kCGImageSourceCreateThumbnailFromImageAlways : kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixel),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary) else {
            throw DecodeError.corrupt(String(localized: "ImageIO không decode được"))
        }
        return try PixelBuffer.converting(image, orientation: 1)
    }

    static func viaFullImage(source: CGImageSource, index: Int, orientation: UInt8) throws -> PixelBuffer {
        guard let image = CGImageSourceCreateImageAtIndex(source, index, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else {
            throw DecodeError.corrupt(String(localized: "ImageIO không decode được"))
        }
        return try PixelBuffer.converting(image, orientation: orientation)
    }

    /// Size to ask ImageIO for. JPEG: the smallest of full, ½, ¼, ⅛ that is still ≥ target, so the decoder
    /// shrinks inside the DCT; any other size makes ImageIO decode fully and resample (5× slower, docs/SPIKES.md).
    public static func decodeSize(longSide: Int, target: Int, uti: String) -> Int {
        guard target < longSide else { return longSide }
        guard uti == UTType.jpeg.identifier else { return target }
        var size = longSide
        for _ in 0..<3 where (size + 1) / 2 >= target { size = (size + 1) / 2 }
        return size
    }
}

public extension PixelBuffer {
    /// Converts any CGImage to BGRA8 premultiplied Display P3 with vImage (2–11 ms for 12 MP, docs/SPIKES.md),
    /// then applies the EXIF `orientation`. Falls back to drawing through CGContext if vImage refuses the format.
    static func converting(_ image: CGImage, orientation: UInt8) throws -> PixelBuffer {
        let stored = PixelBuffer(width: image.width, height: image.height)
        var target = vImage_Buffer(data: stored.data, height: vImagePixelCount(image.height),
                                   width: vImagePixelCount(image.width), rowBytes: stored.bytesPerRow)
        var format = vImage_CGImageFormat(bitsPerComponent: 8, bitsPerPixel: 32, colorSpace: PixelBuffer.colorSpace,
                                          bitmapInfo: CGBitmapInfo(rawValue: PixelBuffer.bitmapInfo))!
        let error = vImageBuffer_InitWithCGImage(&target, &format, nil, image, vImage_Flags(kvImageNoAllocate))
        if error != kvImageNoError {
            guard let context = stored.makeContext() else { throw DecodeError.corrupt("context") }
            context.setBlendMode(.copy)
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return try stored.oriented(orientation)
    }

    /// Returns the pixels with EXIF `orientation` applied (self when it is 1).
    func oriented(_ orientation: UInt8) throws -> PixelBuffer {
        guard (2...8).contains(orientation) else { return self }
        let swaps = Orientation.swapsAxes(orientation)
        var current = self
        if swaps || orientation == 3 {
            let rotation: Int
            switch orientation {
            case 3: rotation = kRotate180DegreesClockwise
            case 8: rotation = kRotate90DegreesCounterClockwise
            default: rotation = kRotate90DegreesClockwise     // 5, 6, 7
            }
            let out = swaps ? PixelBuffer(width: height, height: width) : PixelBuffer(width: width, height: height)
            var src = current.vImage, dst = out.vImage
            var black: [UInt8] = [0, 0, 0, 0]
            let error = vImageRotate90_ARGB8888(&src, &dst, UInt8(rotation), &black, vImage_Flags(kvImageNoFlags))
            guard error == kvImageNoError else { throw DecodeError.corrupt("xoay ảnh thất bại") }
            current = out
        }
        switch orientation {
        case 2, 5: try current.reflect(horizontal: true)
        case 4, 7: try current.reflect(horizontal: false)
        default: break
        }
        return current
    }

    internal var vImage: vImage_Buffer {
        vImage_Buffer(data: data, height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: bytesPerRow)
    }

    private func reflect(horizontal: Bool) throws {
        var buffer = vImage
        let error = horizontal
            ? vImageHorizontalReflect_ARGB8888(&buffer, &buffer, vImage_Flags(kvImageNoFlags))
            : vImageVerticalReflect_ARGB8888(&buffer, &buffer, vImage_Flags(kvImageNoFlags))
        guard error == kvImageNoError else { throw DecodeError.corrupt("lật ảnh thất bại") }
    }
}
