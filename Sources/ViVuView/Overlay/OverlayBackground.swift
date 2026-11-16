import AppKit

/// Background of every overlay (title bar, status bar, filmstrip, panels): system glass on macOS 26+,
/// a dark HUD blur on macOS 14–15. The only place allowed to use API newer than macOS 14
/// (docs/TECH_SPEC.md §1).
@MainActor
enum OverlayBackground {
    /// Wraps `content` in the background view and returns the container.
    static func make(content: NSView, cornerRadius: CGFloat = 0) -> NSView {
        if #available(macOS 26, *) {
            let glass = NSGlassEffectView()
            glass.style = .regular
            glass.cornerRadius = cornerRadius
            glass.tintColor = NSColor(white: 0, alpha: 0.35)
            glass.contentView = content
            glass.appearance = NSAppearance(named: .darkAqua)
            return glass
        } else {
            let blur = NSVisualEffectView()
            blur.material = .hudWindow
            blur.blendingMode = .withinWindow
            blur.state = .active
            blur.appearance = NSAppearance(named: .vibrantDark)
            blur.wantsLayer = true
            blur.layer?.cornerRadius = cornerRadius
            blur.layer?.masksToBounds = cornerRadius > 0
            content.frame = blur.bounds
            content.autoresizingMask = [.width, .height]
            blur.addSubview(content)
            return blur
        }
    }
}

/// Fades a view in or out (150 ms, docs/UI_SPEC.md §2.2).
@MainActor
func setVisible(_ view: NSView, _ visible: Bool, animated: Bool = true) {
    if visible { view.isHidden = false }
    guard animated else {
        view.alphaValue = visible ? 1 : 0
        view.isHidden = !visible
        return
    }
    NSAnimationContext.runAnimationGroup({ context in
        context.duration = 0.15
        view.animator().alphaValue = visible ? 1 : 0
    }, completionHandler: {
        MainActor.assumeIsolated {
            if !visible && view.alphaValue == 0 { view.isHidden = true }
        }
    })
}
