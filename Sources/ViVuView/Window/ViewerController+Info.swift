import AppKit
import SwiftUI
import ViVuCore

/// Info panel state (docs/UI_SPEC.md §9).
@MainActor
final class InfoState {
    let model = InfoModel()
    var window: InfoPanelWindow?
    /// In full screen and in the gallery the panel overlays the right edge of the content instead.
    var overlay: NSView?
    var histogramURL: URL?
    var histogramTicket: DecodeTicket?
}

extension ViewerController {
    var infoOpen: Bool { settings.infoPanelOpen }

    func toggleInfo() {
        settings.infoPanelOpen.toggle()
        layoutInfoPanel()
    }

    /// Shows, hides and places the panel for the current mode.
    func layoutInfoPanel() {
        let embedded = isFullScreen || galleryOpen
        guard infoOpen, window.isVisible else {
            infoPanelState.window?.orderOut(nil)
            infoPanelState.overlay?.isHidden = true
            return
        }
        updateInfoModel()
        if embedded {
            infoPanelState.window?.orderOut(nil)
            if infoPanelState.overlay == nil {
                let hosting = NSHostingView(rootView: InfoPanelView(model: infoPanelState.model))
                let overlay = OverlayBackground.make(content: hosting)
                content.addSubview(overlay)
                infoPanelState.overlay = overlay
            }
            let b = content.bounds
            let top = galleryOpen ? Self.galleryHeaderHeight : 0
            infoPanelState.overlay?.frame = CGRect(x: b.width - InfoPanelWindow.width, y: 0,
                                                   width: InfoPanelWindow.width, height: b.height - top)
            infoPanelState.overlay?.isHidden = false
        } else {
            infoPanelState.overlay?.isHidden = true
            let panel = infoPanelState.window ?? {
                let made = InfoPanelWindow(model: infoPanelState.model)
                infoPanelState.window = made
                return made
            }()
            if panel.parent == nil { window.addChildWindow(panel, ordered: .above) }
            panel.place(beside: window.frame, on: window.screen)
            panel.orderFront(nil)
        }
        requestHistogram()
    }

    /// Refreshes the panel's values (cheap; called with every status update).
    func updateInfoModel() {
        guard infoOpen else { return }
        let model = infoPanelState.model
        model.info = info
        model.fileName = currentURL?.lastPathComponent ?? ""
        model.zoom = meta == nil ? "" : zoomText
        model.position = positionText ?? ""
        if let texture {
            let w = texture.texture.width, h = texture.texture.height
            model.shownResolution = texture.coverage >= 0.999 ? String(localized: "đầy đủ") + " (\(w)×\(h))" : "\(w)×\(h)"
        } else {
            model.shownResolution = ""
        }
        model.detail = detailInfoText
        if model.histogram != nil && infoPanelState.histogramURL != currentURL { model.histogram = nil }
        requestHistogram()
    }

    private var detailInfoText: String {
        switch detail.tier {
        case .region?: return String(localized: "đọc theo vùng từ file, \(detail.tiles.count) tile") + (detailStatus.map { ", \($0)" } ?? "")
        case .ramPyramid?: return detail.source == nil ? (detailStatus ?? "") : String(localized: "pyramid trong RAM, \(detail.tiles.count) tile")
        case .subsampled(let f)?: return String(localized: "giảm mẫu 1/\(f), \(detail.tiles.count) tile")
        default: return detailStatus ?? ""
        }
    }

    /// Histogram from a small decode (or the RAM thumbnail), off the main thread.
    private func requestHistogram() {
        guard infoOpen, let url = currentURL, infoPanelState.histogramURL != url else { return }
        infoPanelState.histogramURL = url
        infoPanelState.histogramTicket?.cancel()
        let store = thumbs.store
        infoPanelState.histogramTicket = scheduler.submit(.thumbnails, priority: .veryHigh, work: { _ in
            let pixels: PixelBuffer
            if let cached = store.get(url) {
                pixels = try ThumbnailStore.decode(cached)
            } else if let own = SourceFactory.ownThumbnail(url, longSide: 512) {
                pixels = own
            } else {
                pixels = try ImageIODecoder.thumbnail(url, maxPixel: 512)
            }
            return Histogram.compute(pixels)
        }, completion: { [weak self] result in
            guard let self, currentURL == url else { return }
            infoPanelState.model.histogram = try? result.get()
        })
    }
}
