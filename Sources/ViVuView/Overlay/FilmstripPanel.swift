import AppKit
import QuartzCore
import ViVuCore
import ViVuRender

/// The one-row strip of thumbnails at the bottom of the screen, outside the main window, as wide as the
/// screen (docs/UI_SPEC.md §7). A non-activating panel so it never takes focus from the viewer.
@MainActor
final class FilmstripPanel: NSPanel {
    let stripView: MetalView
    private let host: FilmstripHostView
    private let thumbs: ThumbnailService
    private(set) var layout = FilmstripLayout(aspects: [], thumbHeight: 72)
    private var urls: [URL] = []
    private(set) var current: Int?
    /// Strip x shown at the left edge, points.
    private var offset: Double = 0
    private var offsetAnimation: (from: Double, to: Double, start: CFTimeInterval)?
    /// The user scrolled the strip by hand; it stops following the current image until the next change.
    private var browsing = false
    var onSelect: ((Int) -> Void)?
    /// Right-click on a thumbnail: the viewer goes to it and returns the picture's menu (docs/UI_SPEC.md §7).
    var onContextMenu: ((Int) -> NSMenu?)?
    var onMouseInside: ((Bool) -> Void)?
    static let verticalPadding: Double = 8

    init(renderer: Renderer, thumbs: ThumbnailService) {
        self.thumbs = thumbs
        stripView = MetalView(renderer: renderer, transparent: true)
        host = FilmstripHostView(frame: .zero)
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        hidesOnDeactivate = true
        becomesKeyOnlyIfNeeded = true
        isReleasedWhenClosed = false
        collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace, .ignoresCycle]
        let background = OverlayBackground.make(content: stripView)
        host.panel = self
        host.addSubview(background)
        background.frame = host.bounds
        background.autoresizingMask = [.width, .height]
        stripView.frame = background.bounds
        stripView.autoresizingMask = [.width, .height]
        contentView = host
        stripView.sceneProvider = { [weak self] size in self?.scene(size: size) ?? [] }
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    var panelHeight: Double { layout.thumbHeight + Self.verticalPadding * 2 }

    /// Places the panel at the bottom of `screen`'s visible area, full width.
    func place(on screen: NSScreen) {
        let visible = screen.visibleFrame
        setFrame(CGRect(x: visible.minX, y: visible.minY, width: visible.width, height: panelHeight), display: false)
    }

    func reload(urls: [URL], current: Int?, thumbHeight: Double) {
        self.urls = urls
        self.current = current
        layout = FilmstripLayout(aspects: urls.map { thumbs.aspect(for: $0) }, thumbHeight: thumbHeight)
        if let screen { place(on: screen) }
        if !browsing, let current { offset = layout.offset(centering: current, viewWidth: frame.width) }
        offset = layout.clampedOffset(offset, viewWidth: frame.width)
        requestThumbnails()
        stripView.setNeedsRender()
    }

    /// Image sizes arrived: rebuild widths, keep the current cell centered.
    func relayout() {
        reload(urls: urls, current: current, thumbHeight: layout.thumbHeight)
    }

    func setCurrent(_ index: Int?, animated: Bool) {
        current = index
        browsing = false
        guard let index, index < layout.count else { stripView.setNeedsRender(); return }
        let target = layout.offset(centering: index, viewWidth: frame.width)
        if animated && isVisible {
            offsetAnimation = (offset, target, CACurrentMediaTime())
            stripView.animationStep = { [weak self] now in self?.stepOffset(now) ?? false }
            stripView.startAnimating()
        } else {
            offset = target
            stripView.setNeedsRender()
        }
        requestThumbnails()
    }

    private func stepOffset(_ now: CFTimeInterval) -> Bool {
        guard let a = offsetAnimation else { return false }
        let t = min(1, (now - a.start) / 0.12)
        offset = a.from + (a.to - a.from) * Transition.easeOut(t)
        if t >= 1 { offsetAnimation = nil }
        return t < 1
    }

    /// Visible cells ± one screen, nearest to the middle first.
    func requestThumbnails() {
        let width = frame.width
        let range = layout.visible(from: offset - width, to: offset + width * 2)
        let middle = offset + width / 2
        let order = range.sorted { abs(layout.frame($0).midX - middle) < abs(layout.frame($1).midX - middle) }
        thumbs.want(order.map { urls[$0] }, client: "filmstrip")
    }

    func thumbnailArrived(_ url: URL) {
        guard isVisible else { return }
        stripView.setNeedsRender()
    }

