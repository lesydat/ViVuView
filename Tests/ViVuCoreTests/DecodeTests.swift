import Foundation
import Testing
import UniformTypeIdentifiers
@testable import ViVuCore

@Suite struct DecodeTests {
    static let dir: URL = {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("vivu-decode-tests")
        try? TestFixtures.write(to: dir)
        return dir
    }()

    static func close(_ a: (r: UInt8, g: UInt8, b: UInt8, a: UInt8), _ b: (r: UInt8, g: UInt8, b: UInt8, a: UInt8)) -> Bool {
        abs(Int(a.r) - Int(b.r)) <= 14 && abs(Int(a.g) - Int(b.g)) <= 14 && abs(Int(a.b) - Int(b.b)) <= 14
    }

    /// Our full-decode path rotates with vImage; ImageIO's thumbnail path applies the transform itself.
    /// Both must agree for every EXIF orientation.
    @Test(arguments: 1...8)
    func orientationMatchesImageIO(orientation: Int) throws {
        let url = Self.dir.appendingPathComponent("orientation-\(orientation).jpg")
        let ours = try ImageIODecoder.fullDecode(url)
        let source = try ImageIODecoder.source(url)
        let reference = try ImageIODecoder.viaThumbnailAPI(source: source, index: 0, maxPixel: 300, fromImage: true)
        #expect(ours.size == reference.size)
        let meta = try ImageIODecoder.meta(url)
        #expect(meta.orientedSize == ours.size)
        for (fx, fy) in [(0.1, 0.1), (0.9, 0.1), (0.1, 0.9), (0.9, 0.9), (0.5, 0.5), (0.2, 0.7)] {
            let x = Int(fx * Double(ours.width)), y = Int(fy * Double(ours.height))
            #expect(Self.close(ours.pixel(x: x, y: y), reference.pixel(x: x, y: y)), "orientation \(orientation) at \(x),\(y)")
        }
    }

    @Test func screenDecodeKeepsJPEGHalvingSteps() {
        #expect(ImageIODecoder.decodeSize(longSide: 4000, target: 3024, uti: UTType.jpeg.identifier) == 4000)
        #expect(ImageIODecoder.decodeSize(longSide: 8000, target: 3024, uti: UTType.jpeg.identifier) == 4000)
        #expect(ImageIODecoder.decodeSize(longSide: 17320, target: 3024, uti: UTType.jpeg.identifier) == 4330)
        #expect(ImageIODecoder.decodeSize(longSide: 30000, target: 3024, uti: UTType.jpeg.identifier) == 3750)
        #expect(ImageIODecoder.decodeSize(longSide: 8000, target: 3024, uti: UTType.heic.identifier) == 3024)
        #expect(ImageIODecoder.decodeSize(longSide: 2000, target: 3024, uti: UTType.jpeg.identifier) == 2000)
    }

    @Test func notAnImageFails() {
        #expect(throws: (any Error).self) {
            _ = try ImageIODecoder.screenDecode(Self.dir.appendingPathComponent("not-an-image.jpg"), screenLongSide: 1000)
        }
    }

    @Test func formatCatalogKnowsCommonExtensions() {
        for ext in ["jpg", "JPEG", "heic", "png", "cr3", "nef", "dng", "tif", "psb", "webp"] {
            #expect(FormatCatalog.isImage(URL(fileURLWithPath: "/x/a.\(ext)")), "\(ext)")
        }
        #expect(!FormatCatalog.isImage(URL(fileURLWithPath: "/x/a.txt")))
        #expect(FormatCatalog.documentTypesPlistXML().contains("public.jpeg"))
    }
}
