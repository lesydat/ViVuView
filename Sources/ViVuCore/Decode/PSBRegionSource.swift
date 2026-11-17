import CoreGraphics
import Foundation
import UniformTypeIdentifiers

/// Own reader for the merged (composite) image of Photoshop PSD/PSB files: 8-bit RGB,
/// raw or RLE (PackBits), orientation 1 (docs/TECH_SPEC.md §4.4). Anything else is declined
/// (`DecodeError.unsupported`) so the caller falls back to ImageIO.
///
/// The composite is stored channel by channel, row by row. With RLE, the per-row byte counts are
/// turned into prefix sums so any row of any channel can be reached with one `pread`.
/// All values read from the file are bounds-checked: a damaged file throws, never crashes.
public final class PSBRegionSource: RegionSource {
    public let meta: ImageMeta
    public let maxLevel: Int
    public let isLargeDocument: Bool       // PSB
    public let compression: Int            // 0 raw, 1 RLE
    public let iccProfile: Data?
    let reader: FileReader
    let channels: Int
    let width: Int
    let height: Int
    let dataStart: Int64
    /// RLE: offset of each (channel, row), count channels*height + 1. Raw: empty.
    let rowOffsets: [Int64]

    public static let maxPSDSide = 30_000
    public static let maxPSBSide = 300_000

    public init(url: URL) throws {
        let reader = try FileReader(url: url)
        self.reader = reader
        var header = ByteCursor(try reader.bytes(at: 0, count: min(26, Int(reader.size))))
        guard header.bytes.count == 26, header.bytes[0..<4].elementsEqual("8BPS".utf8) else { throw DecodeError.unsupported }
        header.position = 4
        let version = try header.u16()
        guard version == 1 || version == 2 else { throw DecodeError.unsupported }
        isLargeDocument = version == 2
        header.position = 12
        channels = try header.u16()
        height = try header.u32()
        width = try header.u32()
        let depth = try header.u16()
        let colorMode = try header.u16()
        let maxSide = isLargeDocument ? Self.maxPSBSide : Self.maxPSDSide
        guard (3...4).contains(channels), depth == 8, colorMode == 3 else { throw DecodeError.unsupported }
        guard (1...maxSide).contains(width), (1...maxSide).contains(height) else { throw DecodeError.corrupt("kích thước vô lý") }

        // Color mode data, image resources, layer and mask info: skip, keeping the ICC profile (resource 1039).
        var offset: Int64 = 26
        let colorModeLength = try Self.length(reader, at: offset, width: 4)
        offset += 4 + colorModeLength
        let resourcesLength = try Self.length(reader, at: offset, width: 4)
        iccProfile = try Self.findICC(reader, start: offset + 4, length: resourcesLength)
        offset += 4 + resourcesLength
        let layerWidth = isLargeDocument ? 8 : 4
        let layerLength = try Self.length(reader, at: offset, width: layerWidth)
        offset += Int64(layerWidth) + layerLength

        var cursor = ByteCursor(try reader.bytes(at: offset, count: 2))
        compression = try cursor.u16()
        offset += 2
        let rowCount = channels * height
        switch compression {
        case 0:
            let needed = Int64(rowCount) * Int64(width)
            guard offset + needed <= reader.size else { throw DecodeError.corrupt("file bị cắt cụt") }
            rowOffsets = []
        case 1:
            let countWidth = isLargeDocument ? 4 : 2
            let table = try reader.bytes(at: offset, count: rowCount * countWidth)
            var offsets = [Int64](repeating: 0, count: rowCount + 1)
            var position = offset + Int64(rowCount * countWidth)
            let maxRowBytes = Int64(width + (width + 127) / 128)   // worst case PackBits size
            try table.withUnsafeBufferPointer { t in
                for i in 0..<rowCount {
                    offsets[i] = position
                    var n: Int64 = 0
                    for b in 0..<countWidth { n = (n << 8) | Int64(t[i * countWidth + b]) }
                    guard n <= maxRowBytes else { throw DecodeError.corrupt("bảng độ dài hàng sai") }
                    position += n
                }
                offsets[rowCount] = position
            }
            guard position <= reader.size else { throw DecodeError.corrupt("file bị cắt cụt") }
            rowOffsets = offsets
        default:
            throw DecodeError.unsupported   // ZIP compressed composites go to ImageIO
        }
        dataStart = offset + (compression == 1 ? Int64(rowCount * (isLargeDocument ? 4 : 2)) : 0)
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        meta = ImageMeta(storedSize: PixelSize(width: width, height: height), orientation: 1, frameCount: 1,
                         hasAlpha: false, uti: UTType("com.adobe.photoshop-image")?.identifier ?? "com.adobe.photoshop-image",
                         fileSize: reader.size, modificationDate: values?.contentModificationDate)
        maxLevel = Self.maxLevel(for: meta.storedSize)
    }

    public var colorSpace: CGColorSpace? {
        iccProfile.flatMap { CGColorSpace(iccData: $0 as CFData) }.flatMap { $0.model == .rgb ? $0 : nil }
    }

