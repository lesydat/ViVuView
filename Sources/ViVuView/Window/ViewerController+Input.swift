import AppKit
import ViVuCore

/// Keyboard, mouse, basic gestures and the hover chrome (docs/UI_SPEC.md §2.2, §2.3, §5, §6).
extension ViewerController {
    var keyContext: KeyBindings.Context {
        KeyBindings.Context(isZoomed: isZoomed, isAnimated: meta?.isAnimated ?? false, inGallery: false)
    }

    func keyDown(_ event: NSEvent) -> Bool {
        if galleryOpen { return galleryKeyDown(event) }
        guard let command = KeyBindings.command(for: event, context: keyContext) else { return false }
        // Holding a key browses without animation (docs/UI_SPEC.md §4).
        switch command {
        case .next: navigate(by: 1, animated: !event.isARepeat)
        case .previous: navigate(by: -1, animated: !event.isARepeat)
        default: perform(command)
        }
        return true
    }

    /// Event location in the Metal view, device pixels, origin top-left.
    func viewPoint(_ event: NSEvent) -> CGPoint {
        let p = metalView.convert(event.locationInWindow, from: nil)
        return CGPoint(x: p.x * metalView.backingScale, y: p.y * metalView.backingScale)
    }

    func mouseDown(_ event: NSEvent) {
        if galleryOpen { return }
        mouseDownEvent = event
        dragged = false
        // A click that brings the window forward is not a pin (docs/UI_SPEC.md §2.3).
        clickActivatesWindow = content.firstMouseTimestamp == event.timestamp
        if event.clickCount == 2 {
            pendingClick?.cancel()
            if currentURL == nil {
                // Empty window: double-click opens a file (docs/UI_SPEC.md §11).
                NSApp.sendAction(#selector(AppDelegate.openDocument(_:)), to: nil, from: content)
            } else {
                toggleFitAndActualSize(at: viewPoint(event))
            }
        }
    }

    func mouseDragged(_ event: NSEvent) {
        guard !galleryOpen, let down = mouseDownEvent else { return }
        if !dragged {
            let d = hypot(event.locationInWindow.x - down.locationInWindow.x, event.locationInWindow.y - down.locationInWindow.y)
            guard d > 3 else { return }
            dragged = true
            if !isZoomed && !isFullScreen {
                window.performDrag(with: down)   // at fit, dragging moves the window
                mouseDownEvent = nil
                return
            }
        }
        let scale = metalView.backingScale
        pan(by: CGVector(dx: event.deltaX * scale, dy: event.deltaY * scale))
    }

    func mouseUp(_ event: NSEvent) {
        if galleryOpen { galleryMouseUp(event); return }
        defer { mouseDownEvent = nil }
        guard !dragged, event.clickCount == 1, !clickActivatesWindow else { return }
        // A single click pins the status bar, unless it turns out to be a double click.
        pendingClick?.cancel()
        pendingClick = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(NSEvent.doubleClickInterval))
            guard let self, !Task.isCancelled else { return }
            toggleStatusPin()
        }
    }

    func toggleFitAndActualSize(at point: CGPoint) {
        if isZoomed || abs(effectiveViewport.scale - unitScale) < unitScale * 0.001 {
            fitToWindow()
        } else {
            zoom(to: unitScale, anchor: point)
        }
    }

    func scrollWheel(_ event: NSEvent) {
        if galleryOpen { galleryScroll(event); return }
        // ⌘ (or ⌃) + scroll zooms around the pointer, with a wheel or a trackpad, whatever the wheel setting.
        if !event.modifierFlags.intersection([.command, .control]).isEmpty {
            // A wheel notch is about 1; a trackpad reports points, about 10 for the same feel.
            let steps = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY / 10 : event.scrollingDeltaY
            guard steps != 0, meta != nil else { return }
            zoom(to: effectiveViewport.scale * pow(1.1, steps), anchor: viewPoint(event))
            return
        }
        if event.hasPreciseScrollingDeltas {
            // Trackpad: swipe to change image at fit, pan when zoomed (ViewerController+Transition.swift).
            if handleTrackpadScroll(event) { return }
            guard isZoomed else { return }
            let scale = metalView.backingScale
            pan(by: CGVector(dx: event.scrollingDeltaX * scale, dy: event.scrollingDeltaY * scale))
        } else if isZoomed {
            // Mouse wheel: scrolls the picture (⇧ for sideways); ⌘ + wheel zooms (above). At fit there is
            // nothing to scroll (docs/UI_SPEC.md §5).
            let line = 40 * metalView.backingScale
            pan(by: CGVector(dx: event.scrollingDeltaX * line, dy: event.scrollingDeltaY * line))
        }
    }

    func magnify(_ event: NSEvent) {
        if galleryOpen { galleryMagnify(event); return }
        pinchGesture(event)
    }

    /// Three-finger swipe (when the system sends it): positive deltaX is a swipe to the left → next image.
    func swipe(_ event: NSEvent) {
        if event.deltaX > 0 { navigate(by: 1, animated: true) } else if event.deltaX < 0 { navigate(by: -1, animated: true) }
    }

    func smartMagnify(_ event: NSEvent) {
        if galleryOpen { return }
        toggleFitAndActualSize(at: viewPoint(event))
    }

    // MARK: Chrome

    var statusBarShown: Bool { !statusBar.isHidden && statusBar.alphaValue > 0 }

    /// `event` nil = forced (scripts). Real events only count when the pointer actually moved: resizing or
    /// recentering the window on an image change sends entered/moved events under a still pointer, and the
    /// chrome must not pop up then (docs/UI_SPEC.md §2.2).
    func mouseMoved(_ event: NSEvent? = nil) {
        if galleryOpen { if let event { galleryMouseMoved(event) }; return }
        if event != nil {
            if ignoresRealPointer { return }
            let pointer = NSEvent.mouseLocation
            guard pointer != lastPointer else { return }
            lastPointer = pointer
        }
        showChrome()
        chromeHideTask?.cancel()
        chromeHideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, !Task.isCancelled else { return }
            hideChrome()
        }
    }

    func mouseExited(real: Bool = false) {
        if real && ignoresRealPointer { return }
        chromeHideTask?.cancel()
        hideChrome()
    }

    func showChrome() {
        guard !chromeVisible else { return }
        chromeVisible = true
        if !isFullScreen {
            setVisible(titleBar, true)
            window.setTrafficLightsHidden(false)
        }
        updateStatusVisibility()
    }

    func hideChrome() {
        guard chromeVisible else { return }
        chromeVisible = false
        setVisible(titleBar, false)
        window.setTrafficLightsHidden(true)
        updateStatusVisibility()
    }

    func toggleStatusPin() {
        guard settings.statusBar == .onHover, settings.clickPinsStatusBar else { return }
        statusPinned.toggle()
        updateStatusVisibility()
    }

    func updateStatusVisibility() {
        let show: Bool
        switch settings.statusBar {
        case .never: show = false
        case .always: show = true
        case .onHover: show = chromeVisible || statusPinned
        }
        statusBar.pinned = statusPinned && settings.statusBar == .onHover
        // The gallery has its own header; the bar stays away even when pinned.
        if galleryOpen { setVisible(statusBar, false, animated: false); return }
        setVisible(statusBar, show && (meta != nil || lastError != nil || isLoading), animated: chromeVisible || statusPinned)
    }

    func layoutOverlays() {
        let b = content.bounds
        let barHeight = window.titleBarHeight
        titleBar.frame = CGRect(x: 0, y: b.height - barHeight, width: b.width, height: barHeight)
        let inset = filmstripBottomInset
        metalView.frame = CGRect(x: 0, y: inset, width: b.width, height: b.height - inset)
        statusBar.frame = CGRect(x: 0, y: inset, width: b.width, height: StatusBar.height)
        zoomBadge.frame = CGRect(x: b.width - 84, y: inset + StatusBar.height + 8, width: 72, height: 26)
    }
}

