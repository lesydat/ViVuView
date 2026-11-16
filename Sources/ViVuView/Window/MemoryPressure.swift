import AppKit
import ViVuCore

/// Reacts to the system's memory pressure (docs/TECH_SPEC.md §10): on a warning the tile and thumbnail
/// budgets halve and far neighbours are dropped; when critical only the current image is kept.
@MainActor
final class MemoryPressureWatcher {
    private let source: DispatchSourceMemoryPressure
    private(set) var level: Level = .normal

    enum Level { case normal, warning, critical }

    init(onChange: @escaping @MainActor (Level) -> Void) {
        source = DispatchSource.makeMemoryPressureSource(eventMask: [.normal, .warning, .critical], queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                let event = self.source.data
                self.level = event.contains(.critical) ? .critical : event.contains(.warning) ? .warning : .normal
                onChange(self.level)
            }
        }
        source.activate()
    }

    deinit { source.cancel() }
}

extension ViewerController {
    func memoryPressureChanged(_ level: MemoryPressureWatcher.Level) {
        let tileBudget = settings.tileMemoryMB << 20
        switch level {
        case .normal:
            detail.tiles.setBudget(tileBudget)
            thumbs.setBudget(megabytes: settings.thumbnailMemoryMB)
        case .warning:
            detail.tiles.setBudget(tileBudget / 2)
            thumbs.setBudget(megabytes: settings.thumbnailMemoryMB / 2)
            dropSlots(keeping: 2)
        case .critical:
            detail.tiles.setBudget(tileBudget / 4)
            thumbs.setBudget(megabytes: 32)
            thumbs.clearTextures()
            dropSlots(keeping: 1)
            animation.frames = animation.frames.filter { $0.key == animation.index }
        }
    }

    /// Frees decoded neighbours, keeping the current image (and the next one when `keeping` is 2).
    private func dropSlots(keeping: Int) {
        guard let index = nav.index else { return }
        var keep = Set<URL>()
        if let url = nav.currentURL { keep.insert(url) }
        if keeping > 1, nav.entries.indices.contains(index + nav.direction) { keep.insert(nav.entries[index + nav.direction].url) }
        if let shown = nav.shownURL { keep.insert(shown) }
        for (url, slot) in nav.slots where !keep.contains(url) {
            slot.ticket?.cancel()
            nav.slots[url] = nil
        }
    }
}

extension ViewerController {
    /// Neighbours per side allowed by the current memory pressure (nil = the setting).
    var memoryWatcherLevelLimit: Int? {
        switch memoryLevel {
        case .normal: nil
        case .warning: 1
        case .critical: 0
        }
    }
}
