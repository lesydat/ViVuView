import AppKit
import ViVuCore

/// Draws SVG files with AppKit's own SVG support (NSImage, macOS 14+) for `VectorImage` in ViVuCore
/// (docs/TECH_SPEC.md §4.5). Runs on decode threads: each call loads its own NSImage, nothing is shared.
enum SVGRasterizer {
    static func install() {
        VectorImage.install(VectorImage.Renderer(size: { url in
            try load(url).size
        }, draw: { url, size in
            let image = try load(url)
            let pixels = PixelBuffer(width: size.width, height: size.height)
            guard let context = pixels.makeContext() else { throw DecodeError.corrupt("context") }
            context.interpolationQuality = .high
            let graphics = NSGraphicsContext(cgContext: context, flipped: false)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = graphics
            image.draw(in: NSRect(x: 0, y: 0, width: size.width, height: size.height),
                       from: .zero, operation: .sourceOver, fraction: 1)
            NSGraphicsContext.restoreGraphicsState()
            return pixels
        }))
    }

    private static func load(_ url: URL) throws -> NSImage {
        guard let image = NSImage(contentsOf: url), image.isValid, image.size.width > 0, image.size.height > 0 else {
            throw DecodeError.unsupported
        }
        return image
    }
}
