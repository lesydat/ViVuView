import Foundation
import Testing
@testable import ViVuCore

@Suite struct NavigationTests {
    func entry(_ name: String, size: Int64 = 0, modified: TimeInterval = 0) -> FolderEntry {
        FolderEntry(url: URL(fileURLWithPath: "/tmp/\(name)"), fileSize: size,
                    modified: Date(timeIntervalSince1970: modified), created: Date(timeIntervalSince1970: modified))
    }

    @Test func nameSortIsNaturalLikeFinder() {
        let names = ["IMG_10.jpg", "img_2.jpg", "IMG_1.jpg", "a.png", "IMG_100.jpg"]
        let sorted = FolderIndex.sorted(names.map { entry($0) }, by: .name, ascending: true).map(\.name)
        #expect(sorted == ["a.png", "IMG_1.jpg", "img_2.jpg", "IMG_10.jpg", "IMG_100.jpg"])
        let reversed = FolderIndex.sorted(names.map { entry($0) }, by: .name, ascending: false).map(\.name)
        #expect(reversed.first == "IMG_100.jpg")
    }

    @Test func otherSortsBreakTiesByName() {
        let entries = [entry("b.jpg", size: 5, modified: 2), entry("a.jpg", size: 5, modified: 1), entry("c.jpg", size: 1, modified: 3)]
        #expect(FolderIndex.sorted(entries, by: .size, ascending: true).map(\.name) == ["c.jpg", "a.jpg", "b.jpg"])
        #expect(FolderIndex.sorted(entries, by: .modified, ascending: true).map(\.name) == ["a.jpg", "b.jpg", "c.jpg"])
    }

    @Test func scanKeepsOnlyImages() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("vivu-scan-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        for name in ["2.jpg", "10.JPG", "notes.txt", ".hidden.jpg", "x.heic"] {
            try Data([1]).write(to: dir.appendingPathComponent(name))
        }
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("sub.jpg"), withIntermediateDirectories: true)
        let names = try FolderIndex.scan(dir, sort: .name, ascending: true).map(\.name)
        #expect(names == ["2.jpg", "10.JPG", "x.heic"])
    }

    @Test func preloadOrderFavoursTheBrowsingDirection() {
        let plan = PreloadPlanner.plan(index: 10, count: 100, direction: 1, perSide: 2, wrap: false)
        #expect(plan.screen == [10, 11, 12, 9, 13, 8])
        let back = PreloadPlanner.plan(index: 10, count: 100, direction: -1, perSide: 2, wrap: false)
        #expect(back.screen == [10, 9, 8, 11, 7, 12])
    }

    @Test func preloadRespectsFolderEdges() {
        #expect(PreloadPlanner.plan(index: 0, count: 100, direction: -1, perSide: 2, wrap: false).screen == [0, 1, 2])
        #expect(PreloadPlanner.plan(index: 0, count: 100, direction: -1, perSide: 2, wrap: true).screen == [0, 99, 98, 1, 97, 2])
        #expect(PreloadPlanner.plan(index: 1, count: 3, direction: 1, perSide: 2, wrap: true).screen == [1, 2, 0])
        #expect(PreloadPlanner.plan(index: 0, count: 1, direction: 1, perSide: 2, wrap: true).screen == [0])
        #expect(PreloadPlanner.plan(index: 5, count: 3, direction: 1, perSide: 2, wrap: false).screen.isEmpty)
    }

    @Test func preloadSizeFollowsTheSetting() {
        #expect(PreloadPlanner.plan(index: 50, count: 100, direction: 1, perSide: 1, wrap: false).screen == [50, 51, 52, 49])
        #expect(PreloadPlanner.plan(index: 50, count: 100, direction: 1, perSide: 4, wrap: false).screen.count == 10)
        let thumbs = PreloadPlanner.plan(index: 50, count: 100, direction: 1, perSide: 2, wrap: false, thumbnailRadius: 3).thumbnails
        #expect(thumbs == [50, 51, 49, 52, 48, 53, 47])
    }
}
