import AppKit
import QuartzCore
import ViVuCore
import ViVuRender

/// Gallery state (docs/UI_SPEC.md §8).
@MainActor
final class GalleryState {
    var isOpen = false
    var layout: MasonryLayout?
    /// Content offset from the top, points.
    var scroll: Double = 0
    var selected = 0
    var hovered: Int?
    /// Index shown when the gallery opened (Esc / G go back to it).
    var openedFrom = 0
    var savedFrame: CGRect?
    var animation: (start: CFTimeInterval, entering: Bool, index: Int, from: CGRect, to: CGRect, done: () -> Void)?
    var typeahead = ""
    var typeaheadTime: TimeInterval = 0
    var pinchAccumulated = 0.0
    var header: GalleryHeader?
}

extension ViewerController {
    static let galleryAnimation = 0.22
    /// Same height as the main window's title bar, with the traffic lights in it (docs/UI_SPEC.md §8).
    var galleryHeaderHeight: Double { Double(window.titleBarHeight) }

    var galleryOpen: Bool { gallery.isOpen }

    /// Content area width/height in points.
    private var galleryViewSize: CGSize { content.bounds.size }

    private func galleryURL(_ i: Int) -> URL { nav.entries[i].url }

    func rebuildGalleryLayout(keepAnchor anchor: Int? = nil) {
        let oldY = anchor.flatMap { a in gallery.layout.map { Double($0.frames[a].minY) - gallery.scroll } }
        let aspects = nav.entries.map { thumbs.aspect(for: $0.url) }
        let layout = MasonryLayout(aspects: aspects, width: galleryViewSize.width, targetColumnWidth: settings.galleryColumnWidth,
                                   top: galleryHeaderHeight)
        gallery.layout = layout
        if let anchor, let oldY, anchor < layout.count {
            gallery.scroll = layout.clampScroll(Double(layout.frames[anchor].minY) - oldY, height: galleryViewSize.height)
        } else {
            gallery.scroll = layout.clampScroll(gallery.scroll, height: galleryViewSize.height)
        }
        requestGalleryThumbnails()
        metalView.setNeedsRender()
    }

    // MARK: Open / close

    func toggleGallery() {
        if gallery.isOpen { closeGallery(opening: gallery.openedFrom) } else { openGallery() }
    }

    func openGallery() {
        guard !gallery.isOpen, let index = nav.index, !nav.entries.isEmpty else { return }
        finishTransitionNow()
        let fromScreen = currentImageScreenRect()
        gallery.isOpen = true
        gallery.openedFrom = index
        gallery.selected = index
        gallery.hovered = nil
        strip.suppressed = true
        hideFilmstrip()
        hideChrome()
        setVisible(statusBar, false, animated: false)
        showGalleryHeader(true)
        window.setTrafficLightsHidden(false)
        defer { layoutInfoPanel() }
        if !isFullScreen {
            gallery.savedFrame = window.frame
            let full = (window.screen ?? NSScreen.main)?.visibleFrame ?? window.frame
            window.setFrame(full, display: true, animate: false)
        }
        rebuildGalleryLayout()
        guard let layout = gallery.layout else { return }
        gallery.scroll = layout.clampScroll(Double(layout.frames[index].midY) - galleryViewSize.height / 2, height: galleryViewSize.height)
        updateGalleryHeader()
        let from = fromScreen.map(viewRect(fromScreen:)) ?? cellRectInView(index)
        startGalleryAnimation(entering: true, index: index, from: from, to: cellRectInView(index)) {}
    }

    /// Leaves the gallery showing image `index` (the selected cell zooms up into the viewer).
    func closeGallery(opening index: Int) {
        guard gallery.isOpen, nav.entries.indices.contains(index) else { return }
        let size = thumbs.sizes[galleryURL(index)] ?? meta?.orientedSize ?? PixelSize(width: 3, height: 2)
        var targetScreen: CGRect
        if isFullScreen {
            let fit = Transition.aspectFit(size.cgSize, in: CGRect(origin: .zero, size: galleryViewSize))
            targetScreen = window.convertToScreen(content.convert(flip(fit), to: nil))
        } else {
            let center = gallery.savedFrame.map { CGPoint(x: $0.midX, y: $0.midY) } ?? CGPoint(x: window.frame.midX, y: window.frame.midY)
            let available = (window.screen ?? NSScreen.main)?.visibleFrame ?? window.frame
            let windowSize = WindowSizing.contentSize(image: size.cgSize, pointsPerPixel: pointsPerPixel,
                                                      available: available.size, minimum: ViewerWindow.minimumSize)
            let frame = fixedFrame ? (gallery.savedFrame ?? window.frame)
                                   : WindowSizing.frame(size: windowSize, center: center, available: available)
            targetScreen = Transition.aspectFit(size.cgSize, in: frame)
            gallery.savedFrame = frame
        }
        let to = viewRect(fromScreen: targetScreen)
        startGalleryAnimation(entering: false, index: index, from: cellRectInView(index), to: to) { [weak self] in
            self?.finishClosingGallery(index)
        }
    }