    public func read(rect: PixelRect, outSize: PixelSize) throws -> PixelBuffer {
        let region = rect.intersection(PixelRect(size: meta.storedSize))
        guard !region.isEmpty else { throw DecodeError.corrupt("vùng đọc rỗng") }
        let buffer = try FitDecode.downscale(region: region, outSize: outSize) { [self] y0, y1, rgb in
            try fillRows(region: region, y0: y0, y1: y1, rgb: rgb)
        }
        try ColorConvert.toDisplayP3(buffer, from: colorSpace)
        return buffer
    }

    /// Interleaved RGB for rows [y0, y1), columns of `region`.
    func fillRows(region: PixelRect, y0: Int, y1: Int, rgb: UnsafeMutablePointer<UInt8>) throws {
        let rw = region.width
        let rows = y1 - y0
        let plane = UnsafeMutablePointer<UInt8>.allocate(capacity: width)
        defer { plane.deallocate() }
        for c in 0..<3 {
            if compression == 0 {
                // Raw: read just the needed columns of each row.
                for r in 0..<rows {
                    let offset = dataStart + (Int64(c * height + y0 + r) * Int64(width)) + Int64(region.x)
                    try reader.read(at: offset, count: rw, into: plane)
                    interleave(plane, count: rw, channel: c, into: rgb + r * rw * 3)
                }
            } else {
                // RLE: one read for all rows of this channel in the band, then unpack row by row.
                let first = c * height + y0
                let start = rowOffsets[first], end = rowOffsets[first + rows]
                let packed = UnsafeMutablePointer<UInt8>.allocate(capacity: Int(end - start))
                defer { packed.deallocate() }
                try reader.read(at: start, count: Int(end - start), into: packed)
                for r in 0..<rows {
                    let rowStart = Int(rowOffsets[first + r] - start)
                    let rowLength = Int(rowOffsets[first + r + 1] - rowOffsets[first + r])
                    try PackBits.unpack(packed + rowStart, count: rowLength, into: plane, width: width, needed: region.maxX)
                    interleave(plane + region.x, count: rw, channel: c, into: rgb + r * rw * 3)
                }
            }
        }
    }

    private func interleave(_ src: UnsafeMutablePointer<UInt8>, count: Int, channel: Int, into dst: UnsafeMutablePointer<UInt8>) {
        for x in 0..<count { dst[x * 3 + channel] = src[x] }
    }

    private static func length(_ reader: FileReader, at offset: Int64, width: Int) throws -> Int64 {
        var cursor = ByteCursor(try reader.bytes(at: offset, count: width))
        let value = try cursor.uint(width)
        guard value <= UInt64(reader.size) else { throw DecodeError.corrupt("độ dài section vô lý") }
        return Int64(value)
    }

    /// Image resource blocks: "8BIM", id u16, Pascal name (padded to even), size u32, data (padded to even).
    private static func findICC(_ reader: FileReader, start: Int64, length: Int64) throws -> Data? {
        guard length > 0, length < 64 << 20 else { return nil }
        let bytes = try reader.bytes(at: start, count: Int(length))
        var c = ByteCursor(bytes)
        while c.position + 12 <= bytes.count {
            guard bytes[c.position..<c.position + 4].elementsEqual("8BIM".utf8) else { return nil }
            c.position += 4
            let id = try c.u16()
            let nameLength = try c.u8()
            c.position += nameLength + ((nameLength + 1) % 2 == 1 ? 1 : 0)
            let size = try c.u32()
            guard c.position + size <= bytes.count else { return nil }
            if id == 1039 { return Data(bytes[c.position..<c.position + size]) }
            c.position += size + (size % 2)
        }
        return nil
    }
}

/// PackBits (Apple / Photoshop RLE).
public enum PackBits {
    /// Unpacks one row. Stops once `needed` bytes are produced; throws if the data is malformed.
    public static func unpack(_ src: UnsafePointer<UInt8>, count: Int, into dst: UnsafeMutablePointer<UInt8>,
                              width: Int, needed: Int) throws {
        var i = 0, o = 0
        while o < needed {
            guard i < count else { throw DecodeError.corrupt("RLE thiếu dữ liệu") }
            let n = Int(Int8(bitPattern: src[i]))
            i += 1
            if n >= 0 {
                let run = n + 1
                guard i + run <= count, o + run <= width else { throw DecodeError.corrupt("RLE vượt hàng") }
                (dst + o).update(from: src + i, count: run)
                i += run; o += run
            } else if n != -128 {
                let run = 1 - n
                guard i < count, o + run <= width else { throw DecodeError.corrupt("RLE vượt hàng") }
                (dst + o).update(repeating: src[i], count: run)
                i += 1; o += run
            }
        }
    }

    /// Packs one row (used by fixture writers and tests).
    public static func pack(_ row: UnsafeBufferPointer<UInt8>, into out: inout [UInt8]) {
        var i = 0
        let n = row.count
        while i < n {
            var run = 1
            while i + run < n, run < 128, row[i + run] == row[i] { run += 1 }
            if run >= 3 {
                out.append(UInt8(bitPattern: Int8(1 - run)))
                out.append(row[i])
                i += run
            } else {
                var lit = 0
                while i + lit < n, lit < 128 {
                    if i + lit + 2 < n, row[i + lit] == row[i + lit + 1], row[i + lit] == row[i + lit + 2] { break }
                    lit += 1
                }
                out.append(UInt8(lit - 1))
                out.append(contentsOf: row[i..<(i + lit)])
                i += lit
            }
        }
    }
}
