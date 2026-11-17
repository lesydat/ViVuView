import CoreGraphics
import Testing
@testable import ViVuCore

@Suite struct ViewportTests {
    let image = PixelSize(width: 4000, height: 3000)
    let view = CGSize(width: 2000, height: 1000)

    func near(_ a: CGPoint, _ b: CGPoint, _ eps: Double = 1e-6) -> Bool {
        abs(a.x - b.x) < eps && abs(a.y - b.y) < eps
    }

    @Test func fitUsesTheTighterAxis() {
        #expect(Viewport.fitScale(image: image, view: view, quarterTurns: 0) == 1000.0 / 3000.0)
        #expect(Viewport.fitScale(image: image, view: view, quarterTurns: 1) == 1000.0 / 4000.0)
    }

    @Test(arguments: 0...3)
    func viewAndImagePointsRoundTrip(turns: Int) {
        let vp = Viewport(scale: 0.7, center: CGPoint(x: 1234, y: 987), quarterTurns: turns)
        let p = CGPoint(x: 321, y: 2345)
        #expect(near(vp.imagePoint(vp.viewPoint(p, view: view), view: view), p))
        #expect(near(vp.viewPoint(vp.center, view: view), CGPoint(x: 1000, y: 500)))
    }

    @Test(arguments: 0...3)
    func zoomKeepsTheAnchorStill(turns: Int) {
        let vp = Viewport.fit(image: image, view: view, quarterTurns: turns)
        let anchor = CGPoint(x: 1500, y: 300)
        let under = vp.imagePoint(anchor, view: view)
        let zoomed = vp.zoomed(to: vp.scale * 3.7, anchor: anchor, view: view)
        #expect(near(zoomed.viewPoint(under, view: view), anchor))
        #expect(!zoomed.isFit)
    }

    @Test func rotationIsClockwise() {
        // Image top-left corner, after one clockwise quarter turn, sits at the top-right of the shown picture.
        let vp = Viewport.fit(image: image, view: CGSize(width: 3000, height: 4000), quarterTurns: 1)
        #expect(near(vp.viewPoint(.zero, view: CGSize(width: 3000, height: 4000)), CGPoint(x: 3000, y: 0)))
    }

    @Test func panMovesWithTheFingers() {
        let vp = Viewport(scale: 2, center: CGPoint(x: 2000, y: 1500))
        let moved = vp.panned(by: CGVector(dx: 100, dy: -50))
        #expect(near(moved.center, CGPoint(x: 1950, y: 1525)))
    }

    @Test func clampCentersSmallAxesAndStopsAtEdges() {
        // Zoomed so width overflows (4000*1 > 2000) but height fits (3000*0.3 < 1000).
        var vp = Viewport(scale: 1, center: CGPoint(x: -500, y: 10))
        vp = vp.clamped(image: image, view: view)
        #expect(vp.center.x == 1000)          // left edge stays at the view's left edge
        vp = Viewport(scale: 0.3, center: CGPoint(x: 100, y: 10)).clamped(image: image, view: view)
        #expect(vp.center.y == 1500)          // height smaller than the view: centered
        #expect(vp.center.x == 2000)          // width 1200 < 2000: centered too
    }

    @Test func renderUnits() {
        #expect(RenderUnit.point.unitScale(backingScale: 2) == 2)
        #expect(RenderUnit.pixel.unitScale(backingScale: 2) == 1)
    }

    @Test func windowSizingKeepsSmallImagesAt100AndFitsLargeOnes() {
        let available = CGSize(width: 1500, height: 900)
        let minimum = CGSize(width: 320, height: 240)
        #expect(WindowSizing.contentSize(image: CGSize(width: 800, height: 600), pointsPerPixel: 1, available: available, minimum: minimum)
                == CGSize(width: 800, height: 600))
        #expect(WindowSizing.contentSize(image: CGSize(width: 800, height: 600), pointsPerPixel: 0.5, available: available, minimum: minimum)
                == CGSize(width: 400, height: 300))
        #expect(WindowSizing.contentSize(image: CGSize(width: 6000, height: 4000), pointsPerPixel: 1, available: available, minimum: minimum)
                == CGSize(width: 1350, height: 900))
        #expect(WindowSizing.contentSize(image: CGSize(width: 100, height: 50), pointsPerPixel: 1, available: available, minimum: minimum)
                == CGSize(width: 320, height: 240))
        // Zoomed: grows with the zoom until it hits the available area.
        #expect(WindowSizing.contentSize(image: CGSize(width: 800, height: 600), pointsPerPixel: 1, available: available,
                                         minimum: minimum, zoom: 2) == CGSize(width: 1500, height: 900))
    }

    @Test func windowFrameStaysOnScreen() {
        let frame = WindowSizing.frame(size: CGSize(width: 800, height: 600), center: CGPoint(x: 1450, y: 50),
                                       available: CGRect(x: 0, y: 0, width: 1500, height: 900))
        #expect(frame.maxX == 1500)
        #expect(frame.minY == 0)
    }

    @Test func zoomStepsStopAtFitAnd100() {
        // fit 0.5, 100% = 2 (Point mode on Retina)
        #expect(ZoomSteps.step(from: 0.45, factor: 1.25, zoomIn: true, fitScale: 0.5, unitScale: 2) == 0.5)
        #expect(ZoomSteps.step(from: 1.8, factor: 1.25, zoomIn: true, fitScale: 0.5, unitScale: 2) == 2)
        #expect(ZoomSteps.step(from: 2.2, factor: 1.25, zoomIn: false, fitScale: 0.5, unitScale: 2) == 2)
        #expect(ZoomSteps.step(from: 2, factor: 1.25, zoomIn: true, fitScale: 0.5, unitScale: 2) == 2.5)
        #expect(ZoomSteps.step(from: 64, factor: 1.25, zoomIn: true, fitScale: 0.5, unitScale: 2) == 64)
    }
}