/// Content view of the main window: hosts the Metal view and overlays, receives input, accepts dropped files.
final class ViewerContentView: NSView {
    weak var controller: ViewerController?
    private var tracking: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func addFill(_ view: NSView) {
        view.frame = bounds
        view.autoresizingMask = [.width, .height]
        addSubview(view)
    }

    override var acceptsFirstResponder: Bool { true }
    /// The mouse-down that activated the window (AppKit asks only for clicks in an inactive window).
    var firstMouseTimestamp: TimeInterval?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        firstMouseTimestamp = event?.timestamp
        return true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func keyDown(with event: NSEvent) {
        let handled = MainActor.assumeIsolated { controller?.keyDown(event) ?? false }
        if !handled { super.keyDown(with: event) }
    }

    override func mouseDown(with event: NSEvent) {
        // Control-click is a right click.
        if event.modifierFlags.contains(.control) { rightMouseDown(with: event); return }
        MainActor.assumeIsolated { controller?.mouseDown(event) }
    }
    override func mouseDragged(with event: NSEvent) { MainActor.assumeIsolated { controller?.mouseDragged(event) } }
    override func mouseUp(with event: NSEvent) { MainActor.assumeIsolated { controller?.mouseUp(event) } }
    override func mouseMoved(with event: NSEvent) { MainActor.assumeIsolated { controller?.mouseMoved(event) } }
    override func mouseEntered(with event: NSEvent) { MainActor.assumeIsolated { controller?.mouseMoved(event) } }
    override func mouseExited(with event: NSEvent) { MainActor.assumeIsolated { controller?.mouseExited(real: true) } }
    override func scrollWheel(with event: NSEvent) { MainActor.assumeIsolated { controller?.scrollWheel(event) } }
    override func magnify(with event: NSEvent) { MainActor.assumeIsolated { controller?.magnify(event) } }
    override func smartMagnify(with event: NSEvent) { MainActor.assumeIsolated { controller?.smartMagnify(event) } }
    override func rotate(with event: NSEvent) { MainActor.assumeIsolated { controller?.rotateGesture(event) } }
    override func swipe(with event: NSEvent) { MainActor.assumeIsolated { controller?.swipe(event) } }
    override func wantsScrollEventsForSwipeTracking(on axis: NSEvent.GestureAxis) -> Bool { true }

    // Built and shown inside the main-actor block: NSMenu is not Sendable, so `menu(for:)` cannot return it.
    override func rightMouseDown(with event: NSEvent) {
        MainActor.assumeIsolated {
            guard let menu = controller?.contextMenu() else { return }
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        }
    }

    @objc func openWithApp(_ sender: NSMenuItem) {
        let app = sender.representedObject as? URL
        MainActor.assumeIsolated { controller?.openCurrent(with: app) }
    }

    @objc func performMenuCommand(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let command = Command(rawValue: raw) else { return }
        MainActor.assumeIsolated { controller?.perform(command) }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        imageURL(from: sender) != nil ? .copy : []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let url = imageURL(from: sender) else { return false }
        MainActor.assumeIsolated { controller?.open(url) }
        return true
    }

    private func imageURL(from info: NSDraggingInfo) -> URL? {
        let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                                                       options: [.urlReadingFileURLsOnly: true]) as? [URL]
        return urls?.first { FormatCatalog.isImage($0) } ?? urls?.first
    }
}
