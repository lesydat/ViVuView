import Foundation

/// Exact area-mean downscale driven by the source's own blocks (tiles or strips), for readers that decode
/// in blocks (docs/TECH_SPEC.md §4.4). Bands of block rows run in parallel; each band decodes its blocks one
/// at a time and adds them straight into the output rows it covers, so memory stays at one block per thread
/// plus a few output rows. Output rows that straddle two bands are merged under a lock.
public enum BandedAreaMean {
    /// Delivers decoded pixels of one block as interleaved 8-bit RGB: `pixels` points at the block's top-left
    /// pixel inside `region` coordinates (x0, y0 absolute source coordinates, w×h), with `rowStride` bytes per row.
    public typealias Emit = (_ x0: Int, _ y0: Int, _ w: Int, _ h: Int, _ pixels: UnsafePointer<UInt8>, _ rowStride: Int) -> Void

    /// Decodes every block of band `band` that intersects `region` (absolute source coordinates) and calls `emit`.
    public typealias DecodeBand = @Sendable (_ band: Int, _ emit: Emit) throws -> Void

    public static func downscale(region: PixelRect, outSize requested: PixelSize, bandHeight: Int,
                                 isCancelled: @Sendable () -> Bool = { false }, decodeBand: DecodeBand) throws -> PixelBuffer {
        let outSize = PixelSize(width: min(max(1, requested.width), region.width),
                                height: min(max(1, requested.height), region.height))
        let output = PixelBuffer(width: outSize.width, height: outSize.height)
        let cols = BoxMap(sourceCount: region.width, outCount: outSize.width)
        let rows = BoxMap(sourceCount: region.height, outCount: outSize.height)
        let colMap = cols.inverse()
        let rowMap = rows.inverse()
        let ow = outSize.width
        let firstBand = region.y / bandHeight
        let lastBand = (region.maxY - 1) / bandHeight
        let shared = SharedRows(width: ow)
        let errorBox = ErrorBox()

        DispatchQueue.concurrentPerform(iterations: lastBand - firstBand + 1) { b in
            if errorBox.failed || isCancelled() { return }
            let band = firstBand + b
            let by0 = max(region.y, band * bandHeight), by1 = min(region.maxY, (band + 1) * bandHeight)
            let o0 = Int(rowMap[by0 - region.y]), o1 = Int(rowMap[by1 - 1 - region.y])
            let rowCount = o1 - o0 + 1
            let acc = UnsafeMutablePointer<UInt32>.allocate(capacity: rowCount * ow * 3)
            acc.initialize(repeating: 0, count: rowCount * ow * 3)
            defer { acc.deallocate() }
            do {
                try colMap.withUnsafeBufferPointer { colMapPtr in
                    try rowMap.withUnsafeBufferPointer { rowMapPtr in
                        try decodeBand(band) { x0, y0, w, h, pixels, stride in
                            let cx0 = max(x0, region.x), cx1 = min(x0 + w, region.maxX)
                            let cy0 = max(y0, by0), cy1 = min(y0 + h, by1)
                            guard cx0 < cx1, cy0 < cy1 else { return }
                            for y in cy0..<cy1 {
                                let o = Int(rowMapPtr[y - region.y]) - o0
                                let dst = acc + o * ow * 3
                                let src = pixels + (y - y0) * stride + (cx0 - x0) * 3
                                for i in 0..<(cx1 - cx0) {
                                    let ox = Int(colMapPtr[cx0 - region.x + i]) * 3
                                    dst[ox] &+= UInt32(src[i * 3])
                                    dst[ox + 1] &+= UInt32(src[i * 3 + 1])
                                    dst[ox + 2] &+= UInt32(src[i * 3 + 2])
                                }
                            }
                        }
                    }
                }
            } catch {
                errorBox.set(error)
                return
            }
            for o in o0...o1 {
                let s0 = rows.starts[o] + region.y, s1 = rows.starts[o + 1] + region.y
                let sums = acc + (o - o0) * ow * 3
                if s0 >= by0 && s1 <= by1 {
                    finish(row: o, sums: sums, output: output, cols: cols, boxHeight: s1 - s0)
                } else {
                    // Straddles bands: add this band's share; the last contributor writes the row.
                    let contributed = min(s1, by1) - max(s0, by0)
                    if let total = shared.add(row: o, sums: sums, rows: contributed, needed: s1 - s0) {
                        total.withUnsafeBufferPointer {
                            finish(row: o, sums: UnsafeMutablePointer(mutating: $0.baseAddress!), output: output, cols: cols,
                                   boxHeight: s1 - s0)
                        }
                    }
                }
            }
        }
        if let error = errorBox.error { throw error }
        if isCancelled() { throw DecodeError.cancelled }
        return output
    }

    private static func finish(row o: Int, sums: UnsafeMutablePointer<UInt32>, output: PixelBuffer, cols: BoxMap, boxHeight: Int) {
        let dst = output.data.advanced(by: o * output.bytesPerRow).assumingMemoryBound(to: UInt8.self)
        for ox in 0..<output.width {
            let count = UInt64(cols.starts[ox + 1] - cols.starts[ox]) * UInt64(boxHeight)
            let half = count / 2
            dst[ox * 4] = UInt8((UInt64(sums[ox * 3 + 2]) + half) / count)
            dst[ox * 4 + 1] = UInt8((UInt64(sums[ox * 3 + 1]) + half) / count)
            dst[ox * 4 + 2] = UInt8((UInt64(sums[ox * 3]) + half) / count)
            dst[ox * 4 + 3] = 255
        }
    }
}

/// Output rows shared by two bands.
private final class SharedRows: @unchecked Sendable {
    // Sendable: all state is guarded by `lock`.
    private let lock = NSLock()
    private let width: Int
    private var rows: [Int: (sums: [UInt32], rows: Int)] = [:]

    init(width: Int) { self.width = width }

    /// Adds a partial row; returns the complete sums once all `needed` source rows are in.
    func add(row: Int, sums: UnsafeMutablePointer<UInt32>, rows count: Int, needed: Int) -> [UInt32]? {
        lock.withLock {
            var entry = rows[row] ?? ([UInt32](repeating: 0, count: width * 3), 0)
            for i in 0..<(width * 3) { entry.sums[i] &+= sums[i] }
            entry.rows += count
            if entry.rows >= needed {
                rows[row] = nil
                return entry.sums
            }
            rows[row] = entry
            return nil
        }
    }
}
