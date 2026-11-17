import AppKit
import ViVuCore

/// One line of basic facts at the bottom of the window (docs/UI_SPEC.md §2.3). Items are listed in
/// priority order; when the window is narrow the lowest-priority items are dropped from the right.
@MainActor
final class StatusBar: NSView {
    static let height: CGFloat = 24
    private let label = NSTextField(labelWithString: "")
    /// Shown while a click has pinned the bar, so it is clear why the bar stays (docs/UI_SPEC.md §2.3).
    private let pin = NSImageView()
    private var background: NSView!
    private(set) var items: [String] = []

    var pinned = false {
        didSet { pin.isHidden = !pinned; layoutText() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        label.textColor = NSColor(white: 1, alpha: 0.9)
        label.lineBreakMode = .byClipping
        label.translatesAutoresizingMaskIntoConstraints = false
        let holder = NSView()
        holder.addSubview(label)
        pin.image = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 10, weight: .regular))
        pin.contentTintColor = NSColor(white: 1, alpha: 0.7)
        pin.translatesAutoresizingMaskIntoConstraints = false
        pin.isHidden = true
        holder.addSubview(pin)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: holder.leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(lessThanOrEqualTo: pin.leadingAnchor, constant: -6),
            label.centerYAnchor.constraint(equalTo: holder.centerYAnchor),
            pin.trailingAnchor.constraint(equalTo: holder.trailingAnchor, constant: -10),
            pin.centerYAnchor.constraint(equalTo: holder.centerYAnchor),
        ])
        background = OverlayBackground.make(content: holder)
        background.frame = bounds
        background.autoresizingMask = [.width, .height]
        addSubview(background)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func update(items: [String]) {
        self.items = items
        layoutText()
    }

    override func layout() {
        super.layout()
        layoutText()
    }

    private func layoutText() {
        let font = label.font!
        let available = bounds.width - 20 - (pinned ? 22 : 0)
        var shown = items
        func width(_ parts: [String]) -> CGFloat {
            (parts.joined(separator: " · ") as NSString).size(withAttributes: [.font: font]).width
        }
        while shown.count > 1 && width(shown) > available { shown.removeLast() }
        label.stringValue = shown.joined(separator: " · ")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Small zoom percentage shown for a second at the bottom-right when the status bar is hidden.
@MainActor
final class ZoomBadge: NSView {
    private let label = NSTextField(labelWithString: "")
    private var hideTask: Task<Void, Never>?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        label.textColor = .white
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        let holder = NSView()
        holder.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: holder.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: holder.centerYAnchor),
        ])
        let background = OverlayBackground.make(content: holder, cornerRadius: 8)
        background.frame = bounds
        background.autoresizingMask = [.width, .height]
        addSubview(background)
        alphaValue = 0
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func flash(_ text: String) {
        label.stringValue = text
        setVisible(self, true, animated: false)
        hideTask?.cancel()
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self, !Task.isCancelled else { return }
            setVisible(self, false)
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
