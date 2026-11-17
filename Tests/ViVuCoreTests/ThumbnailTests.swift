import Foundation
import Testing
@testable import ViVuCore

@Suite struct ThumbnailTests {
    @Test func lruEvictsLeastRecentlyUsedByCost() {
        var lru = ByteLRU<String, Int>(budget: 100)
        lru.insert(1, for: "a", cost: 40)
        lru.insert(2, for: "b", cost: 40)
        _ = lru.value(for: "a")                     // a is now more recent than b
        let evicted = lru.insert(3, for: "c", cost: 40)
        #expect(evicted == ["b"])
        #expect(lru.contains("a") && lru.contains("c"))
        #expect(lru.totalCost == 80)
        #expect(lru.setBudget(30).count == 2)
        #expect(lru.totalCost == 0)
    }

    @Test func lruKeepsAnItemLargerThanTheBudget() {
        var lru = ByteLRU<String, Int>(budget: 10)
        lru.insert(1, for: "big", cost: 50)
        #expect(lru.contains("big"))
    }

    @Test func thumbnailsStayInRAMAndRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("vivu-thumb-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("big.jpg")
        try ImageWriter.write(ImageWriter.pattern(size: PixelSize(width: 4000, height: 3000), seed: 2), to: url, type: .jpeg)
        let (thumb, pixels) = try ThumbnailStore.make(url)
        #expect(pixels.size.longSide <= ThumbnailStore.longSide)
        #expect(thumb.imageSize == PixelSize(width: 4000, height: 3000))
        #expect(thumb.data.count < 200_000)
        let back = try ThumbnailStore.decode(thumb)
        #expect(back.size == pixels.size)
        let store = ThumbnailStore(budgetBytes: 1 << 20)
        store.put(thumb, for: url)
        #expect(store.get(url)?.size == thumb.size)
        // The store writes nothing next to the image or anywhere else in its folder.
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path) == ["big.jpg"])
    }

    @Test func filmstripCentersTheCurrentCellAndStopsAtEnds() {
        let layout = FilmstripLayout(aspects: Array(repeating: 1.5, count: 100), thumbHeight: 72, gap: 4)
        #expect(layout.frame(0).width == 108)
        #expect(layout.totalWidth == 100 * 112 - 4)
        #expect(layout.offset(centering: 0, viewWidth: 1000) == 0)
        let mid = layout.offset(centering: 50, viewWidth: 1000)
        #expect(abs(layout.frame(50).midX - mid - 500) < 0.001)
        #expect(layout.offset(centering: 99, viewWidth: 1000) == layout.totalWidth - 1000)
        // Short strips are centered in the view.
        let short = FilmstripLayout(aspects: [1, 1], thumbHeight: 72, gap: 4)
        #expect(short.offset(centering: 0, viewWidth: 1000) == -(1000 - 148) / 2)
    }

    @Test func filmstripVisibleRangeAndHitTest() {
        let layout = FilmstripLayout(aspects: [1, nil, 3, 0.2], thumbHeight: 100, gap: 4)
        // Widths: 100, 100 (unknown → square), 250 (clamped), 50 (clamped).
        #expect(layout.frame(2).width == 250)
        #expect(layout.frame(3).width == 50)
        #expect(layout.visible(from: 0, to: 150) == 0..<2)
        #expect(layout.visible(from: 210, to: 220) == 2..<3)
        #expect(layout.index(at: 50) == 0)
        #expect(layout.index(at: 102) == nil)     // in the gap
        #expect(layout.index(at: 300) == 2)
    }
}
