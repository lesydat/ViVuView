import CoreGraphics
import Foundation
import Testing
@testable import ViVuCore

@Suite struct TileTests {
    @Test func levelNeverShrinksTexelsMoreThanTwice() {
        #expect(TilePlanner.level(scale: 1, maxLevel: 6) == 0)
        #expect(TilePlanner.level(scale: 2, maxLevel: 6) == 0)
        #expect(TilePlanner.level(scale: 0.6, maxLevel: 6) == 0)
        #expect(TilePlanner.level(scale: 0.5, maxLevel: 6) == 1)
        #expect(TilePlanner.level(scale: 0.26, maxLevel: 6) == 1)
        #expect(TilePlanner.level(scale: 0.01, maxLevel: 3) == 3)
    }

    @Test func visibleTilesCoverTheViewNearestFirst() {
        let image = PixelSize(width: 10_000, height: 8_000)
        let view = CGSize(width: 1000, height: 600)
        let vp = Viewport(scale: 1, center: CGPoint(x: 5000, y: 4000))
        let visible = TilePlanner.visibleRect(viewport: vp, view: view, imageSize: image)
        #expect(visible.x == 4500 && visible.y == 3700)
        let tiles = TilePlanner.tiles(level: 0, visible: visible, imageSize: image, center: CGPoint(x: 5000, y: 4000))
        // x 4500…5500 → cols 8…10, y 3700…4300 → rows 7…8
        #expect(Set(tiles) == Set((7...8).flatMap { r in (8...10).map { TileKey(level: 0, col: $0, row: r) } }))
        #expect(tiles.first == TileKey(level: 0, col: 9, row: 7))
        let ring = TilePlanner.tiles(level: 0, visible: visible, imageSize: image, ring: 1, center: .zero)
        #expect(ring.count == 5 * 4)
    }

    @Test func rotatedViewportUsesTheBoundingBox() {
        let image = PixelSize(width: 4000, height: 3000)
        let vp = Viewport(scale: 1, center: CGPoint(x: 2000, y: 1500), quarterTurns: 1)
        let visible = TilePlanner.visibleRect(viewport: vp, view: CGSize(width: 1000, height: 600), imageSize: image)
        #expect(visible.width >= 600 && visible.width <= 602)
        #expect(visible.height >= 1000 && visible.height <= 1002)
    }

    @Test func paddedReadsOverlapNeighbours() {
        let image = PixelSize(width: 2000, height: 1000)
        let (read, uv) = TilePlanner.paddedRead(of: TileKey(level: 1, col: 0, row: 0), imageSize: image)
        #expect(read == PixelRect(x: 0, y: 0, width: 1026, height: 1000))
        #expect(uv.minX == 0 && abs(uv.width - 1024.0 / 1026.0) < 1e-9)
    }

    @Test func pyramidReadsMatchDirectScaling() throws {
        let pattern = ImageWriter.pattern(size: PixelSize(width: 3000, height: 2000), seed: 4)
        let meta = ImageMeta(storedSize: pattern.size, uti: "public.jpeg")
        let source = try RAMPyramidSource(pixels: pattern, meta: meta)
        #expect(source.maxLevel >= 2)
        // 100%: exact copy.
        let tile = try source.read(rect: PixelRect(x: 512, y: 512, width: 512, height: 512), level: 0)
        for (x, y) in [(0, 0), (100, 200), (511, 511)] {
            let a = tile.pixel(x: x, y: y), b = pattern.pixel(x: 512 + x, y: 512 + y)
            #expect(a.r == b.r && a.g == b.g && a.b == b.b)
        }
        // Level 2: same size as asked.
        let small = try source.read(rect: PixelRect(x: 0, y: 0, width: 2048, height: 2000), level: 2)
        #expect(small.size == PixelSize(width: 512, height: 500))
    }

    @Test func tiersFollowSizeAndMemory() {
        let gib: UInt64 = 1 << 30
        #expect(ImageTier.classify(PixelSize(width: 8000, height: 6000), maxTextureSide: 16384, physicalMemory: 16 * gib) == .single)
        #expect(ImageTier.classify(PixelSize(width: 20000, height: 10000), maxTextureSide: 16384, physicalMemory: 16 * gib) == .ramPyramid)
        #expect(ImageTier.classify(PixelSize(width: 17000, height: 3000), maxTextureSide: 16384, physicalMemory: 16 * gib) == .ramPyramid)
        #expect(ImageTier.classify(PixelSize(width: 60000, height: 40000), maxTextureSide: 16384, physicalMemory: 16 * gib)
                == .subsampled(factor: 4))
    }
}
