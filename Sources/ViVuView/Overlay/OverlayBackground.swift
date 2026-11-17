import AppKit

/// Background of every overlay (title bar, status bar, filmstrip, panels): system glass on macOS 26+,
/// a dark HUD blur on macOS 14–15. The only place allowed to use API newer than macOS 14
/// (docs/TECH_SPEC.md §1).
@MainActor
enum OverlayBackground {
    /// How see-through the bars are (Settings → Display, docs/UI_SPEC.md §10): glass style (macOS 26+) and
    /// how much black is laid over it, 0…1.
    struct Look: Equatable {
        var clearGlass = false
        var tint = 0.35
    }

    private(set) static var look = Look()
    private static let made = NSHashTable<NSView>.weakObjects()

    /// Glass styles exist on macOS 26+; before, only the tint applies (the settings hide the style choice).
    static var supportsGlassStyles: Bool {
        if #available(macOS 26, *) { return true } else { return false }
    }

    /// Changes every overlay already on screen and the ones made later.
    static func apply(_ newLook: Look) {
        guard newLook != look else { return }
        look = newLook
        for view in made.allObjects { style(view) }
    }

    /// Wraps `content` in the background view and returns the container. `behindWindow` is for a view that fills
    /// its own window (the shortcut sheet): the macOS 14–15 blur then samples the windows behind it.
    static func make(content: NSView, cornerRadius: CGFloat = 0, behindWindow: Bool = false) -> NSView {
        let view: NSView
        if #available(macOS 26, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = cornerRadius
            // Darkening is a black layer under the content: the glass's own tintColor with black made the bar
            // lighter and greyer, not darker (checked on screen).
            let holder = NSView()
            let dim = NSView()
            dim.wantsLayer = true
            dim.layer?.cornerRadius = cornerRadius
            dim.identifier = tintIdentifier
            for v in [dim, content] {
                v.frame = holder.bounds
                v.autoresizingMask = [.width, .height]
                holder.addSubview(v)
            }
            glass.contentView = holder
            glass.appearance = NSAppearance(named: .darkAqua)
            view = glass
        } else {
            let blur = NSVisualEffectView()
            blur.material = .hudWindow
            blur.blendingMode = behindWindow ? .behindWindow : .withinWindow
            blur.state = .active
            blur.appearance = NSAppearance(named: .vibrantDark)
            blur.wantsLayer = true
            blur.layer?.cornerRadius = cornerRadius
            blur.layer?.masksToBounds = cornerRadius > 0
            // Tint layer between the blur and the content.
            let tint = NSView(frame: blur.bounds)
            tint.autoresizingMask = [.width, .height]
            tint.wantsLayer = true
            tint.identifier = tintIdentifier
            blur.addSubview(tint)
            content.frame = blur.bounds
            content.autoresizingMask = [.width, .height]
            blur.addSubview(content)
            view = blur
        }
        made.add(view)
        style(view)
        return view
    }

    private static let tintIdentifier = NSUserInterfaceItemIdentifier("OverlayBackground.tint")

    private static func style(_ view: NSView) {
        let tint = NSColor(white: 0, alpha: min(max(look.tint, 0), 1))
        if #available(macOS 26, *), let glass = view as? NSGlassEffectView {
            glass.style = look.clearGlass ? .clear : .regular
            glass.contentView?.subviews.first { $0.identifier == tintIdentifier }?.layer?.backgroundColor = tint.cgColor
        } else {
            view.subviews.first { $0.identifier == tintIdentifier }?.layer?.backgroundColor = tint.cgColor
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
