import AppKit
import Metal
import ViVuCore
import ViVuRender

/// A decoded texture together with the image facts it belongs to. Metal textures are thread-safe,
/// so passing one between threads is fine.
struct DecodedTexture: @unchecked Sendable {
    let texture: MTLTexture
    let meta: ImageMeta
    /// Texture width relative to the oriented image width (1 = full resolution).
    let coverage: Double
}

/// Owns the main window and everything shown in it (docs/TECH_SPEC.md §5.4, docs/UI_SPEC.md §2).
/// Input and chrome live in ViewerController+Input.swift.
@MainActor
final class ViewerController: NSObject, NSWindowDelegate {
    let renderer: Renderer
    let scheduler = DecodeScheduler()
    let settings = Settings.shared
    let window: ViewerWindow
    let content: ViewerContentView
    let metalView: MetalView
    let messageView: MessageView
    let titleBar: TitleBarOverlay
    let statusBar: StatusBar
    let zoomBadge: ZoomBadge

    // Current image
    var currentURL: URL?
    var meta: ImageMeta?
    var texture: DecodedTexture?
    var viewport = Viewport(scale: 1, center: .zero, isFit: true)
    var infoTicket: DecodeTicket?
    var info: ImageInfo?
    private var loadWaiters: [CheckedContinuation<Void, Never>] = []
    var isLoading = false
    var lastError: String?
    /// Folder, position and decoded neighbours (ViewerController+Navigation.swift).
    let nav = NavigationState()
    /// Transition, bounce and gesture animation state (ViewerController+Transition.swift).
    let fx = EffectsState()
    /// Thumbnails (RAM only) for stage 0, the filmstrip and the gallery.
    let thumbs: ThumbnailService
    let strip = FilmstripState()
    let gallery = GalleryState()
    let detail = DetailState(budgetMB: Settings.shared.tileMemoryMB)

    // Window behaviour
    /// The user resized the window by hand: later images fit inside that frame (docs/UI_SPEC.md §2.1).
    var fixedFrame = false
    private var lastFitKey: TimeInterval = 0
    private var resizingProgrammatically = false

    // Chrome and mouse state (used by ViewerController+Input.swift)
    var chromeVisible = false
    var chromeHideTask: Task<Void, Never>?
    var statusPinned = false
    var mouseDownEvent: NSEvent?
    var dragged = false
    var pendingClick: Task<Void, Never>?

    init(renderer: Renderer) {
        self.renderer = renderer
        window = ViewerWindow()
        metalView = MetalView(renderer: renderer)
        messageView = MessageView(frame: .zero)
        content = ViewerContentView(frame: NSRect(origin: .zero, size: ViewerWindow.emptySize))
        titleBar = TitleBarOverlay(frame: NSRect(x: 0, y: 0, width: ViewerWindow.emptySize.width, height: TitleBarOverlay.height))
        statusBar = StatusBar(frame: NSRect(x: 0, y: 0, width: ViewerWindow.emptySize.width, height: StatusBar.height))
        zoomBadge = ZoomBadge(frame: NSRect(x: 0, y: 0, width: 72, height: 26))
        thumbs = ThumbnailService(renderer: renderer, scheduler: scheduler, budgetMB: Settings.shared.thumbnailMemoryMB)
        super.init()
        thumbs.onThumbnail.append { [weak self] url in
            self?.thumbnailArrivedForNavigation(url)
            if self?.galleryOpen == true { self?.metalView.setNeedsRender() }
        }
        thumbs.onSizes.append { [weak self] in
            guard let self, galleryOpen else { return }
            rebuildGalleryLayout(keepAnchor: gallery.hovered ?? gallery.selected)
        }
        content.controller = self
        content.addFill(metalView)
        content.addFill(messageView)
        content.addSubview(titleBar)
        content.addSubview(statusBar)
        content.addSubview(zoomBadge)
        layoutOverlays()
        window.contentView = content
        window.initialFirstResponder = content
        window.delegate = self
        titleBar.onCommand = { [weak self] in self?.perform($0) }
        for view in [titleBar, statusBar] as [NSView] { view.alphaValue = 0; view.isHidden = true }
        messageView.message = String(localized: "Kéo ảnh vào đây hoặc nhấn ⌘O")
        metalView.sceneProvider = { [weak self] size in self?.scene(viewSize: size) ?? [] }
        observeSettings()
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(content)
    }

    // MARK: Opening

