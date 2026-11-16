import AppKit
import QuartzCore
import ViVuCore

/// Animation state for image changes, the end-of-folder bounce and live rotation.
@MainActor
final class EffectsState {
    var overlay: TransitionOverlay?
    var transition: Transition?
    /// Running progress animation of the transition.
    var animation: (from: Double, to: Double, start: CFTimeInterval, duration: Double, done: () -> Void)?
    /// Interactive swipe in progress.
    var swipe: (accumulated: CGVector, axis: Axis?, lastTime: CFTimeInterval, velocity: Double, target: Int?)?
    /// End-of-folder bounce: direction and start time.
    var bounce: (direction: Int, start: CFTimeInterval)?
    /// Rotation gesture in progress, radians clockwise.
    var liveRotation: Double = 0
    var rotationAccumulated: Double = 0
    /// Pinch in progress (for pinch-to-gallery).
    var pinching = false

    enum Axis { case horizontal, vertical }
}

extension ViewerController {
    static let swipeTravelFraction = 0.35      // of the screen width (docs/UI_SPEC.md §4)
    static let swipeCommitFraction = 0.30
    static let swipeCommitVelocity = 1.2       // points per millisecond
    static let axisLockDistance = 8.0          // points
    static let bounceDuration = 0.22
    static let bounceFraction = 0.04

    var transitionStyle: Transition.Style? {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { return settings.transition == .none ? nil : .fade }
        switch settings.transition {
        case .slideFade: return .slideFade
        case .fade: return .fade
        case .none: return nil
        }
    }

    var transitionDuration: Double { max(0, settings.transitionMilliseconds) / 1000 }

    // MARK: Animated navigation

    /// Next/previous from keys, menus and buttons. Key repeat passes `animated: false` to browse fast.
    func navigate(by delta: Int, animated: Bool) {
        finishTransitionNow()
        guard let index = nav.index, !nav.entries.isEmpty, !nav.scanning else { step(by: delta); return }
        let count = nav.entries.count
        var target = index + delta
        if settings.wrapAround { target = ((target % count) + count) % count }
        guard (0..<count).contains(target), target != index else { step(by: delta); return }
        let direction = delta > 0 ? 1 : -1
        guard animated, transitionDuration > 0, let style = transitionStyle, texture != nil,
              let newTexture = slot(for: nav.entries[target].url).best,
              let transition = beginTransition(style: style, direction: direction) else {
            go(to: target, direction: direction)
            return
        }
        transition.new = TransitionImage(texture: newTexture, rect: .zero, rotation: 0)
        transition.newStartRect = startRect(for: newTexture, transition: transition)
        commit(transition, to: target, direction: direction)
        animateTransition(to: 1, duration: transitionDuration) { [weak self] in self?.endTransition() }
    }

    /// The picture currently on screen, in the coordinates of the view that will draw the transition.
    func currentTransitionImage(inMainView: Bool, overlay: TransitionOverlay?) -> TransitionImage? {
        guard let texture, let meta else { return nil }
        let vp = effectiveViewport
        let size = CGSize(width: Double(meta.orientedSize.width) * vp.scale, height: Double(meta.orientedSize.height) * vp.scale)
        let center = vp.viewPoint(CGPoint(x: Double(meta.orientedSize.width) / 2, y: Double(meta.orientedSize.height) / 2), view: viewSize)
        var rect = CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
        if !inMainView, let overlay {
            let origin = overlay.viewRect(fromScreen: window.frame).origin
            rect.origin.x += origin.x
            rect.origin.y += origin.y
        }
        return TransitionImage(texture: texture, rect: rect, rotation: Double(vp.quarterTurns) * .pi / 2 + fx.liveRotation)
    }

