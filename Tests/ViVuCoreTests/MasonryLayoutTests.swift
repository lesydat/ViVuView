import CoreGraphics
import Testing
@testable import ViVuCore

@Suite struct MasonryLayoutTests {
    @Test func columnsHaveEqualWidthAndFillTheView() {
        let layout = MasonryLayout(aspects: Array(repeating: 1.5, count: 10), width: 1000, targetColumnWidth: 220)
        // (1000 - 24 + 6) / 226 = 4.34 → 4 columns of (976 - 18) / 4 = 239.5
        #expect(layout.columns == 4)
        #expect(layout.columnWidth == 239.5)
        #expect(Set(layout.frames.map(\.width)) == [239.5])
        #expect(abs(layout.frames[3].maxX - (1000 - 12)) < 0.001)
    }

    @Test func eachImageGoesToTheShortestColumn() {
        // Column width 100 (2 columns in 218 = 12+100+6+100... ), heights: tall, wide, then shortest gets next.
        let layout = MasonryLayout(aspects: [0.5, 2, 2, 2], width: 230, targetColumnWidth: 100, gap: 6, margin: 12)
        #expect(layout.columns == 2)
        #expect(layout.columnOf == [0, 1, 1, 1])   // col 0 is tall (200), col 1 grows 50 + 6 per wide image
        let next = MasonryLayout(aspects: [0.5, 2, 2, 2, 2], width: 230, targetColumnWidth: 100, gap: 6, margin: 12)
        #expect(next.columnOf.last == 1)           // col1 = 3*(50+6)=168 < col0 206
    }

    @Test func heightsFollowAspectWithinLimits() {
        let layout = MasonryLayout(aspects: [1.0, 0.1, 10], width: 1000, targetColumnWidth: 300)
        let w = layout.columnWidth
        #expect(abs(Double(layout.frames[0].height) - w) < 1)
        #expect(abs(Double(layout.frames[1].height) - w * 3) < 1)      // very tall: capped at 3×
        #expect(abs(Double(layout.frames[2].height) - w * 0.3) < 1)    // very wide: at least 0.3×
    }

    @Test func settledCellsNeverMoveWhenMoreSizesArrive() {
        var aspects: [Double?] = [1.5, 0.66, 1.0, nil, 2.0, nil, 0.75, 1.2]
        let before = MasonryLayout(aspects: aspects, width: 900, targetColumnWidth: 200)
        #expect(before.settledCount == 3)
        aspects[3] = 0.5
        aspects[5] = 1.8
        let after = MasonryLayout(aspects: aspects, width: 900, targetColumnWidth: 200)
        #expect(after.settledCount == aspects.count)
        for i in 0..<before.settledCount {
            #expect(before.frames[i] == after.frames[i])
            #expect(before.columnOf[i] == after.columnOf[i])
        }
    }

    @Test func visibleRangeHitTestAndNeighbours() {
        let aspects: [Double?] = (0..<200).map { Double($0 % 5 + 1) / 3 }
        let layout = MasonryLayout(aspects: aspects, width: 1200, targetColumnWidth: 220)
        let shown = layout.visible(y0: 500, y1: 900)
        let brute = layout.frames.indices.filter { layout.frames[$0].maxY > 500 && layout.frames[$0].minY < 900 }
        #expect(shown == brute)
        let f = layout.frames[57]
        #expect(layout.index(at: CGPoint(x: f.midX, y: f.midY)) == 57)
        if let below = layout.neighbour(of: 57, up: false) {
            #expect(layout.columnOf[below] == layout.columnOf[57])
            #expect(layout.frames[below].minY > f.maxY)
        }
        #expect(layout.neighbour(of: layout.cellsInColumn[0][0], up: true) == nil)
    }

    @Test func revealScrollsOnlyWhenNeeded() {
        let layout = MasonryLayout(aspects: Array(repeating: 1.0, count: 100), width: 500, targetColumnWidth: 220)
        #expect(layout.scrollToReveal(0, scroll: 0, height: 600) == 0)
        let far = layout.scrollToReveal(99, scroll: 0, height: 600)
        #expect(far == layout.totalHeight - 600)
        #expect(layout.clampScroll(-50, height: 600) == 0)
    }
}
