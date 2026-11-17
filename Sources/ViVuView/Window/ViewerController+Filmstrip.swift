import AppKit
import ViVuCore

/// Filmstrip visibility state (docs/UI_SPEC.md §7).
@MainActor
final class FilmstripState {
    var panel: FilmstripPanel?
    /// `T` / swipe up pinned it open (in auto-hide mode).
    var pinned = false
    var mouseInside = false
    var hideTask: Task<Void, Never>?
    var monitors: [Any] = []
    /// Hidden while the gallery is open.
    var suppressed = false
}

extension ViewerController {
    var filmstripVisible: Bool { strip.panel?.isVisible == true }

    /// Height the filmstrip takes from the bottom of the screen when it is shown, points.
    var filmstripReservedHeight: Double {
        guard !isFullScreen, filmstripVisible || (settings.filmstrip == .always && nav.entries.count > 1),
              let panel = strip.panel else { return 0 }
        return panel.panelHeight
    }

    /// In full screen a filmstrip the user turned on (`T`, swipe up, or "Always") takes its height from the bottom
    /// of the picture instead of covering it; the auto-hide peek at the screen edge still overlays (UI_SPEC §7).
    var filmstripBottomInset: CGFloat {
        guard isFullScreen, filmstripVisible, strip.pinned || settings.filmstrip == .always, let panel = strip.panel
        else { return 0 }
        return panel.panelHeight
    }

    func layoutFilmstripInset() {
        let inset = filmstripBottomInset
        guard abs(metalView.frame.minY - inset) > 0.5 else { return }
        layoutOverlays()
        clampViewport()
        metalView.setNeedsRender()
    }

    func makeFilmstripIfNeeded() -> FilmstripPanel {
        if let panel = strip.panel { return panel }
        let panel = FilmstripPanel(renderer: renderer, thumbs: thumbs)
        panel.onSelect = { [weak self] index in
            guard let self, let current = nav.index else { return }
            navigate(by: index - current, animated: abs(index - current) == 1)
        }
        panel.onContextMenu = { [weak self] index in
            guard let self, let current = nav.index else { return nil }
            if index != current { navigate(by: index - current, animated: false) }
            return contextMenu()
        }
        panel.onMouseInside = { [weak self] inside in
            guard let self else { return }
            strip.mouseInside = inside
            if inside { strip.hideTask?.cancel() } else { scheduleFilmstripHide() }
        }
        strip.panel = panel
        thumbs.onThumbnail.append { [weak self] url in self?.strip.panel?.thumbnailArrived(url) }
        thumbs.onSizes.append { [weak self] in self?.strip.panel?.relayout() }
        installHotZone()
        return panel
    }

    func showFilmstrip() {
        guard nav.entries.count > 1, !strip.suppressed, let screen = window.screen ?? NSScreen.main else { return }
        let panel = makeFilmstripIfNeeded()
        panel.reload(urls: nav.entries.map(\.url), current: nav.index, thumbHeight: settings.filmstripThumb.height)
        panel.place(on: screen)
        panel.orderFront(nil)
        panel.stripView.setNeedsRender()
        keepWindowAboveFilmstrip()
        layoutFilmstripInset()
    }

    func hideFilmstrip() {
        strip.hideTask?.cancel()
        guard let panel = strip.panel, panel.isVisible else { return }
        panel.orderOut(nil)
        thumbs.want([], client: "filmstrip")
        layoutFilmstripInset()
    }

    func toggleFilmstrip() {
        if filmstripVisible && (strip.pinned || settings.filmstrip == .always) {
            strip.pinned = false
            if settings.filmstrip == .always { settings.filmstrip = .autoHide }
            hideFilmstrip()
        } else {
            strip.pinned = true
            showFilmstrip()
        }
    }

    func scheduleFilmstripHide() {
        guard settings.filmstrip == .autoHide, !strip.pinned else { return }
        strip.hideTask?.cancel()
        strip.hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, !Task.isCancelled, !strip.mouseInside, !strip.pinned else { return }
            hideFilmstrip()
        }
    }

    /// The main window never sits under the strip: move it up (or shrink it) when they would overlap.
    func keepWindowAboveFilmstrip() {
        guard !isFullScreen, let panel = strip.panel, panel.isVisible, window.frame.minY < panel.frame.maxY else { return }
        if fixedFrame || meta == nil {
            let available = availableFrame
            var frame = window.frame
            frame.size.height = min(frame.height, available.height)
            frame = WindowSizing.frame(size: frame.size, center: CGPoint(x: frame.midX, y: frame.midY), available: available)
            window.setFrame(frame, display: true)
        } else {
            resizeWindowToImage(zoom: viewport.isFit ? nil : viewport.scale / unitScale)
        }
    }

    /// Mouse at the very bottom of the screen shows the strip (auto-hide mode, app in front).
    private func installHotZone() {
        let handler: (NSEvent) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.checkHotZone() }
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved, handler: handler) { strip.monitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved, handler: { event in handler(event); return event }) {
            strip.monitors.append(local)
        }
    }

    private func checkHotZone() {
        guard settings.filmstrip == .autoHide, NSApp.isActive, window.isVisible, !strip.suppressed,
              let screen = window.screen else { return }
        let mouse = NSEvent.mouseLocation
        let visible = screen.visibleFrame
        guard visible.minX...visible.maxX ~= mouse.x else { return }
        if mouse.y <= visible.minY + 4 && mouse.y >= screen.frame.minY {
            if !filmstripVisible { showFilmstrip() }
            strip.hideTask?.cancel()
        } else if filmstripVisible && !strip.mouseInside, let panel = strip.panel, mouse.y > panel.frame.maxY + 40 {
            scheduleFilmstripHide()
        }
    }

    // MARK: Hooks from navigation

    func filmstripFolderChanged() {
        thumbs.readSizes(nav.entries.map(\.url), priority: nearbyURLs(radius: 30))
        if settings.filmstrip == .always && !strip.suppressed { showFilmstrip() }
        if filmstripVisible { strip.panel?.reload(urls: nav.entries.map(\.url), current: nav.index,
                                                  thumbHeight: settings.filmstripThumb.height) }
    }

    func filmstripCurrentChanged() {
        if filmstripVisible { strip.panel?.setCurrent(nav.index, animated: true) }
    }

    func nearbyURLs(radius: Int) -> [URL] {
        guard let index = nav.index else { return [] }
        return PreloadPlanner.plan(index: index, count: nav.entries.count, direction: nav.direction, perSide: 0,
                                   wrap: false, thumbnailRadius: radius).thumbnails.map { nav.entries[$0].url }
    }

    /// A thumbnail finished: it may be the stage-0 picture the current image is waiting for.
    func thumbnailArrivedForNavigation(_ url: URL) {
        guard url == nav.currentURL, let slot = nav.slots[url], slot.screen == nil, slot.thumb == nil,
              let tex = thumbs.texture(for: url) else { return }
        slot.thumb = tex
        if nav.shownURL != url {
            nav.shownURL = url
            showDecoded(tex, url: url, isNewImage: true)
        }
    }
}
