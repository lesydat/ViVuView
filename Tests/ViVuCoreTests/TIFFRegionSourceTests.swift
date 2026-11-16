import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import ViVuCore

@Suite struct TIFFRegionSourceTests {
    static func temp(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("vivu-tiff-\(UUID().uuidString)-\(name)")
    }

    static func maxDifference(_ a: PixelBuffer, _ b: PixelBuffer, step: Int = 3) -> Int {
        var worst = 0
        for y in stride(from: 0, to: min(a.height, b.height), by: step) {
            for x in stride(from: 0, to: min(a.width, b.width), by: step) {
                let p = a.pixel(x: x, y: y), q = b.pixel(x: x, y: y)
                worst = max(worst, abs(Int(p.r) - Int(q.r)), abs(Int(p.g) - Int(q.g)), abs(Int(p.b) - Int(q.b)))
            }
        }
        return worst
    }

    /// Tiled RGB with two overview IFDs: full-size reads match ImageIO; overviews become levels.
    @Test func tiledWithOverviewsMatchesImageIO() throws {
        let url = Self.temp("tiled.tif")
        defer { try? FileManager.default.removeItem(at: url) }
        let (w, h) = (1300, 900)
        try TIFFWriter.write(to: url, width: w, height: h, tile: 256, bigTIFF: false, overviews: 2) { level, y, lw, rgb in
            FixtureContent.fillRow(y: y << level, x0: 0, count: lw, width: lw, height: h >> level, into: rgb)
        }
        let source = try TIFFRegionSource(url: url)
        #expect(source.meta.storedSize == PixelSize(width: w, height: h))
        #expect(source.levels.count == 3)
        #expect(source.hasOverviews)
        let ours = try source.read(rect: PixelRect(size: source.fullSize), level: 0)
        let reference = try ImageIODecoder.fullDecode(url)
        #expect(ours.size == reference.size)
        #expect(Self.maxDifference(ours, reference) <= 2)
        // A region crossing tile borders.
        let part = try source.read(rect: PixelRect(x: 200, y: 250, width: 400, height: 300), level: 0)
        for (x, y) in [(0, 0), (55, 6), (399, 299), (57, 6)] {
            let p = part.pixel(x: x, y: y), q = reference.pixel(x: 200 + x, y: 250 + y)
            #expect(abs(Int(p.r) - Int(q.r)) <= 2 && abs(Int(p.b) - Int(q.b)) <= 2)
        }
        // A 1/4 read uses the second overview.
        let quarter = try source.read(rect: PixelRect(size: source.fullSize), level: 2)
        #expect(quarter.size == PixelSize(width: 325, height: 225))
    }

    /// LZW-compressed strips written by ImageIO go through libtiff's RGBA path.
    @Test func compressedStripsMatchImageIO() throws {
        let url = Self.temp("lzw.tif")
        defer { try? FileManager.default.removeItem(at: url) }
        let pattern = ImageWriter.pattern(size: PixelSize(width: 700, height: 500), seed: 6)
        guard let image = pattern.makeImage(),
              let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.tiff.identifier as CFString, 1, nil) else {
            Issue.record("cannot write TIFF"); return
        }
        let tiffProps: [CFString: Any] = [kCGImagePropertyTIFFCompression: 5]
        CGImageDestinationAddImage(dest, image, [kCGImagePropertyTIFFDictionary: tiffProps] as CFDictionary)
        #expect(CGImageDestinationFinalize(dest))
        let source = try TIFFRegionSource(url: url)
        let ours = try source.read(rect: PixelRect(size: source.fullSize), level: 0)
        let reference = try ImageIODecoder.fullDecode(url)
        #expect(Self.maxDifference(ours, reference) <= 3)
        // Exact area mean when shrinking: compare one output pixel with its 4×4 box.
        let small = try source.read(rect: PixelRect(size: source.fullSize), outSize: PixelSize(width: 175, height: 125))
        var sum = 0
        for y in 40..<44 { for x in 80..<84 { sum += Int(ours.pixel(x: x, y: y).g) } }
        #expect(abs(Int(small.pixel(x: 20, y: 10).g) - (sum + 8) / 16) <= 2)
    }

    /// 16-bit grayscale is stretched from the 2nd to the 98th percentile.
    @Test func sixteenBitGrayIsStretched() throws {
        let url = Self.temp("gray16.tif")
        defer { try? FileManager.default.removeItem(at: url) }
        // Values 1000…1999 across x: without stretch the picture would be nearly black (1999/65535 ≈ 3%).
        try TIFFWriter.writeGray16(to: url, width: 1000, height: 64) { x, _ in UInt16(1000 + x) }
        let source = try TIFFRegionSource(url: url)
        let range = try #require(source.stretchRange)
        #expect(abs(range.low - 1020) < 15 && abs(range.high - 1980) < 15)
        let image = try source.read(rect: PixelRect(size: source.fullSize), level: 0)
        #expect(image.pixel(x: 5, y: 10).g < 10)
        #expect(image.pixel(x: 500, y: 10).g > 100 && image.pixel(x: 500, y: 10).g < 160)
        #expect(image.pixel(x: 995, y: 10).g > 245)
        source.stretchEnabled = false
        let linear = try source.read(rect: PixelRect(size: source.fullSize), level: 0)
        #expect(linear.pixel(x: 995, y: 10).g < 12)
    }

    @Test func damagedFilesThrowInsteadOfCrashing() throws {
        let url = Self.temp("tiled.tif")
        defer { try? FileManager.default.removeItem(at: url) }
        try TIFFWriter.write(to: url, width: 600, height: 400, tile: 128, bigTIFF: true, overviews: 1) { level, y, lw, rgb in
            FixtureContent.fillRow(y: y, x0: 0, count: lw, width: lw, height: 400, into: rgb)
        }
        let data = try Data(contentsOf: url)
        for cut in [6, 200, data.count / 2] {
            let broken = Self.temp("cut.tif")
            try data.prefix(cut).write(to: broken)
            defer { try? FileManager.default.removeItem(at: broken) }
            // Either it is declined at open, or reading fails; nothing may crash.
            if let source = try? TIFFRegionSource(url: broken) {
                _ = try? source.read(rect: PixelRect(size: source.fullSize), level: 0)
            }
        }
        let notTIFF = Self.temp("text.tif")
        try Data("not a tiff at all".utf8).write(to: notTIFF)
        defer { try? FileManager.default.removeItem(at: notTIFF) }
        #expect(throws: (any Error).self) { _ = try TIFFRegionSource(url: notTIFF) }
    }
}