    private func finishClosingGallery(_ index: Int) {
        gallery.isOpen = false
        gallery.animation = nil
        thumbs.want([], client: "gallery")
        showGalleryHeader(false)
        window.setTrafficLightsHidden(!chromeVisible)
        strip.suppressed = false
        if !isFullScreen, let frame = gallery.savedFrame { window.setFrame(frame, display: false, animate: false) }
        if index != nav.index {
            go(to: index, direction: index > (nav.index ?? 0) ? 1 : -1)
        } else {
            resizeWindowToImage()
        }
        clampViewport()
        metalView.renderNow(synchronously: true)
        updateStatusVisibility()
        layoutInfoPanel()
    }

    // MARK: Animation

    private func startGalleryAnimation(entering: Bool, index: Int, from: CGRect, to: CGRect, done: @escaping () -> Void) {
        gallery.animation = (CACurrentMediaTime(), entering, index, from, to, done)
        metalView.animationStep = { [weak self] now in
            guard let self, let a = gallery.animation else { return false }
            if now - a.start >= Self.galleryAnimation {
                gallery.animation = nil
                DispatchQueue.main.async { a.done() }
                return false
            }
            return true
        }
        metalView.startAnimating()
    }

    private var galleryAnimationProgress: Double {
        guard let a = gallery.animation else { return 1 }
        return Transition.easeOut((CACurrentMediaTime() - a.start) / Self.galleryAnimation)
    }

    // MARK: Geometry helpers

    /// Cell rect in view points (y down), scrolled.
    func cellRectInView(_ i: Int) -> CGRect {
        guard let layout = gallery.layout, i < layout.count else { return .zero }
        return layout.frames[i].offsetBy(dx: 0, dy: -gallery.scroll)
    }

    /// Screen rect (y up) → content view points (y down).
    func viewRect(fromScreen rect: CGRect) -> CGRect {
        let inWindow = window.convertFromScreen(rect)
        let local = content.convert(inWindow, from: nil)
        return flip(local)
    }

    /// Flips a rect between y-up content coordinates and y-down view coordinates.
    private func flip(_ r: CGRect) -> CGRect {
        CGRect(x: r.minX, y: content.bounds.height - r.maxY, width: r.width, height: r.height)
    }

    /// The picture currently shown in the viewer, in screen coordinates.
    func currentImageScreenRect() -> CGRect? {
        guard let meta, texture != nil else { return nil }
        let vp = effectiveViewport
        let scale = metalView.backingScale
        let shown = Viewport.rotatedSize(meta.orientedSize, quarterTurns: vp.quarterTurns)
        let size = CGSize(width: shown.width * vp.scale / scale, height: shown.height * vp.scale / scale)
        let c = vp.viewPoint(CGPoint(x: Double(meta.orientedSize.width) / 2, y: Double(meta.orientedSize.height) / 2), view: viewSize)
        let topLeft = CGRect(x: c.x / scale - size.width / 2, y: c.y / scale - size.height / 2, width: size.width, height: size.height)
        return window.convertToScreen(content.convert(flip(topLeft), to: nil))
    }

    // MARK: Drawing

