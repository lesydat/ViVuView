import AppKit
import Metal
import ViVuCore
import ViVuRender

/// A decoded texture together with the image facts it belongs to. Metal textures are thread-safe,
/// so passing one between threads is fine.
struct DecodedTexture: @unchecked Sendable {
    let texture: MTLTexture
    let meta: ImageMeta
    /// Size of the texture relative to the oriented image (1 = full resolution).
    let coverage: Double
}

/// Owns the main window and everything shown in it (docs/TECH_SPEC.md §5.4, docs/UI_SPEC.md §2).
@MainActor
final class ViewerController: NSObject, NSWindowDelegate {
    let renderer: Renderer
    let scheduler = DecodeScheduler()
    let settings = Settings.shared
    let window: ViewerWindow
    let content: ViewerContentView
    let metalView: MetalView
    let messageView: MessageView

    // Current image
    private(set) var currentURL: URL?
    private(set) var meta: ImageMeta?
    private var texture: DecodedTexture?
    private(set) var viewport = Viewport(scale: 1, center: .zero, isFit: true)
    private var loadTicket: DecodeTicket?
    private var loadWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var isLoading = false
    private(set) var lastError: String?

    init(renderer: Renderer) {
        self.renderer = renderer
        window = ViewerWindow()
        metalView = MetalView(renderer: renderer)
        messageView = MessageView(frame: .zero)
        content = ViewerContentView(frame: NSRect(origin: .zero, size: ViewerWindow.emptySize))
        super.init()
        content.controller = self
        content.addFill(metalView)
        content.addFill(messageView)
        window.contentView = content
        window.delegate = self
        messageView.message = String(localized: "Kéo ảnh vào đây hoặc nhấn ⌘O")
        metalView.sceneProvider = { [weak self] size in self?.scene(viewSize: size) ?? [] }
        withObservationTracking({ _ = settings.renderUnit }, onChange: { [weak self] in
            Task { @MainActor in self?.renderUnitChanged() }
        })
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: Opening

    /// Long side of the largest screen in device pixels: the size stage 1 decodes to.
    var screenLongSide: Int {
        let sides = NSScreen.screens.map { Int(max($0.frame.width, $0.frame.height) * $0.backingScaleFactor) }
        return sides.max() ?? 3024
    }

    func open(_ url: URL) {
        loadTicket?.cancel()
        isLoading = true
        currentURL = url
        lastError = nil
        window.title = url.lastPathComponent
        window.representedURL = url
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
        let renderer = renderer
        let longSide = screenLongSide
        let preferEmbedded = settings.rawMode == .embeddedPreview
        let signpostID = Signposts.decode.makeSignpostID()
        let state = Signposts.decode.beginInterval("Decode", id: signpostID)
        loadTicket = scheduler.submit(.interactive, priority: .veryHigh, work: { isCancelled in
            let (pixels, meta) = try ImageIODecoder.screenDecode(url, screenLongSide: longSide, preferEmbedded: preferEmbedded)
            if isCancelled() { throw DecodeError.cancelled }
            let texture = try renderer.makeTexture(pixels)
            let coverage = Double(pixels.width) / Double(max(1, meta.orientedSize.width))
            return DecodedTexture(texture: texture, meta: meta, coverage: coverage)
        }, completion: { [weak self] result in
            Signposts.decode.endInterval("Decode", state)
            guard let self, currentURL == url else { return }
            switch result {
            case .success(let decoded): show(decoded)
            case .failure(let error): showError(error, url: url)
            }
            finishLoad()
        })
    }

    private func show(_ decoded: DecodedTexture) {
        texture = decoded
        meta = decoded.meta
        messageView.message = ""
        viewport = Viewport.fit(image: decoded.meta.orientedSize, view: metalView.drawableSize)
        resizeWindowToImage()
        metalView.setNeedsRender()
    }

    private func showError(_ error: Error, url: URL) {
        texture = nil
        meta = nil
        lastError = "\(error)"
        messageView.message = "⚠︎ \(url.lastPathComponent)\n\(error)"
        metalView.setNeedsRender()
    }

    /// Script support: waits until the current load finished (success or error).
    func waitForLoad() async {
        guard isLoading else { return }
        await withCheckedContinuation { loadWaiters.append($0) }
    }

    private func finishLoad() {
        isLoading = false
        let waiters = loadWaiters
        loadWaiters = []
        waiters.forEach { $0.resume() }
    }

    // MARK: Window size

    /// Points one image pixel takes at 100%.
    var pointsPerPixel: Double {
        settings.renderUnit == .point ? 1 : 1 / metalView.backingScale
    }

    func resizeWindowToImage() {
        guard let meta, !window.styleMask.contains(.fullScreen), let screen = window.screen ?? NSScreen.main else { return }
        let available = screen.visibleFrame
        let image = Viewport.rotatedSize(meta.orientedSize, quarterTurns: viewport.quarterTurns)
        let size = WindowSizing.contentSize(image: image, pointsPerPixel: pointsPerPixel, available: available.size,
                                            minimum: ViewerWindow.minimumSize)
        let center = window.isVisible ? CGPoint(x: window.frame.midX, y: window.frame.midY)
                                      : CGPoint(x: available.midX, y: available.midY)
        let frame = WindowSizing.frame(size: size, center: center, available: available)
        if frame != window.frame { window.setFrame(frame, display: true, animate: false) }
        if viewport.isFit {
            viewport = Viewport.fit(image: meta.orientedSize, view: metalView.drawableSize, quarterTurns: viewport.quarterTurns)
        }
    }

    private func renderUnitChanged() {
        resizeWindowToImage()
        metalView.setNeedsRender()
        withObservationTracking({ _ = settings.renderUnit }, onChange: { [weak self] in
            Task { @MainActor in self?.renderUnitChanged() }
        })
    }

    func windowDidResize(_ notification: Notification) {
        if let meta, viewport.isFit {
            viewport = Viewport.fit(image: meta.orientedSize, view: metalView.drawableSize, quarterTurns: viewport.quarterTurns)
        }
        metalView.setNeedsRender()
    }

    // MARK: Scene

    func scene(viewSize: CGSize) -> [Quad] {
        guard let texture, let meta else { return [] }
        var vp = viewport
        if vp.isFit { vp = Viewport.fit(image: meta.orientedSize, view: viewSize, quarterTurns: vp.quarterTurns) }
        let size = CGSize(width: Double(meta.orientedSize.width) * vp.scale, height: Double(meta.orientedSize.height) * vp.scale)
        let center = vp.viewPoint(CGPoint(x: Double(meta.orientedSize.width) / 2, y: Double(meta.orientedSize.height) / 2), view: viewSize)
        let nearest = vp.scale / max(texture.coverage, 0.0001) >= 4
        return [Quad.placed(texture: texture.texture, center: center, size: size,
                            rotation: Double(vp.quarterTurns) * .pi / 2, viewSize: viewSize, nearest: nearest)]
    }

    // MARK: Script support

    func performScriptKey(_ spec: String) throws {
        throw ScriptError.message("unknown key \(spec)")
    }

    func scriptState() -> String {
        let f = window.frame
        return "image=\(currentURL?.lastPathComponent ?? "-") size=\(meta.map { "\($0.orientedSize)" } ?? "-") "
            + "scale=\(String(format: "%.4f", viewport.scale)) fit=\(viewport.isFit) turns=\(viewport.quarterTurns) "
            + "window=\(Int(f.width))x\(Int(f.height)) backing=\(metalView.backingScale) error=\(lastError ?? "-")"
    }

    /// The window content as an image: the Metal scene with the visible overlays drawn on top.
    func snapshot() -> NSBitmapImageRep? {
        let bounds = content.bounds
        guard let rep = content.bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.black.setFill()
        bounds.fill()
        if let scene = metalView.snapshotImage() {
            NSGraphicsContext.current?.cgContext.draw(scene, in: metalView.frame)
        }
        NSGraphicsContext.restoreGraphicsState()
        for overlay in content.subviews where overlay !== metalView && !overlay.isHidden {
            guard let overlayRep = overlay.bitmapImageRepForCachingDisplay(in: overlay.bounds) else { continue }
            overlay.cacheDisplay(in: overlay.bounds, to: overlayRep)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            overlayRep.draw(in: overlay.frame, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            NSGraphicsContext.restoreGraphicsState()
        }
        return rep
    }
}

/// Content view of the main window: hosts the Metal view and overlays, accepts dropped files.
final class ViewerContentView: NSView {
    weak var controller: ViewerController?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func addFill(_ view: NSView) {
        view.frame = bounds
        view.autoresizingMask = [.width, .height]
        addSubview(view)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        imageURL(from: sender) != nil ? .copy : []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let url = imageURL(from: sender) else { return false }
        MainActor.assumeIsolated { controller?.open(url) }
        return true
    }

    private func imageURL(from info: NSDraggingInfo) -> URL? {
        let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                                                       options: [.urlReadingFileURLsOnly: true]) as? [URL]
        return urls?.first { FormatCatalog.isImage($0) } ?? urls?.first
    }
}
