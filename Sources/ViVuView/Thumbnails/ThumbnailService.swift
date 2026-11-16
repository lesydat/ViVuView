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

    func aspect(for url: URL) -> Double? { sizes[url].map { Double($0.width) / Double(max(1, $0.height)) } }

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
        for (url, ticket) in tickets where !wanted.contains(url) {
            ticket.cancel()
            tickets[url] = nil
        }
        for (rank, url) in order.enumerated() where textures.peek(url) == nil && tickets[url] == nil {
            start(url, rank: rank)
        }
    }

    private func start(_ url: URL, rank: Int) {
        let store = store, renderer = renderer
        let priority: DecodeScheduler.Priority = rank < 8 ? .high : rank < 40 ? .normal : .low
        tickets[url] = scheduler.submit(.thumbnails, priority: priority, work: { isCancelled in
            let thumb: CompressedThumbnail
            let pixels: PixelBuffer
            if let cached = store.get(url) {
                thumb = cached
                pixels = try ThumbnailStore.decode(cached)
            } else {
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
            guard case .success(let decoded) = result else { return }
            textures.insert(decoded, for: url, cost: decoded.texture.estimatedBytes)
            sizes[url] = decoded.meta.orientedSize
            onThumbnail.forEach { $0(url) }
        })
    }

    /// Reads the size of every image in `urls` from its header, `priority` ones first, in batches.
    func readSizes(_ urls: [URL], priority: [URL]) {
        sizeTicket?.cancel()
        sizeGeneration += 1
        let generation = sizeGeneration
        let known = sizes
        var order = priority.filter { known[$0] == nil }
        let prioritySet = Set(order)
        order += urls.filter { known[$0] == nil && !prioritySet.contains($0) }
        readBatch(order[...], generation: generation)
    }

    private func readBatch(_ remaining: ArraySlice<URL>, generation: Int) {
        guard !remaining.isEmpty, generation == sizeGeneration else { return }
        let batch = Array(remaining.prefix(64))
        let rest = remaining.dropFirst(64)
        sizeTicket = scheduler.submit(.thumbnails, priority: .low, work: { isCancelled in
            var found: [(URL, PixelSize)] = []
            for url in batch {
                if isCancelled() { break }
                if let meta = try? ImageIODecoder.meta(url) { found.append((url, meta.orientedSize)) }
            }
            return found
        }, completion: { [weak self] result in
            guard let self, generation == sizeGeneration, case .success(let found) = result else { return }
            for (url, size) in found { sizes[url] = size }
            onSizes.forEach { $0() }
            readBatch(rest, generation: generation)
        })
    }

    var sizesComplete: Bool { sizeTicket == nil || sizeTicket?.isFinished == true }

    func clearTextures() { textures.removeAll() }
}
