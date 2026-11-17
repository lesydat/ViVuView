import Foundation
import Testing
@testable import ViVuCore

@Suite struct PSBRegionSourceTests {
    static func tempURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("vivu-tests-\(UUID().uuidString)-\(name)")
    }

    static func write(width: Int, height: Int, large: Bool, compression: PSBWriter.Compression) throws -> URL {
        let url = tempURL(large ? "t.psb" : "t.psd")
        try PSBWriter.write(to: url, width: width, height: height, large: large, compression: compression) { y, rgb in
            FixtureContent.fillRow(y: y, x0: 0, count: width, width: width, height: height, into: rgb)
        }
        return url
    }

    /// Reference area mean computed straight from the generator, in sRGB terms (before color conversion).
    static func referenceMean(x0: Int, y0: Int, w: Int, h: Int, width: Int, height: Int) -> (Double, Double, Double) {
        var sum = (0.0, 0.0, 0.0)
        let row = UnsafeMutablePointer<UInt8>.allocate(capacity: w * 3)
        defer { row.deallocate() }
        for y in y0..<(y0 + h) {
            FixtureContent.fillRow(y: y, x0: x0, count: w, width: width, height: height, into: row)
            for x in 0..<w { sum.0 += Double(row[x * 3]); sum.1 += Double(row[x * 3 + 1]); sum.2 += Double(row[x * 3 + 2]) }
        }
        let n = Double(w * h)
        return (sum.0 / n, sum.1 / n, sum.2 / n)
    }

    @Test func packBitsRoundTrip() throws {
        var bytes = [UInt8](repeating: 7, count: 300)
        for i in stride(from: 0, to: 300, by: 7) { bytes[i] = UInt8(i % 256) }
        var packed: [UInt8] = []
        bytes.withUnsafeBufferPointer { PackBits.pack($0, into: &packed) }
        var out = [UInt8](repeating: 0, count: 300)
        try packed.withUnsafeBufferPointer { p in
            try out.withUnsafeMutableBufferPointer { o in
                try PackBits.unpack(p.baseAddress!, count: p.count, into: o.baseAddress!, width: 300, needed: 300)
            }
        }
        #expect(out == bytes)
    }

    @Test(arguments: [(false, PSBWriter.Compression.rle), (true, .rle), (false, .raw), (true, .raw)])
    func readsFullSizeExactly(large: Bool, compression: PSBWriter.Compression) throws {
        let (w, h) = (257, 131)
        let url = try Self.write(width: w, height: h, large: large, compression: compression)
        defer { try? FileManager.default.removeItem(at: url) }
        let source = try PSBRegionSource(url: url)
        #expect(source.meta.storedSize == PixelSize(width: w, height: h))
        // No ICC → treated as sRGB and converted to P3, so compare against ImageIO-free reference loosely
        // only through the area mean test below; here check geometry and that reading works everywhere.
        let full = try source.read(rect: PixelRect(size: source.fullSize), level: 0)
        #expect(full.size == source.fullSize)
        let corner = try source.read(rect: PixelRect(x: 250, y: 120, width: 100, height: 100), level: 0)
        #expect(corner.size == PixelSize(width: 7, height: 11))
    }

    @Test func areaMeanMatchesReference() throws {
        let (w, h) = (400, 300)
        let url = try Self.write(width: w, height: h, large: true, compression: .rle)
        defer { try? FileManager.default.removeItem(at: url) }
        let source = try PSBRegionSource(url: url)
        // Read in the file's own space: shrink 4× and compare one output pixel with the mean of its 4×4 box.
        let raw = try FitDecode.downscale(region: PixelRect(size: source.fullSize), outSize: PixelSize(width: 100, height: 75)) {
            y0, y1, rgb in try source.fillRows(region: PixelRect(size: source.fullSize), y0: y0, y1: y1, rgb: rgb)
        }
        for (ox, oy) in [(0, 0), (37, 21), (99, 74)] {
            let ref = Self.referenceMean(x0: ox * 4, y0: oy * 4, w: 4, h: 4, width: w, height: h)
            let p = raw.pixel(x: ox, y: oy)
            #expect(abs(Double(p.r) - ref.0) <= 0.5)
            #expect(abs(Double(p.g) - ref.1) <= 0.5)
            #expect(abs(Double(p.b) - ref.2) <= 0.5)
        }
    }

    @Test func truncatedFileThrows() throws {
        let url = try Self.write(width: 300, height: 200, large: true, compression: .rle)
        defer { try? FileManager.default.removeItem(at: url) }
        let data = try Data(contentsOf: url)
        for cut in [10, 40, data.count / 3, data.count - 5] {
            let truncated = Self.tempURL("cut.psb")
            try data.prefix(cut).write(to: truncated)
            defer { try? FileManager.default.removeItem(at: truncated) }
            #expect(throws: (any Error).self) {
                let source = try PSBRegionSource(url: truncated)
                _ = try source.read(rect: PixelRect(size: source.fullSize), level: 0)
            }
        }
    }

    @Test func badRowTableThrows() throws {
        let url = try Self.write(width: 300, height: 200, large: false, compression: .rle)
        defer { try? FileManager.default.removeItem(at: url) }
        var data = try Data(contentsOf: url)
        // First row count lives right after the 26-byte header, 3 zero section lengths and compression.
        let tableStart = 26 + 4 + 4 + 4 + 2
        data[tableStart] = 0xFF; data[tableStart + 1] = 0xFF
        try data.write(to: url)
        #expect(throws: (any Error).self) { _ = try PSBRegionSource(url: url) }
    }

    @Test func declinesUnsupportedFiles() throws {
        let url = Self.tempURL("not.psd")
        try Data("hello world, definitely not a PSD file".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: DecodeError.unsupported) { _ = try PSBRegionSource(url: url) }
    }
}
