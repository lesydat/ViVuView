import AppKit
import ViVuCore
import ViVuRender

/// Thumbnails for the filmstrip, the gallery and stage 0 (docs/TECH_SPEC.md §7): compressed in a RAM store
/// (tier 1), decompressed textures only for what is on or near the screen (tier 2). Also reads every image's
/// size from its header so layouts know the shapes before thumbnails exist. Nothing is written to disk.
@MainActor
final class ThumbnailService {
    let renderer: Renderer
    let scheduler: DecodeScheduler
    let store: ThumbnailStore
    private var textures = ByteLRU<URL, DecodedTexture>(budget: 128 << 20)
    private var tickets: [URL: DecodeTicket] = [:]
    /// What each client (filmstrip, gallery, navigation) wants, most urgent first.
    private var wants: [String: [URL]] = [:]
    /// Oriented image sizes from headers or thumbnails.
    private(set) var sizes: [URL: PixelSize] = [:]
    private var sizeTicket: DecodeTicket?
    private var sizeGeneration = 0
    /// Called on the main actor when a thumbnail texture becomes available.
    var onThumbnail: [(URL) -> Void] = []
    /// Called when a batch of image sizes arrived (layouts should rebuild).
    var onSizes: [() -> Void] = []

    init(renderer: Renderer, scheduler: DecodeScheduler, budgetMB: Int) {
        self.renderer = renderer
        self.scheduler = scheduler
        store = ThumbnailStore(budgetBytes: budgetMB << 20)
    }

    func setBudget(megabytes: Int) { store.setBudget(megabytes << 20) }

    func texture(for url: URL) -> DecodedTexture? { textures.value(for: url) }

    /// Files whose header could not be read: laid out as known 3:2 cells so they never hold up the layout.
    private(set) var unreadable: Set<URL> = []

    func aspect(for url: URL) -> Double? {
        if let size = sizes[url] { return Double(size.width) / Double(max(1, size.height)) }
        return unreadable.contains(url) ? MasonryLayout.placeholderAspect : nil
    }

    func noteSize(_ size: PixelSize, for url: URL) { sizes[url] = size }

    /// Replaces what `client` wants decoded; jobs nobody wants any more are cancelled.
    func want(_ urls: [URL], client: String) {
        wants[client] = urls
        var wanted = Set<URL>()
        var order: [URL] = []
        // Interleave clients so each one's most urgent items go first.
        let lists = wants.values.sorted { $0.count < $1.count }
        let longest = lists.map(\.count).max() ?? 0
        for i in 0..<longest {
            for list in lists where i < list.count && wanted.insert(list[i]).inserted { order.append(list[i]) }
        }
        // Room for everything wanted at once, or visible thumbnails evict each other and stay blank.
        let needed = order.count * Tuning.thumbnailTextureEstimate * 5 / 4
        let budget = min(max(needed, Tuning.thumbnailTextureMinimumMB << 20), Tuning.thumbnailTextureMaximumMB << 20)
        if budget != textures.budget { _ = textures.setBudget(budget) }
        // A job already running is left to finish (its thumbnail lands in the store): cancelling it would not
        // stop ImageIO, and starting it again later ran the same slow picture twice on both workers.
        for (url, ticket) in tickets where !wanted.contains(url) && !ticket.isExecuting {
            ticket.cancel()
            tickets[url] = nil
        }
        for (rank, url) in order.enumerated() where textures.peek(url) == nil && tickets[url] == nil {
            start(url, rank: rank)
        }
    }

    /// Thrown on the normal lane when the header shows a very large picture: the job moves to the large lane.
    private struct MoveToLargeLane: Error {}

    private func isLarge(_ size: PixelSize) -> Bool {
        Double(size.width) * Double(size.height) / 1_000_000 > Tuning.thumbnailLargeMegapixels
    }

    private func start(_ url: URL, rank: Int, large: Bool? = nil) {
        let store = store, renderer = renderer
        let priority: DecodeScheduler.Priority = rank < 8 ? .high : rank < 40 ? .normal : .low
        // Known size from the header pass decides the lane; unknown ones check the header first.
        let large = large ?? (VectorImage.isVector(url) ? nil : sizes[url].map(isLarge))
        let checkSize = large == nil
        let threshold = Tuning.thumbnailLargeMegapixels
        tickets[url] = scheduler.submit(large == true ? .largeThumbnails : .thumbnails, priority: priority, work: { isCancelled in
            let thumb: CompressedThumbnail
            let pixels: PixelBuffer
            if let cached = store.get(url) {
                thumb = cached
                pixels = try ThumbnailStore.decode(cached)
            } else {
                if checkSize {
                    if VectorImage.isVector(url) {
                        // Drawing cost follows the document's complexity, roughly its file size.
                        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                        if bytes > VectorImage.largeFileBytes { throw MoveToLargeLane() }
                    } else if let size = (try? ImageIODecoder.meta(url))?.orientedSize,
                              Double(size.width) * Double(size.height) / 1_000_000 > threshold {
                        throw MoveToLargeLane()
                    }
                }
                (thumb, pixels) = try ThumbnailStore.make(url)
                store.put(thumb, for: url)
            }
            if isCancelled() { throw DecodeError.cancelled }
            let texture = try renderer.makeTexture(pixels)
            let meta = ImageMeta(storedSize: thumb.imageSize, uti: "public.image")
            return DecodedTexture(texture: texture, meta: meta, coverage: Double(pixels.width) / Double(max(1, thumb.imageSize.width)))
        }, completion: { [weak self] result in
            guard let self else { return }
            tickets[url] = nil
            switch result {
            case .success(let decoded):
                textures.insert(decoded, for: url, cost: decoded.texture.estimatedBytes)
                sizes[url] = decoded.meta.orientedSize
                onThumbnail.forEach { $0(url) }
            case .failure(let error) where error is MoveToLargeLane:
                start(url, rank: rank, large: true)
            case .failure:
                break
            }
        })
    }

    /// Reads the size of every image in `urls` from its header, `priority` ones first, in batches.
    func readSizes(_ urls: [URL], priority: [URL]) {
        sizeTicket?.cancel()
        sizeGeneration += 1
        let generation = sizeGeneration
        let known = sizes
        let skip = unreadable
        var order = priority.filter { known[$0] == nil && !skip.contains($0) }
        let prioritySet = Set(order)
        order += urls.filter { known[$0] == nil && !skip.contains($0) && !prioritySet.contains($0) }
        readBatch(order[...], generation: generation)
    }

    private func readBatch(_ remaining: ArraySlice<URL>, generation: Int) {
        guard !remaining.isEmpty, generation == sizeGeneration else { return }
        let batch = Array(remaining.prefix(64))
        let rest = remaining.dropFirst(64)
        sizeTicket = scheduler.submit(.thumbnails, priority: .low, work: { isCancelled in
            var found: [(URL, PixelSize?)] = []
            for url in batch {
                if isCancelled() { break }
                found.append((url, (try? ImageIODecoder.meta(url))?.orientedSize))
            }
            return found
        }, completion: { [weak self] result in
            guard let self, generation == sizeGeneration, case .success(let found) = result else { return }
            for (url, size) in found {
                if let size { sizes[url] = size } else { unreadable.insert(url) }
            }
            onSizes.forEach { $0() }
            readBatch(rest, generation: generation)
        })
    }

    var sizesComplete: Bool { sizeTicket == nil || sizeTicket?.isFinished == true }

    func clearTextures() { textures.removeAll() }
}
