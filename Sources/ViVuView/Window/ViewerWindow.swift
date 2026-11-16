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
        // The traffic lights appear with the hover title bar (M2); hidden until then.
        setTrafficLightsHidden(true)
        center()
    }

    func setTrafficLightsHidden(_ hidden: Bool) {
        for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            standardWindowButton(kind)?.animator().alphaValue = hidden ? 0 : 1
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Black view with a centered message: the "drop an image here" hint or an error.
final class MessageView: NSView {
    private let label = NSTextField(labelWithString: "")

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
