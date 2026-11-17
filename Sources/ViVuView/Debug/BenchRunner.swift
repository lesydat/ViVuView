import AppKit
import QuartzCore
import ViVuCore

/// In-app benchmarks (docs/TECH_SPEC.md §11.2). Times run from the command to the moment a frame showing
/// the new image is presented on screen (`MTLDrawable.addPresentedHandler`).
///
///   --bench-navigate <folder> [--count N]   browse the folder in three rhythms, print p50/p95/max
///   --bench-open <file>                     time from process start to first and to sharp frame
///   --bench-idle <file>                     CPU use while showing a still image for 10 s
@MainActor
final class BenchRunner {
    private let viewer: ViewerController
    private var frames: [Int: (url: URL?, sharp: Bool)] = [:]
    private var pending: [(id: UUID, url: URL, sharp: Bool)] = []
    private var results: [UUID: CFTimeInterval] = [:]
    /// First presentation of each image (any stage, sharp), for --bench-open.
    private var firstSeen: [URL: (any: CFTimeInterval?, sharp: CFTimeInterval?)] = [:]

    init(viewer: ViewerController) {
        self.viewer = viewer
        let original = viewer.metalView.sceneProvider
        viewer.metalView.sceneProvider = { [weak self, weak viewer] size in
            guard let viewer else { return [] }
            let url = viewer.nav.shownURL
            let sharp = url.flatMap { viewer.nav.slots[$0]?.screen?.texture } === viewer.texture?.texture && viewer.texture != nil
            self?.frames[viewer.metalView.frameNumber] = (url, sharp)
            return original?(size) ?? []
        }
        viewer.metalView.onPresented = { [weak self] frame, time in self?.presented(frame: frame, time: time) }
    }

    private func presented(frame: Int, time: CFTimeInterval) {
        if ProcessInfo.processInfo.environment["VIVU_BENCH_DEBUG"] != nil {
            print("presented frame \(frame) at \(time) info \(String(describing: frames[frame]))")
        }
        guard time > 0 else { return }
        guard let info = frames.removeValue(forKey: frame) else { return }
        if let url = info.url {
            var seen = firstSeen[url] ?? (nil, nil)
            if seen.any == nil { seen.any = time }
            if info.sharp && seen.sharp == nil { seen.sharp = time }
            firstSeen[url] = seen
        }
        pending.removeAll { waiter in
            guard info.url == waiter.url, info.sharp || !waiter.sharp else { return false }
            results[waiter.id] = time
            return true
        }
    }

    /// Registers interest in the first presented frame showing `url` (sharp if asked). Register before
    /// triggering the change, so a frame presented right away is not missed.
    private func expect(_ url: URL, sharp: Bool) -> UUID {
        let id = UUID()
        pending.append((id, url, sharp))
        return id
    }

    /// Presentation time for an `expect`, or nil after `timeout` seconds.
    private func wait(_ id: UUID, timeout: Double = 10) async -> CFTimeInterval? {
        let deadline = CACurrentMediaTime() + timeout
        while CACurrentMediaTime() < deadline {
            if let time = results.removeValue(forKey: id) { return time }
            try? await Task.sleep(for: .milliseconds(1))
        }
        pending.removeAll { $0.id == id }
        return nil
    }

    static func stats(_ ms: [Double]) -> String {
        guard !ms.isEmpty else { return "n=0" }
        let s = ms.sorted()
        func p(_ q: Double) -> Double { s[min(s.count - 1, Int(Double(s.count - 1) * q))] }
        return String(format: "n=%d p50=%.1fms p95=%.1fms max=%.1fms", s.count, p(0.5), p(0.95), s.last!)
    }

