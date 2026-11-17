import CoreGraphics
import Foundation

/// Decoded pixels: BGRA8, premultiplied alpha, Display P3, page-aligned rows (docs/TECH_SPEC.md §2).
/// Memory layout per pixel is B, G, R, A, which matches `MTLPixelFormat.bgra8Unorm`.
///
/// Sendable: the buffer is only written while it is being produced by one decoder; once handed
/// to anyone else it is treated as immutable.
public final class PixelBuffer: @unchecked Sendable {
    public let width: Int
    public let height: Int
    public let bytesPerRow: Int
    public let data: UnsafeMutableRawPointer
    public var byteCount: Int { bytesPerRow * height }
    public var size: PixelSize { PixelSize(width: width, height: height) }

    public static let colorSpace: CGColorSpace = CGColorSpace(name: CGColorSpace.displayP3)!
    public static let bitmapInfo: UInt32 =
        CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue

    /// Allocates zeroed (transparent black) pixels.
    public init(width: Int, height: Int) {
        precondition(width > 0 && height > 0, "empty PixelBuffer")
        self.width = width
        self.height = height
        self.bytesPerRow = (width * 4 + 63) & ~63
        let count = bytesPerRow * height
        let page = Int(getpagesize())
        var pointer: UnsafeMutableRawPointer?
        guard posix_memalign(&pointer, page, max(count, page)) == 0, let pointer else {
            fatalError("out of memory allocating \(width)×\(height) PixelBuffer")
        }
        memset(pointer, 0, count)
        self.data = pointer
    }

    deinit { free(data) }

    /// A bitmap context drawing straight into these pixels.
    public func makeContext() -> CGContext? {
        CGContext(data: data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                  space: Self.colorSpace, bitmapInfo: Self.bitmapInfo)
    }

    /// Draws `image` scaled into the whole buffer.
    public static func drawing(_ image: CGImage, size: PixelSize? = nil) -> PixelBuffer? {
        let size = size ?? PixelSize(width: image.width, height: image.height)
        guard size.width > 0, size.height > 0 else { return nil }
        let buffer = PixelBuffer(width: size.width, height: size.height)
        guard let context = buffer.makeContext() else { return nil }
        context.interpolationQuality = .high
        context.setBlendMode(.copy)
        context.draw(image, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
        return buffer
    }

    /// A CGImage view of the pixels (copies; for tests, snapshots and encoders).
    public func makeImage() -> CGImage? { makeContext()?.makeImage() }

    /// Pixel at (x, y) from the top-left as (r, g, b, a).
    public func pixel(x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let p = data.advanced(by: y * bytesPerRow + x * 4).assumingMemoryBound(to: UInt8.self)
        return (p[2], p[1], p[0], p[3])
    }
}