    func galleryScene(viewSize: CGSize) -> [Quad] {
        guard let layout = gallery.layout else { return [] }
        let scale = metalView.backingScale
        let p = galleryAnimationProgress
        let animation = gallery.animation
        let cellAlpha = animation.map { $0.entering ? p : 1 - p } ?? 1
        var quads: [Quad] = []
        let height = galleryViewSize.height
        for i in layout.visible(y0: gallery.scroll, y1: gallery.scroll + height) {
            if animation?.index == i { continue }   // drawn separately below
            let r = cellRectInView(i)
            let selected = i == gallery.selected && animation == nil
            quads.append(cellQuad(i, rect: r, scale: scale, viewSize: viewSize, alpha: cellAlpha,
                                  selected: selected, hovered: i == gallery.hovered))
            if selected {
                let px = CGRect(x: r.minX * scale, y: r.minY * scale, width: r.width * scale, height: r.height * scale)
                quads.append(SelectionRing.quad(around: px, cornerRadius: 4, scale: scale, viewSize: viewSize,
                                                alpha: Float(cellAlpha)))
            }
        }
        if let a = animation {
            let r = Transition.lerp(a.from, a.to, p)
            // The flying picture: the viewer's sharp texture when it is the current image, else the thumbnail.
            let tex = (a.index == nav.index ? texture : nil) ?? thumbs.texture(for: galleryURL(a.index))
            if let tex {
                let px = CGRect(x: r.minX * scale, y: r.minY * scale, width: r.width * scale, height: r.height * scale)
                let radius = Float(4 * scale * (a.entering ? p : 1 - p))
                quads.append(Quad.placed(texture: tex.texture, center: CGPoint(x: px.midX, y: px.midY), size: px.size,
                                         viewSize: viewSize, uvRect: cropUV(tex, aspect: r.width / max(r.height, 1)),
                                         cornerRadius: radius))
            }
        }
        return quads
    }

    private func cellQuad(_ i: Int, rect r: CGRect, scale: Double, viewSize: CGSize, alpha: Double,
                          selected: Bool, hovered: Bool) -> Quad {
        let px = CGRect(x: r.minX * scale, y: r.minY * scale, width: r.width * scale, height: r.height * scale)
        let a = Float(alpha)
        // The selected cell's mark is the ring drawn around it (SelectionRing); hover keeps a faint inner line.
        let border: Float = hovered && !selected ? Float(1 * scale) : 0
        let borderColor = SIMD4<Float>(0.6, 0.6, 0.6, 0.6) * a
        if let tex = thumbs.texture(for: galleryURL(i)) {
            return Quad.placed(texture: tex.texture, center: CGPoint(x: px.midX, y: px.midY), size: px.size, viewSize: viewSize,
                               uvRect: cropUV(tex, aspect: r.width / max(r.height, 1)), color: SIMD4(a, a, a, a),
                               cornerRadius: Float(4 * scale), borderWidth: border, borderColor: borderColor)
        }
        let g = Float(0.2) * a
        return Quad.placed(texture: nil, center: CGPoint(x: px.midX, y: px.midY), size: px.size, viewSize: viewSize,
                           color: SIMD4(g, g, g * 1.1, a), cornerRadius: Float(4 * scale), borderWidth: border, borderColor: borderColor)
    }

    /// Centered crop of a texture to `aspect` (cells clamp very tall or wide pictures).
    private func cropUV(_ tex: DecodedTexture, aspect: Double) -> CGRect {
        let t = Double(tex.texture.width) / Double(max(1, tex.texture.height))
        if t > aspect * 1.01 { let w = aspect / t; return CGRect(x: (1 - w) / 2, y: 0, width: w, height: 1) }
        if t < aspect / 1.01 { let h = t / aspect; return CGRect(x: 0, y: (1 - h) / 2, width: 1, height: h) }
        return CGRect(x: 0, y: 0, width: 1, height: 1)
    }

    /// Visible gallery cells that have their thumbnail, and all visible cells (scripts: `action thumbs`).
    func galleryThumbnailCoverage() -> (shown: Int, visible: Int) {
        guard gallery.isOpen, let layout = gallery.layout else { return (0, 0) }
        let cells = layout.visible(y0: gallery.scroll, y1: gallery.scroll + galleryViewSize.height)
        return (cells.filter { thumbs.texture(for: galleryURL($0)) != nil }.count, cells.count)
    }

    func requestGalleryThumbnails() {
        guard gallery.isOpen, let layout = gallery.layout else { return }
        let h = galleryViewSize.height
        let middle = gallery.scroll + h / 2
        let cells = layout.visible(y0: gallery.scroll - h / 2, y1: gallery.scroll + 1.5 * h)
            .sorted { abs(Double(layout.frames[$0].midY) - middle) < abs(Double(layout.frames[$1].midY) - middle) }
        thumbs.want(cells.map(galleryURL), client: "gallery")
    }

    // MARK: Input

