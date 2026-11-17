import AppKit
import ViVuRender

/// The mark of the selected cell (gallery) and the current thumbnail (filmstrip): a ring in the system accent
/// color drawn just outside the picture, on the dark background, so it shows on white pictures too
/// (docs/UI_SPEC.md §7, §8). A white border inside the picture disappeared on white images.
@MainActor
enum SelectionRing {
    /// Points between the picture's edge and the ring, and the ring's width.
    static let offset = 3.0
    static let width = 2.0

    static func quad(around rect: CGRect, cornerRadius: Double, scale: Double, viewSize: CGSize,
                     alpha: Float = 1, offset: Double = offset, width: Double = width) -> Quad {
        let grow = offset * scale
        let ring = rect.insetBy(dx: -grow, dy: -grow)
        return Quad.placed(texture: nil, center: CGPoint(x: ring.midX, y: ring.midY), size: ring.size, viewSize: viewSize,
                           color: SIMD4(0, 0, 0, 0), cornerRadius: Float((cornerRadius + offset) * scale),
                           borderWidth: Float(width * scale), borderColor: color * alpha)
    }

    /// Premultiplied accent color (follows System Settings → Appearance → Accent color).
    static var color: SIMD4<Float> {
        let c = NSColor.controlAccentColor.usingColorSpace(.displayP3) ?? .systemBlue
        return SIMD4(Float(c.redComponent), Float(c.greenComponent), Float(c.blueComponent), 1)
    }
}
