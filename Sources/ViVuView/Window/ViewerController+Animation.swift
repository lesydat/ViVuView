import AppKit
import ViVuCore
import ViVuRender

/// Playback of animated images (docs/TECH_SPEC.md §10): frames decoded on demand into a small ring
/// (8 ahead), never the whole animation in RAM.
@MainActor
final class AnimationState {
    var url: URL?
    var delays: [Double] = []
    var index = 0
    var playing = true
    var frames: [Int: DecodedTexture] = [:]
    var tickets: [Int: DecodeTicket] = [:]
    var timer: Timer?
    var nextDue: CFTimeInterval = 0

    static let ahead = 8

    func reset() {
        timer?.invalidate()
        timer = nil
        tickets.values.forEach { $0.cancel() }
        tickets = [:]
        frames = [:]
        delays = []
        index = 0
        playing = true
        url = nil
    }
}

extension ViewerController {
    var isAnimating: Bool { animation.url != nil && animation.delays.count > 1 }

    /// Called when the current image's pixels appear: start playback for animated files.
    func animationImageShown() {
        guard let url = currentURL, let meta, meta.isAnimated, nav.shownURL == url else {
            if animation.url != nil && animation.url != currentURL { animation.reset() }
            return
        }
        guard animation.url != url else { return }
        animation.reset()
        animation.url = url
        if let first = texture { animation.frames[0] = first }
        scheduler.submit(.background, priority: .high, work: { _ in try AnimatedDecoder.durations(url) },
                         completion: { [weak self] result in
            guard let self, animation.url == url, case .success(let delays) = result, delays.count > 1 else { return }
            animation.delays = delays
            animation.nextDue = CACurrentMediaTime() + delays[0]
            requestFrames()
            startAnimationTimer()
            updateStatus()
        })
    }

    private func startAnimationTimer() {
        animation.timer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.animationTick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        animation.timer = timer
    }

    private func animationTick() {
        guard animation.playing, isAnimating, CACurrentMediaTime() >= animation.nextDue else { return }
        let next = (animation.index + 1) % animation.delays.count
        // Waits on a frame that is not decoded yet instead of skipping it.
        guard animation.frames[next] != nil else { requestFrames(); return }
        showFrame(next)
        animation.nextDue = max(animation.nextDue + animation.delays[next], CACurrentMediaTime())
    }

    func showFrame(_ i: Int) {
        guard let frame = animation.frames[i] else { return }
        animation.index = i
        texture = frame
        // Keep only frames that are still ahead.
        let count = animation.delays.count
        for key in animation.frames.keys {
            let distance = (key - i + count) % count
            if distance > AnimationState.ahead { animation.frames[key] = nil }
        }
        requestFrames()
        metalView.setNeedsRender()
        if !statusBar.isHidden { updateStatus() }
    }

    private func requestFrames() {
        guard let url = animation.url, animation.delays.count > 1 else { return }
        let count = animation.delays.count
        let renderer = renderer, longSide = screenLongSide
        for step in 1...min(AnimationState.ahead, count - 1) {
            let i = (animation.index + step) % count
            guard animation.frames[i] == nil, animation.tickets[i] == nil else { continue }
            animation.tickets[i] = scheduler.submit(.background, priority: step <= 2 ? .veryHigh : .high, work: { isCancelled in
                let pixels = try AnimatedDecoder.frame(url, index: i, maxPixel: longSide)
                if isCancelled() { throw DecodeError.cancelled }
                let meta = try ImageIODecoder.meta(url)
                return DecodedTexture(texture: try renderer.makeTexture(pixels, mipmapped: false), meta: meta,
                                      coverage: Double(pixels.width) / Double(max(1, meta.orientedSize.width)))
            }, completion: { [weak self] result in
                guard let self, animation.url == url else { return }
                animation.tickets[i] = nil
                if case .success(let frame) = result { animation.frames[i] = frame }
            })
        }
    }

    func toggleAnimationPlayback() {
        guard isAnimating else { navigate(by: 1, animated: true); return }
        animation.playing.toggle()
        animation.nextDue = CACurrentMediaTime() + animation.delays[animation.index]
        updateStatus()
    }

    func stepAnimation(by delta: Int) {
        guard isAnimating else { return }
        animation.playing = false
        let count = animation.delays.count
        let target = (animation.index + delta + count) % count
        if animation.frames[target] != nil {
            showFrame(target)
        } else {
            animation.index = (target - 1 + count) % count
            requestFrames()
        }
        updateStatus()
    }

    var animationStatus: String? {
        guard isAnimating else { return nil }
        return String(localized: "khung \(animation.index + 1)/\(animation.delays.count)")
            + (animation.playing ? "" : " ⏸")
    }
}