    // MARK: Drawing

    private func scene(size: CGSize) -> [Quad] {
        let scale = Double(backingScaleFactor)
        let viewWidth = size.width / scale
        var quads: [Quad] = []
        for i in layout.visible(from: offset, to: offset + viewWidth) {
            let f = layout.frame(i)
            let x = (f.minX - offset) * scale
            let rect = CGRect(x: x, y: Self.verticalPadding * scale, width: f.width * scale, height: f.height * scale)
            let isCurrent = i == current
            if let tex = thumbs.texture(for: urls[i]) {
                let crop = cropUV(texture: tex, cellAspect: f.width / f.height)
                quads.append(Quad.placed(texture: tex.texture, center: CGPoint(x: rect.midX, y: rect.midY), size: rect.size,
                                         viewSize: size, uvRect: crop, cornerRadius: Float(4 * scale)))
            } else {
                quads.append(Quad.placed(texture: nil, center: CGPoint(x: rect.midX, y: rect.midY), size: rect.size,
                                         viewSize: size, color: SIMD4(0.22, 0.22, 0.24, 0.9), cornerRadius: Float(4 * scale)))
            }
            if isCurrent {
                quads.append(SelectionRing.quad(around: rect, cornerRadius: 4, scale: scale, viewSize: size, offset: 2.5))
            }
        }
        return quads
    }

    /// Texture rect that fills a cell of `cellAspect` (cropping the middle when the aspect was clamped).
    private func cropUV(texture: DecodedTexture, cellAspect: Double) -> CGRect {
        let aspect = Double(texture.texture.width) / Double(max(1, texture.texture.height))
        if aspect > cellAspect {
            let w = cellAspect / aspect
            return CGRect(x: (1 - w) / 2, y: 0, width: w, height: 1)
        } else if aspect < cellAspect {
            let h = aspect / cellAspect
            return CGRect(x: 0, y: (1 - h) / 2, width: 1, height: h)
        }
        return CGRect(x: 0, y: 0, width: 1, height: 1)
    }

    // MARK: Input

    func index(at point: NSPoint) -> Int? {
        layout.index(at: offset + point.x).flatMap { i in
            let f = layout.frame(i)
            return point.y >= Self.verticalPadding && point.y <= Self.verticalPadding + f.height ? i : nil
        }
    }

    fileprivate func clicked(at point: NSPoint) {
        guard let i = index(at: point) else { return }
        onSelect?(i)
    }

    fileprivate func contextMenu(at point: NSPoint) -> NSMenu? {
        guard let i = index(at: point) else { return nil }
        return onContextMenu?(i)
    }

    fileprivate func scrolled(_ event: NSEvent) {
        let delta = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) ? event.scrollingDeltaX : event.scrollingDeltaY
        let factor = event.hasPreciseScrollingDeltas ? 1.0 : 20.0
        browsing = true
        offsetAnimation = nil
        offset = layout.clampedOffset(offset - delta * factor, viewWidth: frame.width)
        requestThumbnails()
        stripView.setNeedsRender()
    }

    fileprivate func hovered(at point: NSPoint?) {
        host.toolTip = point.flatMap { index(at: $0) }.map { urls[$0].lastPathComponent }
        onMouseInside?(point != nil)
    }
}

/// Content view of the filmstrip panel: forwards clicks, scrolls and hover.
final class FilmstripHostView: NSView {
    weak var panel: FilmstripPanel?
    private var tracking: NSTrackingArea?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        MainActor.assumeIsolated { panel?.clicked(at: NSPoint(x: p.x, y: bounds.height - p.y)) }
    }

    override func scrollWheel(with event: NSEvent) { MainActor.assumeIsolated { panel?.scrolled(event) } }

    // The menu is built and shown inside the main-actor block (NSMenu is not Sendable, so it cannot be returned
    // out of it from `menu(for:)`).
    override func rightMouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        MainActor.assumeIsolated {
            guard let menu = panel?.contextMenu(at: NSPoint(x: p.x, y: bounds.height - p.y)) else { return }
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        }
    }

    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        MainActor.assumeIsolated { panel?.hovered(at: NSPoint(x: p.x, y: bounds.height - p.y)) }
    }

    override func mouseEntered(with event: NSEvent) { mouseMoved(with: event) }
    override func mouseExited(with event: NSEvent) { MainActor.assumeIsolated { panel?.hovered(at: nil) } }
}