    func run(arguments: [String]) async {
        // Measure decode-and-show latency, not the deliberate transition animation.
        viewer.settings.transition = .none
        if let folder = AppDelegate.value(after: "--bench-navigate", in: arguments) {
            let count = AppDelegate.value(after: "--count", in: arguments).flatMap(Int.init) ?? 300
            await navigate(folder: URL(fileURLWithPath: folder), count: count)
        } else if let file = AppDelegate.value(after: "--bench-open", in: arguments) {
            await openTiming(URL(fileURLWithPath: file))
        } else if let file = AppDelegate.value(after: "--bench-zoom", in: arguments) {
            await zoomTiming(URL(fileURLWithPath: file))
        } else if let file = AppDelegate.value(after: "--bench-idle", in: arguments) {
            await idle(URL(fileURLWithPath: file))
        }
        NSApp.terminate(nil)
    }

    private func navigate(folder: URL, count: Int) async {
        guard let entries = try? FolderIndex.scan(folder, sort: .name, ascending: true), entries.count > 10 else {
            print("bench-navigate: need a folder with more than 10 images"); return
        }
        print("bench-navigate: \(folder.path) (\(entries.count) images), preload \(viewer.settings.preloadEachSide) per side")
        viewer.open(entries[0].url)
        await viewer.waitForLoad()
        try? await Task.sleep(for: .seconds(1))
        let steps = min(count, entries.count - 1)
        let start = MemoryFootprint.current()

        // A. Browsing at a reading pace: each step waits until the next neighbour is ready.
        for round in 1...2 {
            viewer.go(to: 0, direction: 1)
            await viewer.waitForLoad()
            try? await Task.sleep(for: .milliseconds(500))
            var first: [Double] = [], sharpTimes: [Double] = []
            for i in 1...steps {
                await waitNeighbourReady(entries, i)
                let url = entries[i].url
                let anyFrame = expect(url, sharp: false), sharpFrame = expect(url, sharp: true)
                let t0 = CACurrentMediaTime()
                viewer.perform(.next)
                if let t = await wait(anyFrame) { first.append((t - t0) * 1000) }
                if let t = await wait(sharpFrame) { sharpTimes.append((t - t0) * 1000) }
            }
            print("A\(round) paced, preloaded   first frame: \(Self.stats(first))")
            print("A\(round) paced, preloaded   sharp:       \(Self.stats(sharpTimes))")
            print("A\(round) footprint after round: \(MemoryFootprint.megabytes(MemoryFootprint.current())) (start \(MemoryFootprint.megabytes(start)))")
        }

        // B. As fast as the images can be shown: next as soon as the previous one is sharp.
        viewer.go(to: 0, direction: 1)
        await viewer.waitForLoad()
        try? await Task.sleep(for: .milliseconds(500))
        var cold: [Double] = []
        for i in 1...min(steps, 100) {
            let url = entries[i].url
            let sharpFrame = expect(url, sharp: true)
            let t0 = CACurrentMediaTime()
            viewer.perform(.next)
            if let t = await wait(sharpFrame) { cold.append((t - t0) * 1000) }
        }
        print("B  back-to-back, sharp:        \(Self.stats(cold))")

        // C. Key repeat (30 Hz): never waits. Each step's image should appear within one frame if it was
        // preloaded; images not decoded in time are skipped over (the old picture stays), which is allowed.
        viewer.go(to: 0, direction: 1)
        await viewer.waitForLoad()
        try? await Task.sleep(for: .milliseconds(500))
        let repeats = min(steps, 120)
        var ids: [(UUID, CFTimeInterval)] = []
        let cStart = CACurrentMediaTime()
        for i in 1...repeats {
            let id = expect(entries[i].url, sharp: false)
            ids.append((id, CACurrentMediaTime()))
            viewer.perform(.next)
            try? await Task.sleep(for: .milliseconds(33))
        }
        let elapsed = CACurrentMediaTime() - cStart
        try? await Task.sleep(for: .milliseconds(300))
        var latencies: [Double] = []
        for (id, t0) in ids {
            if let t = results.removeValue(forKey: id) { latencies.append((t - t0) * 1000) }
        }
        pending.removeAll()
        let overFrame = latencies.filter { $0 > 1000.0 / 60 }.count
        let queued = viewer.nav.slots.values.filter { $0.ticket != nil }.count
        print(String(format: "C  key repeat 30 Hz: %d steps in %.2fs; shown %d, skipped %d; slower than one 60 Hz frame: %d",
                     repeats, elapsed, latencies.count, repeats - latencies.count, overFrame))
        print("C  key repeat latency:         \(Self.stats(latencies)); decodes queued at end: \(queued)")
        print("footprint end: \(MemoryFootprint.megabytes(MemoryFootprint.current()))")
    }

