import AppKit
import ViVuCore
import ViVuRender

/// A borderless, transparent, click-through window covering the whole screen, just above the main window.
/// During an image change it draws the old picture sliding out and the new one sliding in, so the motion is
/// not clipped by the window frame (docs/TECH_SPEC.md §6).
@MainActor
final class TransitionOverlay {
    let window: NSWindow
    let view: MetalView

    init(renderer: Renderer) {
        window = NSWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: true)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]
        view = MetalView(renderer: renderer, transparent: true)
        window.contentView = view
    }

    /// Covers `screen` and sits just above `parent`.
    func show(on screen: NSScreen, above parent: NSWindow) {
        if window.frame != screen.frame { window.setFrame(screen.frame, display: false) }
        window.level = parent.level
        window.order(.above, relativeTo: parent.windowNumber)
        view.renderNow(synchronously: true)
    }

    func hide() {
        window.orderOut(nil)
    }

    /// Screen rect (points, y up) → overlay view rect (device pixels, y down).
    func viewRect(fromScreen rect: CGRect) -> CGRect {
        let frame = window.frame
        let scale = Double(window.backingScaleFactor)
        return CGRect(x: (rect.minX - frame.minX) * scale, y: (frame.maxY - rect.maxY) * scale,
                      width: rect.width * scale, height: rect.height * scale)
    }
}

/// One image as drawn during a transition.
struct TransitionImage {
    var texture: DecodedTexture
    /// Where the picture sits at rest, in the drawing view's device pixels (unrotated size, center).
    var rect: CGRect
    var rotation: Double
}

/// State of a running image change animation (docs/UI_SPEC.md §4).
@MainActor
final class Transition {
    enum Style { case slideFade, fade }

    let style: Style
    /// +1 = going to the next image (old leaves to the left), −1 = previous.
    let direction: Int
    /// Distance the pictures travel, device pixels (35% of the screen width).
    let travel: Double
    let old: TransitionImage?
    var new: TransitionImage?
    /// Rect the new picture starts from (its aspect fitted into the old picture's rect).
    var newStartRect: CGRect?
    /// 0 = only the old picture, 1 = only the new one.
    var progress: Double = 0
    /// Progress at the moment the destination became known (navigation committed).
    var committedAt: Double?
    /// Drawn inside the main view (full screen) instead of the overlay.
    let inMainView: Bool

    init(style: Style, direction: Int, travel: Double, old: TransitionImage?, inMainView: Bool) {
        self.style = style
        self.direction = direction
        self.travel = travel
        self.old = old
        self.inMainView = inMainView
    }

    func quads(viewSize: CGSize) -> [Quad] {
        var quads: [Quad] = []
        let p = min(max(progress, 0), 1)
        let slide = style == .slideFade ? travel : 0
        if let old {
            var r = old.rect
            r.origin.x -= Double(direction) * slide * p
            quads.append(quad(old, rect: r, alpha: 1 - p, viewSize: viewSize))
        }
        if let new {
            let start = newStartRect ?? new.rect
            let end = committedAt == nil ? start : new.rect
            let c = committedAt ?? 0
            let t = c >= 1 ? 1 : max(0, (p - c) / (1 - c))
            var r = Self.lerp(start, end, t)
            r.origin.x += Double(direction) * slide * (1 - p)
            quads.append(quad(new, rect: r, alpha: p, viewSize: viewSize))
        }
        return quads
    }

    private func quad(_ image: TransitionImage, rect: CGRect, alpha: Double, viewSize: CGSize) -> Quad {
        let a = Float(alpha)
        return Quad.placed(texture: image.texture.texture, center: CGPoint(x: rect.midX, y: rect.midY), size: rect.size,
                           rotation: image.rotation, viewSize: viewSize, color: SIMD4(a, a, a, a))
    }

    static func lerp(_ a: CGRect, _ b: CGRect, _ t: Double) -> CGRect {
        CGRect(x: a.minX + (b.minX - a.minX) * t, y: a.minY + (b.minY - a.minY) * t,
               width: a.width + (b.width - a.width) * t, height: a.height + (b.height - a.height) * t)
    }

    /// `size` scaled to fit inside `rect`, centered.
    static func aspectFit(_ size: CGSize, in rect: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0 else { return rect }
        let f = min(rect.width / size.width, rect.height / size.height)
        let w = size.width * f, h = size.height * f
        return CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h)
    }

    static func easeOut(_ t: Double) -> Double { 1 - pow(1 - min(max(t, 0), 1), 3) }
}
