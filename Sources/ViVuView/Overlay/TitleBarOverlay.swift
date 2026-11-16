import AppKit

/// Hover title bar (docs/UI_SPEC.md §2.2): file name in the middle, info / gallery / filmstrip
/// buttons on the right. The standard traffic lights sit on top of it on the left.
@MainActor
final class TitleBarOverlay: NSView {
    static let height: CGFloat = 28
    private let titleLabel = NSTextField(labelWithString: "")
    var onCommand: ((Command) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = NSColor(white: 1, alpha: 0.92)
        titleLabel.alignment = .center
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        let holder = NSView()
        holder.addSubview(titleLabel)
        let buttons = NSStackView(views: [
            button("info.circle", String(localized: "Thông tin (I)"), .toggleInfo),
            button("square.grid.2x2", String(localized: "Gallery (G)"), .toggleGallery),
            button("film", String(localized: "Filmstrip (T)"), .toggleFilmstrip),
        ])
        buttons.spacing = 4
        buttons.translatesAutoresizingMaskIntoConstraints = false
        holder.addSubview(buttons)
        NSLayoutConstraint.activate([
            titleLabel.centerXAnchor.constraint(equalTo: holder.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: holder.centerYAnchor),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: holder.leadingAnchor, constant: 80),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: buttons.leadingAnchor, constant: -8),
            buttons.trailingAnchor.constraint(equalTo: holder.trailingAnchor, constant: -8),
            buttons.centerYAnchor.constraint(equalTo: holder.centerYAnchor),
        ])
        let background = OverlayBackground.make(content: holder)
        background.frame = bounds
        background.autoresizingMask = [.width, .height]
        addSubview(background)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    var title: String {
        get { titleLabel.stringValue }
        set { titleLabel.stringValue = newValue }
    }

    private func button(_ symbol: String, _ tip: String, _ command: Command) -> NSButton {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip) ?? NSImage()
        let button = NSButton(image: image, target: self, action: #selector(pressed(_:)))
        button.isBordered = false
        button.contentTintColor = NSColor(white: 1, alpha: 0.85)
        button.toolTip = tip
        button.identifier = NSUserInterfaceItemIdentifier(command.rawValue)
        button.widthAnchor.constraint(equalToConstant: 22).isActive = true
        return button
    }

    @objc private func pressed(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue, let command = Command(rawValue: raw) else { return }
        onCommand?(command)
    }

    /// Dragging the bar moves the window, like a real title bar.
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { window?.performZoom(nil) } else { window?.performDrag(with: event) }
    }
}