    /// Long side of the largest screen in device pixels: the size stage 1 decodes to.
    var screenLongSide: Int {
        let sides = NSScreen.screens.map { Int(max($0.frame.width, $0.frame.height) * $0.backingScaleFactor) }
        return sides.max() ?? 3024
    }

    /// Shows a decoded image as the current one (called by navigation when the current slot has pixels).
    func showDecoded(_ decoded: DecodedTexture, url: URL, isNewImage: Bool) {
        texture = decoded
        meta = decoded.meta
        lastError = nil
        messageView.message = ""
        guard isNewImage else {
            // A sharper stage of the same image: keep the viewport, just redraw.
            metalView.setNeedsRender()
            return
        }
        let keep = settings.keepZoom && !viewport.isFit
        if !keep { viewport = Viewport.fit(image: decoded.meta.orientedSize, view: viewSize) }
        if settings.openSize == .always100 {
            viewport = Viewport(scale: unitScale, center: CGPoint(x: Double(decoded.meta.orientedSize.width) / 2,
                                                                  y: Double(decoded.meta.orientedSize.height) / 2))
            resizeWindowToImage(zoom: 1)
        } else if settings.openSize == .alwaysFit && !fixedFrame && !isFullScreen {
            fillScreenForFit()
        } else {
            resizeWindowToImage(zoom: keep ? viewport.scale / unitScale : nil)
        }
        metalView.setNeedsRender()
        updateStatus()
        updateStatusVisibility()
    }

    /// "Luôn vừa màn hình": small images are enlarged to fill the available area.
    private func fillScreenForFit() {
        guard let meta else { return }
        let image = Viewport.rotatedSize(meta.orientedSize, quarterTurns: viewport.quarterTurns)
        let f = min(availableFrame.width / image.width, availableFrame.height / image.height) / pointsPerPixel
        resizeWindowToImage(zoom: f)
        viewport = Viewport.fit(image: meta.orientedSize, view: viewSize, quarterTurns: viewport.quarterTurns)
    }

    func showError(_ error: String, url: URL) {
        texture = nil
        meta = nil
        lastError = error
        messageView.message = "⚠︎ \(url.lastPathComponent)\n\(error)"
        metalView.setNeedsRender()
        updateStatus()
    }

    /// Script support: waits until the current load finished (success or error).
    func waitForLoad() async {
        guard isLoading else { return }
        await withCheckedContinuation { loadWaiters.append($0) }
    }

    func finishLoad() {
        isLoading = false
        let waiters = loadWaiters
        loadWaiters = []
        waiters.forEach { $0.resume() }
        updateStatus()
    }

    // MARK: Geometry

    /// Device pixels per image pixel at 100% (docs/UI_SPEC.md §3).
    var unitScale: Double { settings.renderUnit.unitScale(backingScale: metalView.backingScale) }
    /// Points one image pixel takes at 100%.
    var pointsPerPixel: Double { unitScale / metalView.backingScale }
    var viewSize: CGSize { metalView.drawableSize }
    var isFullScreen: Bool { window.styleMask.contains(.fullScreen) }

    var fitScale: Double {
        guard let meta else { return 1 }
        return Viewport.fitScale(image: meta.orientedSize, view: viewSize, quarterTurns: viewport.quarterTurns)
    }

    /// Viewport with fit resolved for the current view size.
    var effectiveViewport: Viewport {
        guard let meta, viewport.isFit else { return viewport }
        return Viewport.fit(image: meta.orientedSize, view: viewSize, quarterTurns: viewport.quarterTurns)
    }

    var isZoomed: Bool { !viewport.isFit && abs(viewport.scale - fitScale) > fitScale * 0.001 }

    /// Available screen area for the window, in points.
    var availableFrame: CGRect {
        var frame = (window.screen ?? NSScreen.main)?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let strip = filmstripReservedHeight
        frame.origin.y += strip
        frame.size.height -= strip
        return frame
    }

    /// Sizes the window for the current image at fit, or at `zoom` (relative to 100%) when given.
    func resizeWindowToImage(zoom: Double? = nil) {
        guard let meta, !isFullScreen, !fixedFrame else { clampViewport(); return }
        let image = Viewport.rotatedSize(meta.orientedSize, quarterTurns: viewport.quarterTurns)
        let size = WindowSizing.contentSize(image: image, pointsPerPixel: pointsPerPixel, available: availableFrame.size,
                                            minimum: ViewerWindow.minimumSize, zoom: zoom)
        let center = window.isVisible ? CGPoint(x: window.frame.midX, y: window.frame.midY)
                                      : CGPoint(x: availableFrame.midX, y: availableFrame.midY)
        let frame = WindowSizing.frame(size: size, center: center, available: availableFrame)
        if frame != window.frame {
            resizingProgrammatically = true
            window.setFrame(frame, display: true, animate: false)
            resizingProgrammatically = false
        }
        clampViewport()
    }

