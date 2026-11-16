import AppKit
import ViVuCore
import ViVuRender

/// Decoded state of one image in the neighbourhood of the current one (docs/TECH_SPEC.md §5.2).
@MainActor
final class ImageSlot {
    let url: URL
    var meta: ImageMeta?
    /// Stage 0: small thumbnail (ThumbnailCache, M5).
    var thumb: DecodedTexture?
    /// Stage 1: sharp at screen size.
    var screen: DecodedTexture?
    var error: String?
    /// Huge TIFF/PSB: the reader to zoom with, kept only for the current image and the next one.
    var source: RegionSource?
    var ticket: DecodeTicket?
    var lane: DecodeScheduler.Lane?

    init(url: URL) { self.url = url }

    var best: DecodedTexture? { screen ?? thumb }
    var isDone: Bool { screen != nil || error != nil }
    var bytes: Int { (screen?.texture.estimatedBytes ?? 0) + (thumb?.texture.estimatedBytes ?? 0) }
}

/// Folder, position and the decoded neighbours.
@MainActor
final class NavigationState {
    var folder: URL?
    var entries: [FolderEntry] = []
    var index: Int?
    /// Last browsing direction, +1 or −1.
    var direction = 1
    var slots: [URL: ImageSlot] = [:]
    var watcher: FolderWatcher?
    var scanTicket: DecodeTicket?
    var scanning = false
    /// Steps requested while the folder was still being scanned.
    var pendingSteps = 0
    /// Delayed request for the thumbnails around the current image.
    var thumbTask: Task<Void, Never>?
    /// The slot whose pixels are on screen (may lag behind `index` until it decodes).
    var shownURL: URL?

    var currentURL: URL? { index.flatMap { entries.indices.contains($0) ? entries[$0].url : nil } }
}

extension ViewerController {
    // MARK: Opening

    /// Opens a file: shows it at once, then scans its folder in the background.
    func open(_ url: URL) {
        // Keep the URL as given (no standardizing: it turns /private/tmp into /tmp and breaks matching
        // against the folder scan, whose URLs are built from the same folder URL).
        let url = url.absoluteURL
        let folder = url.deletingLastPathComponent()
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
        if folder != nav.folder {
            nav.folder = folder
            nav.slots.values.forEach { $0.ticket?.cancel() }
            nav.slots = [:]
            nav.entries = [FolderEntry(url: url, fileSize: 0, modified: .distantPast, created: .distantPast)]
            nav.index = 0
            nav.watcher = FolderWatcher(folder: folder) { [weak self] in self?.rescanFolder() }
            scanFolder(keeping: url)
        } else if let i = nav.entries.firstIndex(where: { $0.url.path == url.path }) {
            nav.index = i
        } else {
            nav.entries.append(FolderEntry(url: url, fileSize: 0, modified: .distantPast, created: .distantPast))
            nav.index = nav.entries.count - 1
            scanFolder(keeping: url)
        }
        nav.direction = 1
        currentChanged()
    }

    private func scanFolder(keeping url: URL) {
        guard let folder = nav.folder else { return }
        nav.scanTicket?.cancel()
        nav.scanning = true
        let sort = FolderSort(rawValue: settings.sortKey.rawValue) ?? .name
        let ascending = settings.sortAscending
        nav.scanTicket = scheduler.submit(.background, priority: .veryHigh, work: { _ in
            try FolderIndex.scan(folder, sort: sort, ascending: ascending)
        }, completion: { [weak self] result in
            guard let self, nav.folder == folder else { return }
            nav.scanning = false
            guard case .success(let entries) = result, !entries.isEmpty else { return }
            let keep = nav.currentURL ?? url
            nav.entries = entries
            nav.index = entries.firstIndex { $0.url.path == keep.path } ?? min(nav.index ?? 0, entries.count - 1)
            // Keep the slots of files already decoded under the URL the scan now uses.
            for entry in entries where nav.slots[entry.url] == nil {
                if let old = nav.slots.first(where: { $0.key.path == entry.url.path }) {
                    nav.slots[old.key] = nil
                    nav.slots[entry.url] = old.value
                    if nav.shownURL?.path == entry.url.path { nav.shownURL = entry.url }
                }
            }
            if nav.pendingSteps != 0 {
                let steps = nav.pendingSteps
                nav.pendingSteps = 0
                step(by: steps)
            } else {
                refreshPreload()
                updateStatus()
            }
            folderChanged()
        })
    }

