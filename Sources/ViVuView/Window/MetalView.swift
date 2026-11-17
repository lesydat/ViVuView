import AppKit
import Metal
import QuartzCore
import ViVuRender

/// A view backed by CAMetalLayer that draws on demand (docs/TECH_SPEC.md §3): `setNeedsRender()`
/// coalesces requests into the next frame; a display link runs only while `isAnimating` says so.
@MainActor
final class MetalView: NSView {
    let renderer: Renderer
    /// Supplies the quads for a view of the given size in device pixels.
    var sceneProvider: ((CGSize) -> [Quad])?
    /// Background clear color (premultiplied).
    var clearColor = SIMD4<Double>(0, 0, 0, 1)
    /// Asked every frame while the display link runs; return false to stop it.
    var animationStep: ((CFTimeInterval) -> Bool)?
    /// Called with a frame's number and the time it actually reached the screen (benchmarks).
    var onPresented: (@MainActor @Sendable (Int, CFTimeInterval) -> Void)?
    /// Number of the frame being (or last) rendered; the scene provider can read it.
    private(set) var frameNumber = 0

    private var metalLayer: CAMetalLayer { layer as! CAMetalLayer }
    private var renderScheduled = false
    private var animationTimer: Timer?

    /// Transparent views (the transition overlay, the main view on the translucent background) clear to
    /// nothing and let what is behind show through.
    var transparent: Bool {
        didSet {
            guard transparent != oldValue else { return }
            metalLayer.isOpaque = !transparent
            if transparent {
                clearColor = SIMD4(0, 0, 0, 0)
                metalLayer.backgroundColor = NSColor.clear.cgColor
            }
            setNeedsRender()
        }
    }

    init(renderer: Renderer, transparent: Bool = false) {
        self.renderer = renderer
        self.transparent = transparent
        super.init(frame: .zero)
        if transparent { clearColor = SIMD4(0, 0, 0, 0) }
        wantsLayer = true
        layerContentsRedrawPolicy = .duringViewResize
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func makeBackingLayer() -> CALayer {
        let layer = CAMetalLayer()
        layer.device = renderer.device
        layer.pixelFormat = Renderer.pixelFormat
        layer.colorspace = CGColorSpace(name: CGColorSpace.displayP3)
        layer.framebufferOnly = true
        layer.isOpaque = !transparent
        layer.maximumDrawableCount = 3
        layer.backgroundColor = transparent ? NSColor.clear.cgColor : NSColor.black.cgColor
        return layer
    }

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { !transparent }
    override var acceptsFirstResponder: Bool { false }

    var drawableSize: CGSize { metalLayer.drawableSize }
    var backingScale: Double { Double(window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2) }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateDrawableSize()
        // Draw in the same transaction as the resize so the image never appears stretched for a frame.
        renderNow(synchronously: true)
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        metalLayer.contentsScale = backingScale
        updateDrawableSize()
        setNeedsRender()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateDrawableSize()
        setNeedsRender()
    }

    private func updateDrawableSize() {
        let scale = backingScale
        let size = CGSize(width: max(1, (bounds.width * scale).rounded()), height: max(1, (bounds.height * scale).rounded()))
        if metalLayer.drawableSize != size { metalLayer.drawableSize = size }
    }

    func setNeedsRender() {
        guard !renderScheduled else { return }
        renderScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            renderScheduled = false
            renderNow(synchronously: false)
        }
    }

    /// Renders immediately. `synchronously` presents inside the current Core Animation transaction.
    func renderNow(synchronously: Bool) {
        guard window != nil, let provider = sceneProvider, let buffer = renderer.commandQueue.makeCommandBuffer() else { return }
        let size = metalLayer.drawableSize
        guard size.width >= 1, size.height >= 1 else { return }
        metalLayer.presentsWithTransaction = synchronously
        guard let drawable = metalLayer.nextDrawable() else { return }
        frameNumber += 1
        let frame = frameNumber
        renderer.encode(provider(size), into: buffer, target: drawable.texture, clear: clearColor)
        if let onPresented {
            drawable.addPresentedHandler { presented in
                // presentedTime is 0 on some systems (seen on macOS 27); the handler itself runs right
                // after presentation, so its own clock is the fallback.
                let time = presented.presentedTime > 0 ? presented.presentedTime : CACurrentMediaTime()
                Task { @MainActor in onPresented(frame, time) }
            }
        }
        if synchronously {
            buffer.commit()
            buffer.waitUntilScheduled()
            drawable.present()
        } else {
            buffer.present(drawable)
            buffer.commit()
        }
    }

    /// Starts driving animation frames; stops by itself when `animationStep` returns false.
    /// A 120 Hz timer is used instead of CADisplayLink: in testing on macOS 27 neither the view's nor the
    /// screen's display link delivered callbacks while the window was hidden or the app was launched from a
    /// terminal. Presentation itself stays vsync-paced by CAMetalLayer.
    func startAnimating() {
        guard animationTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        animationTimer = timer
        tick()
    }

    func stopAnimating() {
        animationTimer?.invalidate()
        animationTimer = nil
    }

    var isAnimating: Bool { animationTimer != nil }

    private func tick() {
        let keepGoing = animationStep?(CACurrentMediaTime()) ?? false
        renderNow(synchronously: false)
        if !keepGoing { stopAnimating() }
    }

    /// Renders the current scene offscreen (script snapshots).
    func snapshotImage() -> CGImage? {
        guard let provider = sceneProvider else { return nil }
        let size = metalLayer.drawableSize
        let pixels = try? renderer.renderOffscreen(provider(size), size: .init(width: Int(size.width), height: Int(size.height)),
                                                   clear: clearColor)
        return pixels?.makeImage()
    }
}
