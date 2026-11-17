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
    let infoPanelState = InfoState()
    let animation = AnimationState()
    private var memoryWatcher: MemoryPressureWatcher?
    var memoryLevel: MemoryPressureWatcher.Level { memoryWatcher?.level ?? .normal }

    // Window behaviour
    /// The user resized the window by hand: later images fit inside that frame (docs/UI_SPEC.md §2.1).
    var fixedFrame = false
    /// Set by `open(_:)`: the next window resize centers the window on the screen.
    var centerOnNextResize = true
    /// Sort order the folder was last scanned with.
    var appliedSort = "\(Settings.shared.sortKey.rawValue)/\(Settings.shared.sortAscending)"
    private var lastFitKey: TimeInterval = 0
    private var resizingProgrammatically = false
    /// Entering or leaving full screen: the system's own resize must not count as the user fixing the frame.
    private var fullScreenTransition = false

    // Chrome and mouse state (used by ViewerController+Input.swift)
    var chromeVisible = false
    var chromeHideTask: Task<Void, Never>?
    var statusPinned = false
    var mouseDownEvent: NSEvent?
    var dragged = false
    var clickActivatesWindow = false
    /// Screen position of the last pointer event that showed the chrome.
    var lastPointer: CGPoint?
    /// Scripts drive hover themselves (ScriptRunner).
    var ignoresRealPointer = false
    var pendingClick: Task<Void, Never>?
    /// Present while the translucent background is chosen (`applyBackground`).
    var backdrop: NSVisualEffectView?

    init(renderer: Renderer) {
        self.renderer = renderer
        window = ViewerWindow()
        metalView = MetalView(renderer: renderer)
        messageView = MessageView(frame: .zero)
        content = ViewerContentView(frame: NSRect(origin: .zero, size: ViewerWindow.emptySize))
        titleBar = TitleBarOverlay(frame: NSRect(x: 0, y: 0, width: ViewerWindow.emptySize.width, height: TitleBarOverlay.minimumHeight))
        statusBar = StatusBar(frame: NSRect(x: 0, y: 0, width: ViewerWindow.emptySize.width, height: StatusBar.height))
        zoomBadge = ZoomBadge(frame: NSRect(x: 0, y: 0, width: 72, height: 26))
        thumbs = ThumbnailService(renderer: renderer, scheduler: scheduler, budgetMB: Settings.shared.effectiveThumbnailMemoryMB)
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
        messageView.message = String(localized: "Kéo ảnh vào đây, nhấn đúp hoặc ⌘O để mở")
        metalView.sceneProvider = { [weak self] size in self?.scene(viewSize: size) ?? [] }
        observeSettings()
        // The stored background from the first frame (before, only a later settings change applied it).
        applyBackground()
        memoryWatcher = MemoryPressureWatcher { [weak self] level in self?.memoryPressureChanged(level) }
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(content)
        layoutInfoPanel()
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
            animationImageShown()
            return
        }
        defer { animationImageShown() }
        let keep = settings.keepZoom && !viewport.isFit
        if !keep { viewport = fitted(decoded.meta.orientedSize, view: viewSize, turns: 0) }
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
        viewport = fitted(meta.orientedSize, view: viewSize, turns: viewport.quarterTurns)
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
        return fitted(meta.orientedSize, view: viewSize, turns: viewport.quarterTurns).scale
    }

    /// Fit viewport. Unless "Luôn vừa màn hình" is chosen, small images are not enlarged past 100%
    /// (the window may be larger than the image because of its minimum size or full screen).
    func fitted(_ image: PixelSize, view: CGSize, turns: Int) -> Viewport {
        var vp = Viewport.fit(image: image, view: view, quarterTurns: turns)
        // Vectors have no native resolution: they always fill the window.
        if settings.openSize != .alwaysFit && meta?.isVector != true { vp.scale = min(vp.scale, unitScale) }
        return vp
    }

    /// Viewport with fit resolved for the current view size.
    var effectiveViewport: Viewport {
        guard let meta, viewport.isFit else { return viewport }
        return fitted(meta.orientedSize, view: viewSize, turns: viewport.quarterTurns)
    }

    /// The picture is larger than the view, so there is something to pan (arrows pan instead of changing image).
    var isZoomed: Bool {
        guard let meta, !viewport.isFit else { return false }
        let shown = Viewport.rotatedSize(meta.orientedSize, quarterTurns: viewport.quarterTurns)
        return shown.width * viewport.scale > viewSize.width + 1 || shown.height * viewport.scale > viewSize.height + 1
    }

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
        // A file the user opens lands in the middle of the screen; browsing keeps the window where it is.
        let center = window.isVisible && !centerOnNextResize ? CGPoint(x: window.frame.midX, y: window.frame.midY)
                                                             : CGPoint(x: availableFrame.midX, y: availableFrame.midY)
        centerOnNextResize = false
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
            viewport = fitted(meta.orientedSize, view: viewSize, turns: viewport.quarterTurns)
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
            viewport = fitted(meta.orientedSize, view: viewSize, turns: viewport.quarterTurns)
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
        viewport = fitted(meta.orientedSize, view: viewSize, turns: viewport.quarterTurns)
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
        viewport = fitted(meta.orientedSize, view: viewSize, turns: turns)
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
        if command == .showShortcuts {
            ShortcutsPanel.shared.toggle(over: window)
            return
        }
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
            if infoOpen { toggleInfo() } else if isFullScreen { window.toggleFullScreen(nil) } else { window.performClose(nil) }
        case .next: navigate(by: 1, animated: true)
        case .previous: navigate(by: -1, animated: true)
        case .first: go(to: 0, direction: 1)
        case .last: go(to: nav.entries.count - 1, direction: -1)
        case .moveToTrash: moveCurrentToTrash()
        case .toggleFilmstrip: toggleFilmstrip()
        case .toggleGallery: toggleGallery()
        case .toggleStretch: toggleStretch()
        case .togglePlayback: toggleAnimationPlayback()
        case .previousFrame: stepAnimation(by: -1)
        case .nextFrame: stepAnimation(by: 1)
        case .toggleInfo: toggleInfo()
        case .showShortcuts: break
        }
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
        if let frames = animationStatus { items.append(frames) }
        if let lastError, meta == nil { items.append(lastError) }
        statusBar.update(items: items)
        updateInfoModel()
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
            _ = settings.clickPinsStatusBar
            _ = settings.barClearGlass
            _ = settings.barTint
            _ = settings.background
            _ = settings.filmstrip
            _ = settings.filmstripThumb
            _ = settings.thumbnailMemoryMB
            _ = settings.tileMemoryMB
            _ = settings.sortKey
            _ = settings.sortAscending
        }, onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.applySettings()
                self.observeSettings()
            }
        })
    }

    func applySettings() {
        let sort = "\(settings.sortKey.rawValue)/\(settings.sortAscending)"
        if sort != appliedSort {
            appliedSort = sort
            rescanFolder()
        }
        thumbs.setBudget(megabytes: settings.effectiveThumbnailMemoryMB)
        detail.tiles.setBudget(settings.tileMemoryMB << 20)
        if settings.filmstrip == .always { showFilmstrip() } else if !strip.pinned { hideFilmstrip() }
        if filmstripVisible { showFilmstrip() }
        applyBackground()
        resizeWindowToImage()
        if !settings.clickPinsStatusBar || settings.statusBar != .onHover { statusPinned = false }
        updateStatusVisibility()
        updateStatus()
        metalView.setNeedsRender()
    }

    // MARK: Window delegate

    /// The chosen background on every layer behind the picture, not only the Metal clear color: the window, the
    /// content view and the Metal layer show through while the window resizes or before a frame is drawn, and
    /// black there made a gray background flash black on image changes.
    /// The translucent background shows the windows behind through a blur; in full screen nothing is behind the
    /// window, so it is black there (docs/UI_SPEC.md §10). `fullScreen` overrides the state during a transition.
    func applyBackground(fullScreen: Bool? = nil) {
        OverlayBackground.apply(.init(clearGlass: settings.barClearGlass, tint: settings.barTint))
        let translucent = settings.background == .translucent && !(fullScreen ?? isFullScreen)
        setBackdrop(visible: translucent)
        metalView.transparent = translucent
        window.isOpaque = !translucent
        if translucent {
            window.backgroundColor = .clear
            content.layer?.backgroundColor = NSColor.clear.cgColor
        } else {
            let rgb = settings.background.rgb
            metalView.clearColor = SIMD4(rgb.x, rgb.y, rgb.z, 1)
            // Drawable is plain 8-bit Display P3 (not sRGB-encoded), so the same numbers give the same color.
            let color = NSColor(displayP3Red: rgb.x, green: rgb.y, blue: rgb.z, alpha: 1)
            window.backgroundColor = color
            content.layer?.backgroundColor = color.cgColor
            metalView.layer?.backgroundColor = color.cgColor
        }
        window.invalidateShadow()
        messageView.onLightBackground = settings.background.isLight && !translucent
        metalView.setNeedsRender()
    }

    /// Blur of what is behind the window, under the picture (the translucent background).
    private func setBackdrop(visible: Bool) {
        if visible, backdrop == nil {
            let view = NSVisualEffectView(frame: content.bounds)
            view.autoresizingMask = [.width, .height]
            view.blendingMode = .behindWindow
            view.material = .hudWindow
            view.state = .active
            view.appearance = NSAppearance(named: .darkAqua)
            content.addSubview(view, positioned: .below, relativeTo: metalView)
            backdrop = view
        }
        backdrop?.isHidden = !visible
    }

    func windowDidResize(_ notification: Notification) {
        layoutOverlays()
        galleryResized()
        if infoOpen { layoutInfoPanel() }
        clampViewport()
        metalView.setNeedsRender()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        if !resizingProgrammatically && !fullScreenTransition && !isFullScreen && meta != nil { fixedFrame = true }
    }

    /// With a toolbar, full screen keeps the title bar on screen unless told to hide it with the menu bar; it then
    /// slides down with the traffic lights when the pointer reaches the top (docs/UI_SPEC.md §2.1).
    func window(_ window: NSWindow, willUseFullScreenPresentationOptions proposedOptions: NSApplication.PresentationOptions = [])
        -> NSApplication.PresentationOptions {
        proposedOptions.union([.fullScreen, .autoHideMenuBar, .autoHideToolbar])
    }

    // In full screen the system reveals the title bar at the top of the screen: its buttons must be visible.
    func windowWillEnterFullScreen(_ notification: Notification) {
        fullScreenTransition = true
        window.setTrafficLightsHidden(false)
        window.titleVisibility = .visible
        updateWindowTitle(fullScreen: true)
        applyBackground(fullScreen: true)
    }

    func windowWillExitFullScreen(_ notification: Notification) {
        fullScreenTransition = true
        window.titleVisibility = .hidden
        updateWindowTitle(fullScreen: false)
        applyBackground(fullScreen: false)
    }

    /// The system title bar is hidden in a window (the hover title bar shows the name) and shown in full screen,
    /// where it slides down from the top with the file and app name (docs/UI_SPEC.md §2.1).
    func updateWindowTitle(fullScreen: Bool? = nil) {
        let name = currentURL?.lastPathComponent
        if fullScreen ?? isFullScreen, let name {
            window.title = "\(name) — ViVuView"
        } else {
            window.title = name ?? "ViVuView"
        }
    }

    func windowDidFailToEnterFullScreen(_ window: NSWindow) { fullScreenTransition = false }
    func windowDidFailToExitFullScreen(_ window: NSWindow) { fullScreenTransition = false }

    func windowDidEnterFullScreen(_ notification: Notification) {
        layoutFilmstripInset()
        layoutInfoPanel()
        clampViewport()
        hideChrome()
        // A hide that ran while the window was still entering full screen made them transparent.
        window.setTrafficLightsHidden(false)
        fullScreenTransition = false
        updateStatus()
        metalView.setNeedsRender()
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        // The exit animation's live resize can end just after this; keep ignoring it for a moment.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            self?.fullScreenTransition = false
        }
        window.setTrafficLightsHidden(!chromeVisible)
        layoutFilmstripInset()
        layoutInfoPanel()
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
        if vp.isFit { vp = fitted(meta.orientedSize, view: viewSize, turns: vp.quarterTurns) }
        let size = CGSize(width: Double(meta.orientedSize.width) * vp.scale, height: Double(meta.orientedSize.height) * vp.scale)
        var center = vp.viewPoint(CGPoint(x: Double(meta.orientedSize.width) / 2, y: Double(meta.orientedSize.height) / 2), view: viewSize)
        center.x += bounceOffset
        let nearest = vp.scale / max(texture.coverage, 0.0001) >= 4 && detail.source == nil
        let rotation = Double(vp.quarterTurns) * .pi / 2 + fx.liveRotation
        let base = Quad.placed(texture: texture.texture, center: center, size: size, rotation: rotation, viewSize: viewSize,
                               nearest: nearest)
        var quads: [Quad] = []
        if settings.background == .checkerboard && meta.hasAlpha {
            var checker = Quad.placed(texture: nil, center: center, size: size, rotation: rotation, viewSize: viewSize)
            checker.checker = true
            quads.append(checker)
        }
        return quads + [base] + detailQuads(viewport: vp, viewSize: viewSize)
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
        case "thumbs":
            let c = galleryThumbnailCoverage()
            print("thumbs: \(c.shown)/\(c.visible)")
        case "shortcuts-text":
            print(ShortcutTable.text())
        case "menu":
            // Prints the right-click menu (titles, submenu counts).
            guard let menu = contextMenu() else { throw ScriptError.message("no context menu") }
            let titles = menu.items.filter { !$0.isSeparatorItem }.map { item -> String in
                guard let sub = item.submenu else { return item.title }
                return "\(item.title) [\(sub.items.filter { !$0.isSeparatorItem }.count)]"
            }
            print("menu: " + titles.joined(separator: " | "))
        case let name where name.hasPrefix("scroll:"):
            // scroll:[cmd:]<notches> — a mouse wheel turned at the window center.
            let parts = name.split(separator: ":").dropFirst()
            guard let notches = parts.last.flatMap({ Int32($0) }),
                  let cg = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: notches, wheel2: 0, wheel3: 0)
            else { throw ScriptError.message("bad scroll \(name)") }
            if parts.contains("cmd") { cg.flags = .maskCommand }
            guard let event = NSEvent(cgEvent: cg) else { throw ScriptError.message("bad scroll \(name)") }
            scrollWheel(event)
        case let name where name.hasPrefix("settings"):
            let tab = SettingsTab(rawValue: String(name.dropFirst("settings".count).drop { $0 == ":" })) ?? .general
            (NSApp.delegate as? AppDelegate)?.showSettings(tab: tab)
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
            + "detail=\(detailDescription) anim=\(animationStatus ?? "-") info=\(infoOpen ? "open" : "closed") "
            + "filmstrip=\(filmstripVisible ? "shown" : "hidden") transition=\(isTransitioning ? "running" : "idle") alpha=\(window.alphaValue) "
            + "error=\(lastError ?? "-") fullscreen=\(isFullScreen) "
            + "title=[\(window.titleVisibility == .visible ? window.title : "")] statusbar=[\(statusBar.items.joined(separator: " · "))] shortcuts=\(ShortcutsPanel.shared.isShown)"
    }

    var detailDescription: String {
        if detail.source != nil { return "tiles(\(detail.tiles.count))" }
        if detail.isBuilding { return "building" }
        if let texture, meta?.isVector == true { return "vector(\(max(texture.texture.width, texture.texture.height)))" }
        if let texture, texture.coverage >= 0.999 { return "full" }
        return "screen"
    }

    /// The window content as an image: the Metal scene with the visible overlays drawn on top.
    func snapshot() -> NSBitmapImageRep? {
        let bounds = content.bounds
        guard let rep = content.bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        // The translucent background's blur does not render into bitmaps: a gray stand-in shows where it is.
        let rgb = backdrop?.isHidden == false ? SIMD3(0.25, 0.25, 0.27) : settings.background.rgb
        NSColor(displayP3Red: rgb.x, green: rgb.y, blue: rgb.z, alpha: 1).setFill()
        bounds.fill()
        if let scene = metalView.snapshotImage() {
            NSGraphicsContext.current?.cgContext.draw(scene, in: metalView.frame)
        }
        for overlay in content.subviews where overlay !== metalView && overlay !== backdrop && !overlay.isHidden && overlay.alphaValue > 0 {
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