    private func waitNeighbourReady(_ entries: [FolderEntry], _ i: Int) async {
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            if viewer.nav.slots[entries[i].url]?.isDone == true { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    private func openTiming(_ url: URL) async {
        // The app was launched with the file; time from process start.
        func seen() -> (any: CFTimeInterval?, sharp: CFTimeInterval?)? { firstSeen.first { $0.key.path == url.path }?.value }
        let deadline = CACurrentMediaTime() + 30
        while seen()?.sharp == nil && CACurrentMediaTime() < deadline {
            try? await Task.sleep(for: .milliseconds(2))
        }
        let first = seen()?.any, sharp = seen()?.sharp
        let base = launchUptime
        func ms(_ t: CFTimeInterval?) -> String { t.map { String(format: "%.0f ms", ($0 - base) * 1000) } ?? "timeout" }
        print("bench-open: \(url.lastPathComponent) first frame \(ms(first)), sharp \(ms(sharp)) after process start; "
              + "footprint \(MemoryFootprint.megabytes(MemoryFootprint.current()))")
    }

    /// Large image: time until full-resolution detail is ready, then until a 100% view is fully tiled,
    /// then after a pan. Peak footprint over the whole run.
    private func zoomTiming(_ url: URL) async {
        let t0 = CACurrentMediaTime()
        var peak = MemoryFootprint.current()
        func sample() { peak = max(peak, MemoryFootprint.current()) }
        await viewer.waitForLoad()
        let shown = CACurrentMediaTime()
        while viewer.detail.source == nil && viewer.detail.tier != .single && CACurrentMediaTime() - t0 < 60 {
            sample()
            try? await Task.sleep(for: .milliseconds(5))
        }
        let ready = CACurrentMediaTime()
        func tilesDone() -> Bool { viewer.detail.pending.isEmpty }
        viewer.perform(.actualSize)
        let z0 = CACurrentMediaTime()
        try? await Task.sleep(for: .milliseconds(20))
        while !tilesDone() && CACurrentMediaTime() - z0 < 20 { sample(); try? await Task.sleep(for: .milliseconds(2)) }
        let zoomed = CACurrentMediaTime()
        viewer.pan(by: CGVector(dx: -viewer.viewSize.width * 0.8, dy: -viewer.viewSize.height * 0.5))
        let p0 = CACurrentMediaTime()
        try? await Task.sleep(for: .milliseconds(5))
        while !tilesDone() && CACurrentMediaTime() - p0 < 20 { sample(); try? await Task.sleep(for: .milliseconds(2)) }
        let panned = CACurrentMediaTime()
        sample()
        print(String(format: "bench-zoom: %@ first picture %.0f ms, detail ready %.0f ms, 100%% tiled %.0f ms, pan tiled %.0f ms, %d tiles, peak footprint %@",
                     url.lastPathComponent, (shown - t0) * 1000, (ready - t0) * 1000, (zoomed - z0) * 1000, (panned - p0) * 1000,
                     viewer.detail.tiles.count, MemoryFootprint.megabytes(peak)))
    }

    private func idle(_ url: URL) async {
        await viewer.waitForLoad()
        try? await Task.sleep(for: .seconds(1))
        let before = cpuSeconds()
        try? await Task.sleep(for: .seconds(10))
        let used = cpuSeconds() - before
        print(String(format: "bench-idle: %.2f%% CPU over 10 s", used / 10 * 100))
    }

    private func cpuSeconds() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        return Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1e6
            + Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1e6
    }
}
