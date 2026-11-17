import AppKit
import UniformTypeIdentifiers
import ViVuCore
import ViVuRender

/// Full-resolution detail for the current image (docs/TECH_SPEC.md §4.2 stage 2, §4.3 tiles).
@MainActor
final class DetailState {
    var url: URL?
    var tier: ImageTier?
    /// Tier S: full-resolution single texture being decoded.
    var fullTicket: DecodeTicket?
    /// Tiers M / L: the region source and its build job.
    var source: RegionSource?
    var sourceTicket: DecodeTicket?
    var buildFailed = false
    var tiles: TileCache
    var pending: [TileKey: DecodeTicket] = [:]
    var dwellTask: Task<Void, Never>?
    /// The user stayed on this image long enough: build detail as soon as its pixels are in.
    var dwelled = false

    init(budgetMB: Int) { tiles = TileCache(budgetBytes: budgetMB << 20) }

    var isBuilding: Bool { sourceTicket != nil || fullTicket != nil }

    func reset() {
        fullTicket?.cancel()
        sourceTicket?.cancel()
        pending.values.forEach { $0.cancel() }
        pending = [:]
        dwellTask?.cancel()
        fullTicket = nil
        sourceTicket = nil
        source = nil
        tier = nil
        buildFailed = false
        dwelled = false
        tiles.removeAll()
        url = nil
    }
}

extension ViewerController {
    /// Stage-1 pixels are being magnified on screen.
    var needsDetail: Bool {
        guard let texture else { return false }
        return effectiveViewport.scale / max(texture.coverage, 0.0001) > Tuning.detailTrigger
    }