    /// The folder changed on disk: rescan, staying on the same file (or its neighbour if it is gone).
    func rescanFolder() {
        guard let url = nav.currentURL else { return }
        scanFolder(keeping: url)
    }

    /// The file list changed: filmstrip and gallery follow.
    func folderChanged() {
        filmstripFolderChanged()
    }

    // MARK: Moving

    func step(by delta: Int) {
        guard let index = nav.index else { return }
        if nav.scanning {
            nav.pendingSteps += delta
            return
        }
        let count = nav.entries.count
        var target = index + delta
        if settings.wrapAround {
            target = ((target % count) + count) % count
        } else if !(0..<count).contains(target) {
            bounceAtEnd(direction: delta > 0 ? 1 : -1)
            return
        }
        go(to: target, direction: delta > 0 ? 1 : -1)
    }

    func go(to target: Int, direction: Int) {
        guard nav.entries.indices.contains(target), target != nav.index else { return }
        nav.index = target
        nav.direction = direction
        currentChanged()
    }

    /// The current index changed: show the best pixels we have, then plan decodes.
    func currentChanged() {
        guard let url = nav.currentURL else { return }
        let signpost = Signposts.navigate.beginInterval("Navigate", id: Signposts.navigate.makeSignpostID(), "\(url.lastPathComponent)")
        defer { Signposts.navigate.endInterval("Navigate", signpost) }
        currentURL = url
        info = nil
        infoTicket?.cancel()
        window.title = url.lastPathComponent
        window.representedURL = url
        titleBar.title = url.lastPathComponent
        let slot = slot(for: url)
        if slot.screen == nil, slot.thumb == nil, let thumb = thumbs.texture(for: url) { slot.thumb = thumb }   // stage 0
        isLoading = !slot.isDone
        if let best = slot.best {
            nav.shownURL = url
            showDecoded(best, url: url, isNewImage: true)
        } else if let error = slot.error {
            nav.shownURL = url
            showError(error, url: url)
        }
        // else: keep the previous picture while this one decodes (docs/UI_SPEC.md §11).
        refreshPreload()
        readInfo(url)
        updateStatus()
        if slot.isDone { finishLoad() }
        imageWillAppear(url)
    }

    func imageWillAppear(_ url: URL) {
        filmstripCurrentChanged()
        detailImageChanged(url)
    }

    private func readInfo(_ url: URL) {
        infoTicket = scheduler.submit(.background, priority: .high, work: { _ in try ImageInfo.read(url) },
                                      completion: { [weak self] result in
            guard let self, currentURL == url else { return }
            info = try? result.get()
            updateStatus()
        })
    }

    func slot(for url: URL) -> ImageSlot {
        if let slot = nav.slots[url] { return slot }
        let slot = ImageSlot(url: url)
        nav.slots[url] = slot
        return slot
    }

    // MARK: Preloading