    /// Starts drawing a transition from the current picture. Returns nil when nothing is on screen.
    func beginTransition(style: Transition.Style, direction: Int) -> Transition? {
        let inMainView = isFullScreen
        let overlay: TransitionOverlay?
        if inMainView {
            overlay = nil
        } else {
            if fx.overlay == nil {
                let made = TransitionOverlay(renderer: renderer)
                made.view.sceneProvider = { [weak self] size in self?.fx.transition?.quads(viewSize: size) ?? [] }
                fx.overlay = made
            }
            overlay = fx.overlay
        }
        guard let screen = window.screen ?? NSScreen.main,
              let old = currentTransitionImage(inMainView: inMainView, overlay: overlay) else { return nil }
        let scale = inMainView ? metalView.backingScale : Double(screen.backingScaleFactor)
        let travel = screen.frame.width * scale * Self.swipeTravelFraction
        if let overlay {
            overlay.window.setFrame(screen.frame, display: false)
            // Recompute the old rect now that the overlay covers this screen.
            let transition = Transition(style: style, direction: direction, travel: travel,
                                        old: currentTransitionImage(inMainView: false, overlay: overlay), inMainView: false)
            fx.transition = transition
            overlay.show(on: screen, above: window)
            // The overlay shows exactly the same picture; hide the window under it.
            window.alphaValue = 0
            return transition
        }
        let transition = Transition(style: style, direction: direction, travel: travel, old: old, inMainView: true)
        fx.transition = transition
        return transition
    }

    /// Where the incoming picture starts: its own shape fitted into the outgoing picture's rect.
    func startRect(for texture: DecodedTexture, transition: Transition) -> CGRect? {
        guard let old = transition.old else { return nil }
        let turns = Int((old.rotation / (.pi / 2)).rounded())
        let shown = turns % 2 == 0 ? old.rect : CGRect(x: old.rect.midX - old.rect.height / 2, y: old.rect.midY - old.rect.width / 2,
                                                       width: old.rect.height, height: old.rect.width)
        return Transition.aspectFit(texture.meta.orientedSize.cgSize, in: shown)
    }

    /// Navigates for real (window resized while hidden) and aims the incoming picture at its final place.
    func commit(_ transition: Transition, to target: Int, direction: Int) {
        go(to: target, direction: direction)
        let overlay = transition.inMainView ? nil : fx.overlay
        if let image = currentTransitionImage(inMainView: transition.inMainView, overlay: overlay) {
            transition.new = image
            if transition.newStartRect == nil { transition.newStartRect = image.rect }
        }
        transition.committedAt = transition.progress
        redrawTransition()
    }

    func redrawTransition() {
        if let transition = fx.transition, !transition.inMainView { fx.overlay?.view.setNeedsRender() } else { metalView.setNeedsRender() }
    }

    func animateTransition(to target: Double, duration: Double, done: @escaping () -> Void) {
        guard let transition = fx.transition else { done(); return }
        fx.animation = (transition.progress, target, CACurrentMediaTime(), max(duration, 0.001), done)
        let view = transition.inMainView ? metalView : (fx.overlay?.view ?? metalView)
        view.animationStep = { [weak self] now in self?.stepTransitionAnimation(now) ?? false }
        view.startAnimating()
    }

    private func stepTransitionAnimation(_ now: CFTimeInterval) -> Bool {
        guard let transition = fx.transition, let animation = fx.animation else { return false }
        let t = min(1, (now - animation.start) / animation.duration)
        transition.progress = animation.from + (animation.to - animation.from) * Transition.easeOut(t)
        if transition.inMainView { metalView.renderNow(synchronously: false) }
        if t >= 1 {
            fx.animation = nil
            // Run the completion after this frame is drawn.
            DispatchQueue.main.async { animation.done() }
            return false
        }
        return true
    }

