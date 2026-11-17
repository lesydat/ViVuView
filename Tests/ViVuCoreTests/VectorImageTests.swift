import CoreGraphics
import Foundation
import Testing
@testable import ViVuCore

/// SVG through the `VectorImage` hook (the app installs NSImage drawing; here a stand-in renderer).
@Suite struct VectorImageTests {
    static let url: URL = {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("vivu-vector-tests/doc.svg")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data("<svg xmlns='http://www.w3.org/2000/svg' width='300' height='200'/>".utf8).write(to: url)
        VectorImage.install(VectorImage.Renderer(size: { _ in CGSize(width: 300, height: 200) },
                                                 draw: { _, size in PixelBuffer(width: size.width, height: size.height) }))
        return url
    }()

    @Test func metaReportsDocumentSize() throws {
        let meta = try ImageIODecoder.meta(Self.url)
        #expect(meta.orientedSize == PixelSize(width: 300, height: 200))
        #expect(meta.isVector)
        #expect(meta.hasAlpha)
    }

    @Test func drawsAtAnySize() throws {
        let (big, _) = try ImageIODecoder.screenDecode(Self.url, screenLongSide: 3000)
        #expect(big.size == PixelSize(width: 3000, height: 2000))
        let small = try ImageIODecoder.thumbnail(Self.url, maxPixel: 60)
        #expect(small.size == PixelSize(width: 60, height: 40))
        let (capped, _) = try VectorImage.render(Self.url, longSide: 100_000)
        #expect(capped.size.longSide == VectorImage.maxSide)
    }

    @Test func catalogAcceptsSVG() {
        #expect(FormatCatalog.isImage(URL(fileURLWithPath: "/a/b.SVG")))
        #expect(FormatCatalog.format(forExtension: "svg")?.utis == [VectorImage.uti])
    }

    /// Size from the root element without parsing the document (huge diagrams take minutes in NSImage).
    @Test func declaredSizeFromRootElement() {
        #expect(VectorImage.declaredSize("<svg xmlns='x' width='300' height=\"200px\">") == CGSize(width: 300, height: 200))
        #expect(VectorImage.declaredSize("<?xml?><svg width=\"18880pt\" height=\"27088pt\" viewBox=\"0 0 18880 27088\">")
                == CGSize(width: 18880, height: 27088))
        #expect(VectorImage.declaredSize("<svg viewBox='0 0 48 24'>") == CGSize(width: 48, height: 24))
        #expect(VectorImage.declaredSize("<svg width='96' viewBox='0,0,48,24'>") == CGSize(width: 96, height: 48))
        #expect(VectorImage.declaredSize("<svg width='1in' height='2in'>") == CGSize(width: 72, height: 144))
        #expect(VectorImage.declaredSize("<svg stroke-width='3' width='100%' height='100%'>") == nil)
        #expect(VectorImage.declaredSize("<html>") == nil)
    }
}