    func clampViewport() {
        guard let meta else { return }
        if viewport.isFit {
            viewport = Viewport.fit(image: meta.orientedSize, view: viewSize, quarterTurns: viewport.quarterTurns)
        } else {
            viewport = viewport.clamped(image: meta.orientedSize, view: viewSize)
        }
    }

    // MARK: Zoom, pan, rotate

    /// Zooms to `scale` keeping `anchor` (view point, device pixels) still; grows the window with the zoom.
    func zoom(to scale: Double, anchor: CGPoint? = nil, flash: Bool = true, allowBelowFit: Bool = false) {
        guard let meta else { return }
        let range = ZoomSteps.limits(fitScale: fitScale, unitScale: unitScale)
        let target = min(max(scale, range.lowerBound), range.upperBound)
        let anchor = anchor ?? CGPoint(x: viewSize.width / 2, y: viewSize.height / 2)
        viewport = effectiveViewport.zoomed(to: target, anchor: anchor, view: viewSize)
        let shrinkingBelowFit = allowBelowFit && target < fitScale
        if !isFullScreen && !fixedFrame && !shrinkingBelowFit { resizeWindowToImage(zoom: target / unitScale) }
        if abs(target - fitScale) < fitScale * 0.001 {
            viewport = Viewport.fit(image: meta.orientedSize, view: viewSize, quarterTurns: viewport.quarterTurns)
        }
        clampViewport()
        metalView.setNeedsRender()
        updateStatus()
        if flash && !statusBarShown { zoomBadge.flash(zoomText) }
        viewportChanged()
    }

    func zoomStep(in zoomIn: Bool, anchor: CGPoint? = nil) {
        let next = ZoomSteps.step(from: effectiveViewport.scale, factor: settings.zoomStep, zoomIn: zoomIn,
                                  fitScale: fitScale, unitScale: unitScale)
        zoom(to: next, anchor: anchor)
    }

    func fitToWindow() {
        guard let meta else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastFitKey < 0.6 { fixedFrame = false }   // `\` twice: follow the image size again
        lastFitKey = now
        viewport = Viewport.fit(image: meta.orientedSize, view: viewSize, quarterTurns: viewport.quarterTurns)
        resizeWindowToImage()
        metalView.setNeedsRender()
        updateStatus()
        if !statusBarShown { zoomBadge.flash(zoomText) }
        viewportChanged()
    }

    func pan(by delta: CGVector) {
        guard meta != nil, !viewport.isFit else { return }
        viewport = viewport.panned(by: delta)
        clampViewport()
        metalView.setNeedsRender()
        viewportChanged()
    }

    func rotate(clockwise: Bool) {
        guard let meta else { return }
        let turns = viewport.quarterTurns + (clockwise ? 1 : 3)
        viewport = Viewport.fit(image: meta.orientedSize, view: viewSize, quarterTurns: turns)
        resizeWindowToImage()
        clampViewport()
        metalView.setNeedsRender()
        viewportChanged()
    }

    /// Zoom-dependent work: full-resolution decode and tiles (ViewerController+Detail.swift).
    func viewportChanged() {
        updateDetail()
    }

    var zoomText: String {
        viewport.isFit ? String(localized: "Vừa") + " \(Format.percent(effectiveViewport.scale / unitScale * 100))"
                       : Format.percent(viewport.scale / unitScale * 100)
    }

    // MARK: Commands

