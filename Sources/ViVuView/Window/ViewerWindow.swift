import AppKit

/// The single main window (docs/UI_SPEC.md §2.1): image only, transparent title bar, black background.
/// Uses `.titled` (not borderless) so native full screen, tiling and resizing keep working.
@MainActor
final class ViewerWindow: NSWindow {
    static let emptySize = NSSize(width: 480, height: 320)
    static let minimumSize = NSSize(width: 320, height: 240)

    init() {
        super.init(contentRect: NSRect(origin: .zero, size: Self.emptySize),
                   styleMask: [.titled, .fullSizeContentView, .closable, .miniaturizable, .resizable],
                   backing: .buffered, defer: false)
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        title = "ViVuView"
        backgroundColor = .black
        isReleasedWhenClosed = false
        contentMinSize = Self.minimumSize
        collectionBehavior = [.fullScreenPrimary]
        tabbingMode = .disallowed
        // An empty toolbar gives the current system title bar: traffic lights inset from the corner instead of
        // the title-bar-only layout. Compact keeps the bar low (40pt on macOS 27, buttons centered in it); it draws
        // nothing and clicks under it still reach the content view. Kept in full screen too: hiding and showing it
        // around full screen left the bar at a different height afterwards.
        let toolbar = NSToolbar(identifier: "ViVuView.main")
        toolbar.allowsUserCustomization = false
        self.toolbar = toolbar
        toolbarStyle = .unifiedCompact
        titlebarSeparatorStyle = .none
        // The traffic lights appear with the hover title bar (M2); hidden until then.
        setTrafficLightsHidden(true)
        centerOnScreen()
    }

    /// Exactly in the middle of the screen's visible area (`NSWindow.center()` puts it above the middle).
    func centerOnScreen() {
        guard let area = (screen ?? NSScreen.main)?.visibleFrame else { center(); return }
        setFrameOrigin(NSPoint(x: (area.midX - frame.width / 2).rounded(), y: (area.midY - frame.height / 2).rounded()))
    }

    /// Height of the hover title bar = the system title bar with the compact toolbar (traffic lights centered in it).
    /// Measured while windowed; in full screen the last windowed value is kept.
    private var lastTitleBarHeight: CGFloat = 0
    var titleBarHeight: CGFloat {
        if !styleMask.contains(.fullScreen) {
            let measured = frame.height - contentLayoutRect.height
            if measured >= TitleBarOverlay.minimumHeight { lastTitleBarHeight = measured.rounded() }
        }
        return max(TitleBarOverlay.minimumHeight, lastTitleBarHeight)
    }

    /// Hidden with the hover chrome while windowed. In full screen the system shows the title bar when the pointer
    /// reaches the top of the screen, so the buttons stay visible there.
    func setTrafficLightsHidden(_ hidden: Bool) {
        let hidden = hidden && !styleMask.contains(.fullScreen)
        for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            standardWindowButton(kind)?.animator().alphaValue = hidden ? 0 : 1
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Centered message over the background: the "drop an image here" hint or an error.
final class MessageView: NSView {
    private let label = NSTextField(labelWithString: "")

    /// Dark text on the light gray background, light text otherwise.
    var onLightBackground = false {
        didSet { label.textColor = NSColor(white: onLightBackground ? 0 : 1, alpha: onLightBackground ? 0.55 : 0.6) }
    }

    var message: String {
        get { label.stringValue }
        set { label.stringValue = newValue; isHidden = newValue.isEmpty }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        label.textColor = NSColor(white: 1, alpha: 0.6)
        label.font = .systemFont(ofSize: 13)
        label.alignment = .center
        label.maximumNumberOfLines = 3
        label.lineBreakMode = .byWordWrapping
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -32),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