    /// The current image changed: drop the old detail, start the dwell timer for the new one.
    func detailImageChanged(_ url: URL) {
        detail.reset()
        detail.url = url
        detail.dwellTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Tuning.detailDwell))
            guard let self, !Task.isCancelled, detail.url == url else { return }
            detail.dwelled = true
            updateDetail()
        }
    }

    /// Called after zoom, pan, rotation, decode results and the dwell timer.
    func updateDetail() {
        let dwelled = detail.dwelled
        // The pixels on screen must belong to the current file: while a new image decodes, the previous
        // picture (and its meta) is still shown.
        guard let url = currentURL, detail.url == url, nav.shownURL == url, let meta, let texture, !galleryOpen,
              !meta.isAnimated else { return }
        if detail.source == nil, let own = nav.slots[url]?.source {
            // Huge TIFF/PSB: the reader that made the fit picture zooms too (tier L-A).
            detail.source = own
            detail.tier = .region
        }
        let tier = detail.tier ?? ImageTier.classify(meta.orientedSize, maxTextureSide: renderer.maxTextureSide)
        detail.tier = tier
        let needs = needsDetail
        switch tier {
        case .single where meta.isVector:
            updateVectorDetail(url, meta: meta, texture: texture)
        case .single:
            // RAW shown from its embedded preview is only developed when zooming past the preview: developing
            // just because the user paused would change the colours under them (docs/TECH_SPEC.md §4.2).
            let isRaw = UTType(meta.uti)?.conforms(to: .rawImage) == true
            let trigger = isRaw && settings.rawMode == .embeddedPreview ? needs : (needs || dwelled)
            guard texture.coverage < 0.999, trigger, detail.fullTicket == nil else { return }
            startFullDecode(url)
        case .ramPyramid, .subsampled, .region:
            if detail.source == nil {
                if (needs || dwelled) && detail.sourceTicket == nil && !detail.buildFailed { buildSource(url, tier: tier) }
            } else if needs {
                planTiles()
            }
        }
        updateStatus()
    }

    /// SVG: re-drawn at the zoomed size (up to `VectorImage.maxSide`) instead of a fixed "full" decode.
    private func updateVectorDetail(_ url: URL, meta: ImageMeta, texture: DecodedTexture) {
        let shown = effectiveViewport.scale * Double(meta.orientedSize.longSide)
        let have = Double(max(texture.texture.width, texture.texture.height))
        guard shown > have * Tuning.detailTrigger, have < Double(VectorImage.maxSide), detail.fullTicket == nil else { return }
        let side = min(VectorImage.maxSide, Int(shown * 1.25))
        startFullDecode(url) {
            let (pixels, meta) = try VectorImage.render(url, longSide: side)
            return (pixels, meta, Double(pixels.width) / Double(max(1, meta.orientedSize.width)))
        }
    }

    private func startFullDecode(_ url: URL, decode: (@Sendable () throws -> (PixelBuffer, ImageMeta, Double))? = nil) {
        let renderer = renderer
        detail.fullTicket = scheduler.submit(.interactive, priority: .high, work: { isCancelled in
            let state = Signposts.decode.beginInterval("Decode", id: Signposts.decode.makeSignpostID(), "full \(url.lastPathComponent)")
            defer { Signposts.decode.endInterval("Decode", state) }
            let (pixels, meta, coverage) = try decode?() ?? (try ImageIODecoder.fullDecode(url), try ImageIODecoder.meta(url), 1)
            if isCancelled() { throw DecodeError.cancelled }
            return DecodedTexture(texture: try renderer.makeTexture(pixels), meta: meta, coverage: coverage)
        }, completion: { [weak self] result in
            guard let self, detail.url == url else { return }
            detail.fullTicket = nil
            guard case .success(let full) = result else { return }
            nav.slots[url]?.screen = full
            showDecoded(full, url: url, isNewImage: false)
            // A vector may have been zoomed further while it was drawing.
            if full.meta.isVector { updateDetail() }
            updateStatus()
        })
    }

    private func buildSource(_ url: URL, tier: ImageTier) {
        let preferEmbedded = settings.rawMode == .embeddedPreview
        _ = preferEmbedded
        detail.sourceTicket = scheduler.submit(.interactive, priority: .high, work: { isCancelled in
            let state = Signposts.tiles.beginInterval("FitDecode", id: Signposts.tiles.makeSignpostID(), "pyramid \(url.lastPathComponent)")
            defer { Signposts.tiles.endInterval("FitDecode", state) }
            let meta = try ImageIODecoder.meta(url)
            let source: RegionSource
            switch tier {
            case .subsampled(let factor):
                let pixels = try ImageIODecoder.subsampledDecode(url, factor: factor)
                if isCancelled() { throw DecodeError.cancelled }
                source = try RAMPyramidSource(pixels: pixels, meta: meta, baseFactor: factor)
            default:
                let pixels = try ImageIODecoder.fullDecode(url)
                if isCancelled() { throw DecodeError.cancelled }
                source = try RAMPyramidSource(pixels: pixels, meta: meta)
            }
            return SourceBox(source: source)
        }, completion: { [weak self] result in
            guard let self, detail.url == url else { return }
            detail.sourceTicket = nil
            switch result {
            case .success(let box):
                detail.source = box.source
                // Neighbours waited while this huge decode ran.
                refreshPreload()
                if needsDetail { planTiles() }
            case .failure:
                detail.buildFailed = true
            }
            updateStatus()
            metalView.setNeedsRender()
        })
    }

    /// Requests the tiles the view needs (± one ring) and cancels the ones it no longer needs.
    func planTiles() {
        guard let source = detail.source else { return }
        let vp = effectiveViewport
        let size = source.fullSize
        let level = TilePlanner.level(scale: vp.scale, maxLevel: source.maxLevel)
        let visible = TilePlanner.visibleRect(viewport: vp, view: viewSize, imageSize: size)
        let center = vp.imagePoint(CGPoint(x: viewSize.width / 2, y: viewSize.height / 2), view: viewSize)
        let wanted = TilePlanner.tiles(level: level, visible: visible, imageSize: size, ring: 1, center: center)
        let wantedSet = Set(wanted)
        for (key, ticket) in detail.pending where !wantedSet.contains(key) {
            ticket.cancel()
            detail.pending[key] = nil
        }
        let renderer = renderer
        let url = detail.url
        for (rank, key) in wanted.enumerated() where !detail.tiles.contains(key) && detail.pending[key] == nil {
            let (read, uv) = TilePlanner.paddedRead(of: key, imageSize: size)
            detail.pending[key] = scheduler.submit(.background, priority: rank < 6 ? .veryHigh : .high, work: { isCancelled in
                if isCancelled() { throw DecodeError.cancelled }
                let state = Signposts.tiles.beginInterval("RegionDecode", id: Signposts.tiles.makeSignpostID(), "\(key)")
                defer { Signposts.tiles.endInterval("RegionDecode", state) }
                let pixels = try source.read(rect: read, level: key.level)
                if isCancelled() { throw DecodeError.cancelled }
                return TileTexture(texture: try renderer.makeTexture(pixels, mipmapped: false), uv: uv)
            }, completion: { [weak self] result in
                guard let self, detail.url == url else { return }
                detail.pending[key] = nil
                if case .success(let tile) = result {
                    detail.tiles.put(tile, for: key)
                    metalView.setNeedsRender()
                }
            })
        }
    }

    /// Tile quads to draw over the base picture: coarser cached ancestors first, then the wanted level.
    func detailQuads(viewport vp: Viewport, viewSize: CGSize) -> [Quad] {
        guard let source = detail.source, !galleryOpen, needsDetail else { return [] }
        let size = source.fullSize
        let level = TilePlanner.level(scale: vp.scale, maxLevel: source.maxLevel)
        let visible = TilePlanner.visibleRect(viewport: vp, view: viewSize, imageSize: size)
        var fine: [(TileKey, TileTexture)] = []
        var coarse: [TileKey: TileTexture] = [:]
        for key in TilePlanner.tiles(level: level, visible: visible, imageSize: size, center: .zero) {
            if let tile = detail.tiles.peek(key) { fine.append((key, tile)); continue }
            var parent = key
            while parent.level < source.maxLevel {
                parent = TileKey(level: parent.level + 1, col: parent.col / 2, row: parent.row / 2)
                if let tile = detail.tiles.peek(parent) { coarse[parent] = tile; break }
            }
        }
        let ordered = coarse.sorted { $0.key.level > $1.key.level }.map { ($0.key, $0.value) } + fine
        return TileLayer.quads(ordered, imageSize: size, viewport: vp, viewSize: viewSize,
                               extraRotation: fx.liveRotation, offsetX: bounceOffset)
    }

    /// Status bar note for large images.
    var detailStatus: String? {
        if case .subsampled(let factor) = detail.tier, detail.source != nil { return String(localized: "tối đa 1/\(factor)") }
        if detail.sourceTicket != nil { return String(localized: "đang nạp chi tiết…") }
        if detail.buildFailed { return String(localized: "không nạp được độ phân giải đầy đủ") }
        if let tiff = tiffSource, tiff.stretchRange != nil {
            return tiff.stretchEnabled ? String(localized: "kéo giãn") : String(localized: "tuyến tính")
        }
        return nil
    }

    /// The TIFF reader behind the current image, if any.
    var tiffSource: TIFFRegionSource? {
        let source = detail.source ?? currentURL.flatMap { nav.slots[$0]?.source }
        return (source as? TIFFRegionSource) ?? ((source as? HybridSource)?.base as? TIFFRegionSource)
    }

    /// Key E: contrast stretch on/off for 16-bit and float images; the picture is decoded again.
    func toggleStretch() {
        guard let tiff = tiffSource, tiff.stretchRange != nil, let url = currentURL else { NSSound.beep(); return }
        tiff.stretchEnabled.toggle()
        // Everything decoded with the old mapping goes; the reader keeps the new setting.
        detail.reset()
        detail.url = url
        if let slot = nav.slots[url] {
            slot.screen = nil
            slot.thumb = nil
            slot.source = nil
        }
        nav.shownURL = nil
        refreshPreload()
        updateStatus()
    }
}

/// Region sources are Sendable; boxing keeps the generic `submit` happy with an existential.
struct SourceBox: Sendable {
    let source: RegionSource
}