    func perform(_ command: Command) {
        if galleryOpen {
            switch command {
            case .next: selectCell(gallery.selected + 1)
            case .previous: selectCell(gallery.selected - 1)
            case .first: selectCell(0)
            case .last: selectCell(nav.entries.count - 1)
            case .toggleGallery, .escape: closeGallery(opening: gallery.openedFrom)
            case .zoomIn: changeColumnWidth(by: 1.25)
            case .zoomOut: changeColumnWidth(by: 0.8)
            case .toggleFullScreen: window.toggleFullScreen(nil)
            default: break
            }
            return
        }
        let panStep = max(viewSize.width, viewSize.height) * 0.1
        switch command {
        case .zoomIn: zoomStep(in: true)
        case .zoomOut: zoomStep(in: false)
        case .actualSize: zoom(to: unitScale)
        case .fit: fitToWindow()
        case .panLeft: pan(by: CGVector(dx: panStep, dy: 0))
        case .panRight: pan(by: CGVector(dx: -panStep, dy: 0))
        case .panUp: pan(by: CGVector(dx: 0, dy: panStep))
        case .panDown: pan(by: CGVector(dx: 0, dy: -panStep))
        case .rotateLeft: rotate(clockwise: false)
        case .rotateRight: rotate(clockwise: true)
        case .toggleFullScreen: window.toggleFullScreen(nil)
        case .followImageSize:
            fixedFrame = false
            resizeWindowToImage()
            metalView.setNeedsRender()
        case .copyImage: copyImage()
        case .copyPath:
            guard let url = currentURL else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url.path, forType: .string)
        case .revealInFinder:
            if let url = currentURL { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        case .escape:
            if isFullScreen { window.toggleFullScreen(nil) } else { window.performClose(nil) }
        case .next: navigate(by: 1, animated: true)
        case .previous: navigate(by: -1, animated: true)
        case .first: go(to: 0, direction: 1)
        case .last: go(to: nav.entries.count - 1, direction: -1)
        case .moveToTrash: moveCurrentToTrash()
        case .toggleFilmstrip: toggleFilmstrip()
        case .toggleGallery: toggleGallery()
        case .toggleInfo, .toggleStretch,
             .previousFrame, .nextFrame, .togglePlayback:
            performLater(command)
        }
    }

    /// Commands whose features arrive in later milestones.
    func performLater(_ command: Command) {
        NSSound.beep()
    }

    private func copyImage() {
        guard let url = currentURL else { return }
        let board = NSPasteboard.general
        board.clearContents()
        var objects: [NSPasteboardWriting] = [url as NSURL]
        // Very large files are copied as a file reference only, never decoded in full for the clipboard.
        if (meta?.storedSize.megapixels ?? 0) <= 100, let image = NSImage(contentsOf: url) { objects.insert(image, at: 0) }
        board.writeObjects(objects)
    }

    // MARK: Status bar

    /// Status bar items in priority order (docs/UI_SPEC.md §2.3).
    func updateStatus() {
        var items: [String] = []
        if isFullScreen, let url = currentURL { items.append(url.lastPathComponent) }
        if let position = positionText { items.append(position) }
        if let meta {
            items.append("\(meta.orientedSize.width)×\(meta.orientedSize.height)")
            items.append(Format.bytes(meta.fileSize))
            items.append(zoomText)
        }
        if let info {
            if let date = info.dateTaken ?? info.dateModified {
                items.append(date.formatted(date: .numeric, time: .shortened))
            }
            if let exposure = info.exposureSummary { items.append(exposure) }
            if let camera = info.camera { items.append(camera) }
        }
        if isLoading { items.append(String(localized: "đang nạp…")) }
        if let note = detailStatus { items.append(note) }
        if let lastError, meta == nil { items.append(lastError) }
        statusBar.update(items: items)
    }

    /// "12/384".
    var positionText: String? {
        guard nav.entries.count > 1, let i = nav.index else { return nil }
        return "\(i + 1)/\(nav.entries.count)"
    }

    // MARK: Settings

