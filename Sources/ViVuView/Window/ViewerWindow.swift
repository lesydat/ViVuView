import AppKit

/// The single main window (docs/UI_SPEC.md §2.1): image only, transparent title bar, black background.
@MainActor
enum ViewerWindow {
    static let emptySize = NSSize(width: 480, height: 320)

    /// Window shown before any image is opened (docs/UI_SPEC.md §11).
    static func makeEmpty() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: emptySize),
            styleMask: [.titled, .fullSizeContentView, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = "ViVuView"
        window.backgroundColor = .black
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.contentView = EmptyStateView(frame: NSRect(origin: .zero, size: emptySize))
        window.center()
        return window
    }
}

/// Black view with the "drop an image here" hint.
final class EmptyStateView: NSView {
    private let label = NSTextField(labelWithString: String(localized: "Kéo ảnh vào đây hoặc nhấn ⌘O"))

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        label.textColor = NSColor(white: 1, alpha: 0.55)
        label.font = .systemFont(ofSize: 13)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}