    /// Shows the main window again and removes the overlay one frame later (both show the same picture).
    func endTransition() {
        guard let transition = fx.transition else { return }
        fx.transition = nil
        fx.animation = nil
        if transition.inMainView {
            metalView.setNeedsRender()
            return
        }
        metalView.renderNow(synchronously: true)
        window.alphaValue = 1
        let overlay = fx.overlay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.034) { [weak self] in
            guard self?.fx.transition == nil else { return }
            overlay?.hide()
        }
    }

    /// A new change interrupts a running one: jump to its end state.
    func finishTransitionNow() {
        guard let transition = fx.transition else { return }
        fx.overlay?.view.stopAnimating()
        metalView.stopAnimating()
        if transition.committedAt == nil {
            // An uncommitted swipe being interrupted: cancel it.
            transition.progress = 0
        }
        fx.animation = nil
        fx.transition = nil
        window.alphaValue = 1
        fx.overlay?.hide()
        metalView.setNeedsRender()
    }

    var isTransitioning: Bool { fx.transition != nil }

    // MARK: Interactive swipe (docs/UI_SPEC.md §4, §5)

    /// Two-finger scroll on the trackpad. Returns true when the event was used.
    func handleTrackpadScroll(_ event: NSEvent) -> Bool {
        if event.momentumPhase != [] { return fx.swipe == nil ? false : true }   // ignore inertia
        switch event.phase {
        case .began, .mayBegin:
            fx.swipe = (.zero, nil, event.timestamp, 0, nil)
            return true
        case .changed:
            guard var swipe = fx.swipe else { return false }
            let dx = event.scrollingDeltaX, dy = event.scrollingDeltaY
            let dt = max(event.timestamp - swipe.lastTime, 0.001)
            swipe.accumulated.dx += dx
            swipe.accumulated.dy += dy
            swipe.lastTime = event.timestamp
            if swipe.axis == nil, hypot(swipe.accumulated.dx, swipe.accumulated.dy) >= Self.axisLockDistance {
                swipe.axis = abs(swipe.accumulated.dx) >= abs(swipe.accumulated.dy) ? .horizontal : .vertical
                if swipe.axis == .horizontal && !isZoomed { swipe.target = beginSwipe(dx: swipe.accumulated.dx) }
                if swipe.axis == .vertical && !isZoomed { verticalSwipe(up: swipe.accumulated.dy < 0) }
            }
            if isZoomed {
                let scale = metalView.backingScale
                pan(by: CGVector(dx: dx * scale, dy: dy * scale))
            } else if swipe.axis == .horizontal {
                swipe.velocity = dx / (dt * 1000)
                updateSwipe(dx: swipe.accumulated.dx)
            }
            fx.swipe = swipe
            return true
        case .ended, .cancelled:
            guard let swipe = fx.swipe else { return false }
            fx.swipe = nil
            if swipe.axis == .horizontal && !isZoomed {
                endSwipe(target: swipe.target, velocity: swipe.velocity, cancelled: event.phase == .cancelled)
            }
            return true
        default:
            return fx.swipe != nil
        }
    }

    /// Fingers moving left (negative dx) go to the next image, unless the setting inverts it.
    private func swipeDirection(dx: Double) -> Int {
        let natural = dx < 0 ? 1 : -1
        return settings.invertSwipe ? -natural : natural
    }

    private func beginSwipe(dx: Double) -> Int? {
        finishTransitionNow()
        guard let index = nav.index, !nav.scanning, texture != nil else { return nil }
        let direction = swipeDirection(dx: dx)
        let count = nav.entries.count
        var target = index + direction
        if settings.wrapAround && count > 1 { target = ((target % count) + count) % count }
        guard (0..<count).contains(target), target != index else { return nil }   // edge: bounce on release
        guard let transition = beginTransition(style: transitionStyle ?? .fade, direction: direction) else { return nil }
        if let newTexture = slot(for: nav.entries[target].url).best {
            transition.new = TransitionImage(texture: newTexture, rect: .zero, rotation: 0)
            transition.newStartRect = startRect(for: newTexture, transition: transition)
        }
        return target
    }

    private func updateSwipe(dx: Double) {
        guard let transition = fx.transition, transition.committedAt == nil else { return }
        let travelPoints = (window.screen?.frame.width ?? 1440) * Self.swipeTravelFraction
        let along = -dx * Double(settings.invertSwipe ? -1 : 1) * Double(transition.direction)
        transition.progress = min(max(along / travelPoints, 0), 1)
        // The incoming picture may have finished decoding meanwhile.
        if transition.new == nil, let target = fx.swipe?.target, let tex = slot(for: nav.entries[target].url).best {
            transition.new = TransitionImage(texture: tex, rect: .zero, rotation: 0)
            transition.newStartRect = startRect(for: tex, transition: transition)
        }
        redrawTransition()
    }

    private func endSwipe(target: Int?, velocity: Double, cancelled: Bool) {
        guard let target, let transition = fx.transition else {
            if target == nil && !cancelled, nav.entries.count > 0 { bounceAtEnd(direction: swipeDirection(dx: -velocity)) }
            return
        }
        let fast = abs(velocity) >= Self.swipeCommitVelocity && swipeDirection(dx: velocity) == transition.direction
        if !cancelled && (transition.progress >= Self.swipeCommitFraction || fast) {
            commit(transition, to: target, direction: transition.direction)
            let remaining = transitionDuration * (1 - transition.progress)
            animateTransition(to: 1, duration: max(remaining, 0.06)) { [weak self] in self?.endTransition() }
        } else {
            animateTransition(to: 0, duration: max(transitionDuration * transition.progress, 0.06)) { [weak self] in
                self?.endTransition()
            }
        }
    }

    // MARK: End of folder

    func bounceAtEnd(direction: Int) {
        guard texture != nil, transitionStyle != nil else { return }
        fx.bounce = (direction, CACurrentMediaTime())
        metalView.animationStep = { [weak self] now in
            guard let self, let bounce = fx.bounce else { return false }
            if now - bounce.start >= Self.bounceDuration {
                fx.bounce = nil
                return false
            }
            return true
        }
        metalView.startAnimating()
    }

    /// Horizontal offset (device pixels) of the bounce right now.
    var bounceOffset: Double {
        guard let bounce = fx.bounce else { return 0 }
        let t = min(1, (CACurrentMediaTime() - bounce.start) / Self.bounceDuration)
        return -Double(bounce.direction) * viewSize.width * Self.bounceFraction * sin(.pi * t)
    }

    // MARK: Rotation and pinch gestures

    func rotateGesture(_ event: NSEvent) {
        switch event.phase {
        case .began:
            fx.rotationAccumulated = 0
        case .changed:
            fx.rotationAccumulated += Double(event.rotation)          // degrees, counter-clockwise positive
            fx.liveRotation = -fx.rotationAccumulated * .pi / 180
            metalView.setNeedsRender()
        case .ended, .cancelled:
            let turns = Int((-fx.rotationAccumulated / 90).rounded())
            fx.liveRotation = 0
            fx.rotationAccumulated = 0
            if turns != 0, meta != nil {
                for _ in 0..<abs(turns) { rotate(clockwise: turns > 0) }
            } else {
                metalView.setNeedsRender()
            }
        default:
            break
        }
    }

    func pinchGesture(_ event: NSEvent) {
        switch event.phase {
        case .began:
            fx.pinching = true
        case .ended, .cancelled:
            fx.pinching = false
            // Pinched well below fit and let go: open the gallery (M6); otherwise settle back at fit.
            if !viewport.isFit && effectiveViewport.scale < fitScale * 0.8 {
                fitToWindow()
                pinchedBelowFit()
            } else if !viewport.isFit && effectiveViewport.scale < fitScale {
                fitToWindow()
            }
            return
        default:
            break
        }
        zoom(to: effectiveViewport.scale * (1 + event.magnification), anchor: viewPoint(event), flash: true, allowBelowFit: true)
    }

    /// Hook: pinch-in past fit opens the gallery (M6).
    func pinchedBelowFit() {}

    /// Hook: vertical swipe at fit shows (up) or hides (down) the filmstrip (M5).
    func verticalSwipe(up: Bool) {}
}