    /// Keeps the planned neighbours decoded and drops everything else (docs/TECH_SPEC.md §5.2–5.3).
    func refreshPreload() {
        guard let index = nav.index, !nav.entries.isEmpty else { return }
        let plan = PreloadPlanner.plan(index: index, count: nav.entries.count, direction: nav.direction,
                                       perSide: settings.preloadEachSide, wrap: settings.wrapAround)
        let wanted = plan.screen.map { nav.entries[$0].url }
        // Thumbnails around the current image (stage 0) wait until browsing pauses: made while the user is
        // stepping quickly they would compete with the neighbours' screen decodes (docs/BENCH.md, M5).
        let thumbURLs = plan.thumbnails.map { nav.entries[$0].url }
        nav.thumbTask?.cancel()
        nav.thumbTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard let self, !Task.isCancelled else { return }
            thumbs.want(thumbURLs, client: "navigation")
        }
        let wantedSet = Set(wanted)
        // Drop slots that left the neighbourhood (keep the one still on screen).
        for (url, slot) in nav.slots where !wantedSet.contains(url) && url != nav.shownURL {
            slot.ticket?.cancel()
            nav.slots[url] = nil
        }
        // Region sources of huge files hold hundreds of MB: keep them for the current image and the next only.
        for (rank, url) in wanted.enumerated() where rank > 1 { nav.slots[url]?.source = nil }
        for (rank, url) in wanted.enumerated() {
            let slot = slot(for: url)
            if slot.isDone { continue }
            let isCurrent = rank == 0
            let lane: DecodeScheduler.Lane = isCurrent ? .interactive : .background
            if let ticket = slot.ticket, !ticket.isCancelled {
                // Promote a neighbour that became current and has not started yet.
                if isCurrent && slot.lane == .background && !ticket.isExecuting {
                    ticket.cancel()
                } else {
                    continue
                }
            }
            decode(slot, lane: lane, rank: rank)
        }
    }

    private func decode(_ slot: ImageSlot, lane: DecodeScheduler.Lane, rank: Int) {
        let url = slot.url
        let renderer = renderer
        let longSide = screenLongSide
        let preferEmbedded = settings.rawMode == .embeddedPreview
        let priority: DecodeScheduler.Priority = switch rank {
        case 0: .veryHigh
        case 1: .high
        case 2, 3: .normal
        default: .low
        }
        slot.lane = lane
        slot.ticket = scheduler.submit(lane, priority: priority, work: { isCancelled in
            let state = Signposts.decode.beginInterval("Decode", id: Signposts.decode.makeSignpostID(), "\(url.lastPathComponent)")
            defer { Signposts.decode.endInterval("Decode", state) }
            let (pixels, meta, source) = try SourceFactory.screenDecode(url, screenLongSide: longSide,
                                                                         preferEmbedded: preferEmbedded, isCancelled: isCancelled)
            if isCancelled() { throw DecodeError.cancelled }
            let texture = try renderer.makeTexture(pixels)
            return (DecodedTexture(texture: texture, meta: meta,
                                   coverage: Double(pixels.width) / Double(max(1, meta.orientedSize.width))),
                    source.map(SourceBox.init))
        }, completion: { [weak self] result in
            guard let self, nav.slots[url] === slot else { return }
            slot.ticket = nil
            switch result {
            case .success(let (decoded, box)):
                slot.screen = decoded
                slot.meta = decoded.meta
                slot.source = box?.source
            case .failure(DecodeError.cancelled):
                return
            case .failure(let error):
                slot.error = "\(error)"
            }
            slotFinished(slot)
        })
    }

    private func slotFinished(_ slot: ImageSlot) {
        guard slot.url == nav.currentURL else { return }
        let isNew = nav.shownURL != slot.url
        nav.shownURL = slot.url
        if let screen = slot.screen {
            showDecoded(screen, url: slot.url, isNewImage: isNew)
        } else if let error = slot.error {
            showError(error, url: slot.url)
        }
        finishLoad()
        updateDetail()
        // Neighbours waited while a huge image decoded; let them go now.
        refreshPreload()
    }

    // MARK: Trash

    func moveCurrentToTrash() {
        guard let url = nav.currentURL, let index = nav.index else { return }
        if settings.confirmTrash {
            let alert = NSAlert()
            alert.messageText = String(localized: "Chuyển \"\(url.lastPathComponent)\" vào Thùng rác?")
            alert.addButton(withTitle: String(localized: "Chuyển vào Thùng rác"))
            alert.addButton(withTitle: String(localized: "Huỷ"))
            alert.showsSuppressionButton = true
            alert.suppressionButton?.title = String(localized: "Không hỏi lại")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            if alert.suppressionButton?.state == .on { settings.confirmTrash = false }
        }
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        } catch {
            NSAlert(error: error).runModal()
            return
        }
        nav.slots[url]?.ticket?.cancel()
        nav.slots[url] = nil
        nav.entries.remove(at: index)
        if nav.entries.isEmpty {
            nav.index = nil
            currentURL = nil
            texture = nil
            meta = nil
            messageView.message = String(localized: "Thư mục không còn ảnh nào")
            metalView.setNeedsRender()
            updateStatus()
            return
        }
        nav.index = min(index, nav.entries.count - 1)
        currentChanged()
        folderChanged()
    }
}
