import AppKit
import ViVuCore

/// Keyboard, mouse, basic gestures and the hover chrome (docs/UI_SPEC.md §2.2, §2.3, §5, §6).
extension ViewerController {
    var keyContext: KeyBindings.Context {
        KeyBindings.Context(isZoomed: isZoomed, isAnimated: meta?.isAnimated ?? false, inGallery: false)
    }

    func keyDown(_ event: NSEvent) -> Bool {
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
        mouseDownEvent = event
        dragged = false
        if event.clickCount == 2 {
            pendingClick?.cancel()
            toggleFitAndActualSize(at: viewPoint(event))
        }
    }

    func mouseDragged(_ event: NSEvent) {
        guard let down = mouseDownEvent else { return }
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
        defer { mouseDownEvent = nil }
        guard !dragged, event.clickCount == 1 else { return }
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
        if event.hasPreciseScrollingDeltas {
            // Trackpad: swipe to change image at fit, pan when zoomed (ViewerController+Transition.swift).
            if handleTrackpadScroll(event) { return }
            guard isZoomed else { return }
            let scale = metalView.backingScale
            pan(by: CGVector(dx: event.scrollingDeltaX * scale, dy: event.scrollingDeltaY * scale))
        } else if settings.wheelAction == .zoom || isZoomed {
            let notches = event.scrollingDeltaY
            guard notches != 0 else { return }
            zoom(to: effectiveViewport.scale * pow(1.1, notches), anchor: viewPoint(event))
        } else {
            perform(event.scrollingDeltaY > 0 ? .previous : .next)
        }
    }

    func magnify(_ event: NSEvent) {
        pinchGesture(event)
    }

    /// Three-finger swipe (when the system sends it): positive deltaX is a swipe to the left → next image.
    func swipe(_ event: NSEvent) {
        if event.deltaX > 0 { navigate(by: 1, animated: true) } else if event.deltaX < 0 { navigate(by: -1, animated: true) }
    }

    func smartMagnify(_ event: NSEvent) {
        toggleFitAndActualSize(at: viewPoint(event))
    }

    // MARK: Chrome

    var statusBarShown: Bool { !statusBar.isHidden && statusBar.alphaValue > 0 }

    func mouseMoved() {
        showChrome()
        chromeHideTask?.cancel()
        chromeHideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, !Task.isCancelled else { return }
            hideChrome()
        }
    }

    func mouseExited() {
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
        guard settings.statusBar != .never else { return }
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
        setVisible(statusBar, show && (meta != nil || lastError != nil || isLoading), animated: chromeVisible || statusPinned)
    }

    func layoutOverlays() {
        let b = content.bounds
        titleBar.frame = CGRect(x: 0, y: b.height - TitleBarOverlay.height, width: b.width, height: TitleBarOverlay.height)
        statusBar.frame = CGRect(x: 0, y: 0, width: b.width, height: StatusBar.height)
        zoomBadge.frame = CGRect(x: b.width - 84, y: StatusBar.height + 8, width: 72, height: 26)
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
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

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

    override func mouseDown(with event: NSEvent) { MainActor.assumeIsolated { controller?.mouseDown(event) } }
    override func mouseDragged(with event: NSEvent) { MainActor.assumeIsolated { controller?.mouseDragged(event) } }
    override func mouseUp(with event: NSEvent) { MainActor.assumeIsolated { controller?.mouseUp(event) } }
    override func mouseMoved(with event: NSEvent) { MainActor.assumeIsolated { controller?.mouseMoved() } }
    override func mouseEntered(with event: NSEvent) { MainActor.assumeIsolated { controller?.mouseMoved() } }
    override func mouseExited(with event: NSEvent) { MainActor.assumeIsolated { controller?.mouseExited() } }
    override func scrollWheel(with event: NSEvent) { MainActor.assumeIsolated { controller?.scrollWheel(event) } }
    override func magnify(with event: NSEvent) { MainActor.assumeIsolated { controller?.magnify(event) } }
    override func smartMagnify(with event: NSEvent) { MainActor.assumeIsolated { controller?.smartMagnify(event) } }
    override func rotate(with event: NSEvent) { MainActor.assumeIsolated { controller?.rotateGesture(event) } }
    override func swipe(with event: NSEvent) { MainActor.assumeIsolated { controller?.swipe(event) } }
    override func wantsScrollEventsForSwipeTracking(on axis: NSEvent.GestureAxis) -> Bool { true }

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
