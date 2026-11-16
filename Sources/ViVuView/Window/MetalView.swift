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
    /// Called with the time the last frame actually reached the screen (benchmarks).
    var onPresented: (@MainActor @Sendable (CFTimeInterval) -> Void)?

    private var metalLayer: CAMetalLayer { layer as! CAMetalLayer }
    private var renderScheduled = false
    private var displayLink: CADisplayLink?

    init(renderer: Renderer) {
        self.renderer = renderer
        super.init(frame: .zero)
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
        layer.isOpaque = true
        layer.maximumDrawableCount = 3
        layer.backgroundColor = NSColor.black.cgColor
        return layer
    }

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { true }
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
        renderer.encode(provider(size), into: buffer, target: drawable.texture, clear: clearColor)
        if let onPresented {
            drawable.addPresentedHandler { presented in
                let time = presented.presentedTime
                Task { @MainActor in onPresented(time) }
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

    /// Starts the display link; it stops by itself when `animationStep` returns false.
    func startAnimating() {
        guard displayLink == nil else { return }
        let link = displayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stopAnimating() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        let keepGoing = animationStep?(link.targetTimestamp) ?? false
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