    func galleryKeyDown(_ event: NSEvent) -> Bool {
        galleryKey(KeyBindings.Key(event: event), characters: event.charactersIgnoringModifiers ?? "",
                   modifiers: event.modifierFlags)
    }

    func galleryKey(_ key: KeyBindings.Key, characters chars: String, modifiers: NSEvent.ModifierFlags) -> Bool {
        let cmd = modifiers.contains(.command)
        guard let layout = gallery.layout, gallery.animation == nil else { return true }
        let count = layout.count
        switch key {
        case .left: selectCell(max(0, gallery.selected - 1))
        case .right: selectCell(min(count - 1, gallery.selected + 1))
        case .up: if let n = layout.neighbour(of: gallery.selected, up: true) { selectCell(n) }
        case .down: if let n = layout.neighbour(of: gallery.selected, up: false) { selectCell(n) }
        case .pageUp, .pageDown: pageGallery(down: key == .pageDown)
        case .home: selectCell(0)
        case .end: selectCell(count - 1)
        case .enter: closeGallery(opening: gallery.selected)
        case .escape: closeGallery(opening: gallery.openedFrom)
        case .space: closeGallery(opening: gallery.selected)
        default:
            if cmd && (chars == "+" || chars == "=") { changeColumnWidth(by: 1.25); return true }
            if cmd && chars == "-" { changeColumnWidth(by: 0.8); return true }
            if cmd { return false }
            if chars == "?" && gallery.typeahead.isEmpty { perform(.showShortcuts); return true }
            if !cmd && (chars == "g" || chars == "G") && gallery.typeahead.isEmpty { closeGallery(opening: gallery.openedFrom); return true }
            typeahead(chars)
        }
        return true
    }

    func selectCell(_ i: Int) {
        guard let layout = gallery.layout, layout.count > 0 else { return }
        gallery.selected = min(max(i, 0), layout.count - 1)
        gallery.scroll = layout.scrollToReveal(gallery.selected, scroll: gallery.scroll, height: galleryViewSize.height,
                                               topInset: galleryHeaderHeight)
        updateGalleryHeader()
        requestGalleryThumbnails()
        metalView.setNeedsRender()
    }

    private func pageGallery(down: Bool) {
        guard let layout = gallery.layout else { return }
        let h = galleryViewSize.height - galleryHeaderHeight
        gallery.scroll = layout.clampScroll(gallery.scroll + (down ? h : -h), height: galleryViewSize.height)
        let f = layout.frames[gallery.selected]
        let probe = CGPoint(x: f.midX, y: gallery.scroll + galleryViewSize.height / 2)
        let candidates = layout.visible(y0: gallery.scroll, y1: gallery.scroll + galleryViewSize.height)
        if let nearest = candidates.min(by: { hypot(layout.frames[$0].midX - probe.x, layout.frames[$0].midY - probe.y)
                                              < hypot(layout.frames[$1].midX - probe.x, layout.frames[$1].midY - probe.y) }) {
            gallery.selected = nearest
        }
        updateGalleryHeader()
        requestGalleryThumbnails()
        metalView.setNeedsRender()
    }

    /// Typing jumps to the first file whose name starts with what was typed (resets after 1 s).
    private func typeahead(_ chars: String) {
        guard !chars.isEmpty, chars.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if now - gallery.typeaheadTime > 1 { gallery.typeahead = "" }
        gallery.typeaheadTime = now
        gallery.typeahead += chars.lowercased()
        let prefix = gallery.typeahead
        if let i = nav.entries.firstIndex(where: { $0.name.lowercased().hasPrefix(prefix) }) { selectCell(i) }
    }

    func changeColumnWidth(by factor: Double) {
        settings.galleryColumnWidth = min(max(settings.galleryColumnWidth * factor, 120), 480)
        rebuildGalleryLayout(keepAnchor: gallery.selected)
    }

    func galleryPoint(_ event: NSEvent) -> CGPoint {
        let p = content.convert(event.locationInWindow, from: nil)
        return CGPoint(x: p.x, y: content.bounds.height - p.y + gallery.scroll)
    }

    func galleryMouseMoved(_ event: NSEvent) {
        let hit = gallery.layout?.index(at: galleryPoint(event))
        if hit != gallery.hovered {
            gallery.hovered = hit
            updateGalleryHeader()
            metalView.setNeedsRender()
        }
    }

