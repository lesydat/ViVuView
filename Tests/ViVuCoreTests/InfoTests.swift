import Foundation
import Testing
@testable import ViVuCore

@Suite struct InfoTests {
    @Test func histogramCountsEveryPixel() {
        let pixels = TestFixtures.orientationPattern()
        let h = Histogram.compute(pixels)
        let total = UInt32(pixels.width * pixels.height)
        #expect(h.red.reduce(0, +) == total)
        #expect(h.luma.reduce(0, +) == total)
        // Red block: 100×80 pixels with red 220.
        #expect(h.red[220] == 100 * 80)
        #expect(h.peak > 0)
    }

    @Test func exposureSummaryAndShutter() {
        var info = ImageInfo(url: URL(fileURLWithPath: "/x.jpg"), pixelSize: PixelSize(width: 1, height: 1), fileSize: 0,
                             typeName: "JPEG", uti: "public.jpeg", frameCount: 1)
        #expect(info.exposureSummary == nil)
        info.fNumber = 2.8
        info.exposureTime = 1.0 / 250
        info.iso = 200
        info.focalLength = 35
        #expect(info.exposureSummary == "ƒ/2.8 1/250s ISO 200 35mm")
        #expect(ImageInfo.shutter(2) == "2s")
        info.cameraMake = "Canon"
        info.cameraModel = "Canon EOS R5"
        #expect(info.camera == "Canon EOS R5")
        info.cameraMake = "SONY"
        info.cameraModel = "ILCE-7M4"
        #expect(info.camera == "SONY ILCE-7M4")
    }

    @Test func exifDatesAreLocalTime() throws {
        let date = try #require(ImageInfo.parseEXIFDate("2026:03:14 09:12:30"))
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        #expect(parts.year == 2026 && parts.month == 3 && parts.day == 14 && parts.hour == 9 && parts.minute == 12)
    }

    @Test func associationsClaimAndGiveBack() {
        let ours = "/Applications/ViVuView.app"
        let current: [String: String?] = ["public.jpeg": "/System/Applications/Preview.app",
                                          "public.png": ours, "public.heic": ours, "public.tiff": nil]
        let steps = FileAssociationPlanner.plan(utis: ["public.jpeg", "public.png", "public.heic", "public.tiff"],
                                                current: current, ours: ours,
                                                wanted: ["public.jpeg", "public.png", "public.tiff"],
                                                remembered: ["public.heic": "/Applications/Pixea.app"])
        #expect(steps == [
            .claim(uti: "public.jpeg", previous: "/System/Applications/Preview.app"),
            .release(uti: "public.heic", to: "/Applications/Pixea.app"),
            .claim(uti: "public.tiff", previous: nil),
        ])
        // Nothing remembered: back to Preview.
        let back = FileAssociationPlanner.plan(utis: ["public.png"], current: current, ours: ours, wanted: [], remembered: [:])
        #expect(back == [.release(uti: "public.png", to: FileAssociationPlanner.previewBundlePath)])
    }
}