    private func observeSettings() {
        withObservationTracking({
            _ = settings.renderUnit
            _ = settings.statusBar
            _ = settings.background
            _ = settings.filmstrip
            _ = settings.filmstripThumb
            _ = settings.thumbnailMemoryMB
            _ = settings.tileMemoryMB
        }, onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.applySettings()
                self.observeSettings()
            }
        })
    }

    func applySettings() {
        thumbs.setBudget(megabytes: settings.thumbnailMemoryMB)
        detail.tiles.setBudget(settings.tileMemoryMB << 20)
        if settings.filmstrip == .always { showFilmstrip() } else if !strip.pinned { hideFilmstrip() }
        if filmstripVisible { showFilmstrip() }
        switch settings.background {
        case .black, .checkerboard: metalView.clearColor = SIMD4(0, 0, 0, 1)
        case .darkGray: metalView.clearColor = SIMD4(0.11, 0.11, 0.12, 1)
        }
        resizeWindowToImage()
        updateStatusVisibility()
        updateStatus()
        metalView.setNeedsRender()
    }

    // MARK: Window delegate

    func windowDidResize(_ notification: Notification) {
        layoutOverlays()
        galleryResized()
        clampViewport()
        metalView.setNeedsRender()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        if !resizingProgrammatically && !isFullScreen && meta != nil { fixedFrame = true }
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
        clampViewport()
        hideChrome()
        updateStatus()
        metalView.setNeedsRender()
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        resizeWindowToImage()
        updateStatus()
        metalView.setNeedsRender()
    }

    func windowDidChangeBackingProperties(_ notification: Notification) {
        resizeWindowToImage()
    }

    // MARK: Scene

    func scene(viewSize: CGSize) -> [Quad] {
        if gallery.isOpen { return galleryScene(viewSize: viewSize) }
        if let transition = fx.transition, transition.inMainView { return transition.quads(viewSize: viewSize) }
        guard let texture, let meta else { return [] }
        var vp = viewport
        if vp.isFit { vp = Viewport.fit(image: meta.orientedSize, view: viewSize, quarterTurns: vp.quarterTurns) }
        let size = CGSize(width: Double(meta.orientedSize.width) * vp.scale, height: Double(meta.orientedSize.height) * vp.scale)
        var center = vp.viewPoint(CGPoint(x: Double(meta.orientedSize.width) / 2, y: Double(meta.orientedSize.height) / 2), view: viewSize)
        center.x += bounceOffset
        let nearest = vp.scale / max(texture.coverage, 0.0001) >= 4 && detail.source == nil
        let base = Quad.placed(texture: texture.texture, center: center, size: size,
                               rotation: Double(vp.quarterTurns) * .pi / 2 + fx.liveRotation, viewSize: viewSize, nearest: nearest)
        return [base] + detailQuads(viewport: vp, viewSize: viewSize)
    }

    // MARK: Script support

    func performScriptKey(_ spec: String) throws {
        guard let (key, chars, mods) = KeyBindings.parse(spec) else { throw ScriptError.message("bad key \(spec)") }
        if galleryOpen {
            _ = galleryKey(key, characters: chars, modifiers: mods)
            return
        }
        guard let command = KeyBindings.command(key: key, characters: chars, modifiers: mods, context: keyContext) else {
            throw ScriptError.message("key \(spec) does nothing")
        }
        perform(command)
    }

    func performScriptAction(_ name: String) throws {
        switch name {
        case "hover": mouseMoved()
        case "unhover": mouseExited()
        case "click": toggleStatusPin()
        default:
            guard let command = Command(rawValue: name) else { throw ScriptError.message("unknown action \(name)") }
            perform(command)
        }
    }

    func scriptState() -> String {
        let f = window.frame
        return "image=\(currentURL?.lastPathComponent ?? "-") pos=\(positionText ?? "-") size=\(meta.map { "\($0.orientedSize)" } ?? "-") "
            + "scale=\(String(format: "%.4f", effectiveViewport.scale)) zoom=\(zoomText) fit=\(viewport.isFit) "
            + "turns=\(viewport.quarterTurns) window=\(Int(f.width))x\(Int(f.height)) fixed=\(fixedFrame) "
            + "status=\(statusBarShown) gallery=\(galleryOpen ? "open" : "closed") sel=\(gallery.selected + 1) "
            + "detail=\(detailDescription) "
            + "filmstrip=\(filmstripVisible ? "shown" : "hidden") transition=\(isTransitioning ? "running" : "idle") alpha=\(window.alphaValue) "
            + "error=\(lastError ?? "-")"
    }

    var detailDescription: String {
        if detail.source != nil { return "tiles(\(detail.tiles.count))" }
        if detail.isBuilding { return "building" }
        if let texture, texture.coverage >= 0.999 { return "full" }
        return "screen"
    }

    /// The window content as an image: the Metal scene with the visible overlays drawn on top.
    func snapshot() -> NSBitmapImageRep? {
        let bounds = content.bounds
        guard let rep = content.bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.black.setFill()
        bounds.fill()
        if let scene = metalView.snapshotImage() {
            NSGraphicsContext.current?.cgContext.draw(scene, in: metalView.frame)
        }
        for overlay in content.subviews where overlay !== metalView && !overlay.isHidden && overlay.alphaValue > 0 {
            // Glass does not render into bitmaps; draw a dark stand-in behind the overlay's contents.
            if overlay === titleBar || overlay === statusBar {
                NSColor(white: 0.12, alpha: 0.85).setFill()
                overlay.frame.fill()
            }
            guard let overlayRep = overlay.bitmapImageRepForCachingDisplay(in: overlay.bounds) else { continue }
            overlay.cacheDisplay(in: overlay.bounds, to: overlayRep)
            overlayRep.draw(in: overlay.frame, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }
}