    func galleryMouseUp(_ event: NSEvent) {
        guard gallery.animation == nil, let i = gallery.layout?.index(at: galleryPoint(event)) else { return }
        gallery.selected = i
        closeGallery(opening: i)
    }

    func galleryScroll(_ event: NSEvent) {
        guard let layout = gallery.layout else { return }
        let dy = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 40
        gallery.scroll = layout.clampScroll(gallery.scroll - dy, height: galleryViewSize.height)
        galleryMouseMoved(event)
        requestGalleryThumbnails()
        metalView.setNeedsRender()
    }

    /// Pinch changes the column width; pinching out past the largest size opens the cell under the fingers.
    func galleryMagnify(_ event: NSEvent) {
        if event.phase == .began { gallery.pinchAccumulated = 0 }
        gallery.pinchAccumulated += event.magnification
        if settings.galleryColumnWidth >= 480 && gallery.pinchAccumulated > 0.4,
           let i = gallery.layout?.index(at: galleryPoint(event)) {
            gallery.pinchAccumulated = 0
            closeGallery(opening: i)
            return
        }
        changeColumnWidth(by: 1 + event.magnification)
    }

    func galleryResized() {
        guard gallery.isOpen else { return }
        rebuildGalleryLayout(keepAnchor: gallery.selected)
        layoutGalleryHeader()
    }

    // MARK: Header

    private func showGalleryHeader(_ show: Bool) {
        if show && gallery.header == nil {
            let header = GalleryHeader(frame: .zero)
            header.onSize = { [weak self] bigger in self?.changeColumnWidth(by: bigger ? 1.25 : 0.8) }
            content.addSubview(header)
            gallery.header = header
        }
        gallery.header?.isHidden = !show
        layoutGalleryHeader()
    }

    private func layoutGalleryHeader() {
        let b = content.bounds
        gallery.header?.frame = CGRect(x: 0, y: b.height - galleryHeaderHeight, width: b.width, height: galleryHeaderHeight)
    }

    func updateGalleryHeader() {
        guard gallery.isOpen else { return }
        let folder = (nav.folder?.path as NSString?)?.abbreviatingWithTildeInPath ?? ""
        let focus = gallery.hovered ?? gallery.selected
        let name = nav.entries.indices.contains(focus) ? nav.entries[focus].name : ""
        gallery.header?.text = "\(folder) · " + String(localized: "\(nav.entries.count) ảnh") + " · \(name)"
    }
}

/// Top bar of the gallery: folder, count, focused file name, and cell size buttons.
@MainActor
final class GalleryHeader: NSView {
    private let label = NSTextField(labelWithString: "")
    var onSize: ((Bool) -> Void)?

    var text: String {
        get { label.stringValue }
        set { label.stringValue = newValue }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // Same type and layout as the viewer's title bar (TitleBarOverlay): centered title, buttons on the right.
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = NSColor(white: 1, alpha: 0.92)
        label.alignment = .center
        label.lineBreakMode = .byTruncatingMiddle
        label.translatesAutoresizingMaskIntoConstraints = false
        // Circled symbols at the title bar buttons' size: a bare "−" was too small to aim at.
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        func symbol(_ name: String) -> NSImage {
            NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config) ?? NSImage()
        }
        let smaller = NSButton(image: symbol("minus.circle"), target: self, action: #selector(smallerPressed))
        let bigger = NSButton(image: symbol("plus.circle"), target: self, action: #selector(biggerPressed))
        for b in [smaller, bigger] {
            b.isBordered = false
            b.contentTintColor = NSColor(white: 1, alpha: 0.85)
            b.toolTip = String(localized: "Cỡ ô (⌘− / ⌘+, pinch)")
            b.widthAnchor.constraint(equalToConstant: 24).isActive = true
        }
        let buttons = NSStackView(views: [smaller, bigger])
        buttons.spacing = 4
        buttons.translatesAutoresizingMaskIntoConstraints = false
        let holder = NSView()
        holder.addSubview(label)
        holder.addSubview(buttons)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: holder.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: holder.centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: holder.leadingAnchor, constant: 96),
            label.trailingAnchor.constraint(lessThanOrEqualTo: buttons.leadingAnchor, constant: -8),
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

    @objc private func smallerPressed() { onSize?(false) }
    @objc private func biggerPressed() { onSize?(true) }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { window?.performZoom(nil) } else { window?.performDrag(with: event) }
    }
}
