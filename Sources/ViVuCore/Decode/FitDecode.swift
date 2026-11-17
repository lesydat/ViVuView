import Accelerate
import CoreGraphics
import Foundation

/// Exact area-mean downscaling of a region, run in parallel bands of output rows on every core
/// (docs/TECH_SPEC.md §4.4). Readers only supply source rows as interleaved 8-bit RGB.
public enum FitDecode {
    /// Fills rows [y0, y1) of the region (absolute source rows) as interleaved RGB, `regionWidth * 3`
    /// bytes per row, into `buffer`. Called concurrently from several threads with distinct buffers.
    public typealias RowFiller = @Sendable (_ y0: Int, _ y1: Int, _ buffer: UnsafeMutablePointer<UInt8>) throws -> Void

    public static func downscale(region: PixelRect, outSize requested: PixelSize, isCancelled: @Sendable () -> Bool = { false },
                                 fillRows: RowFiller) throws -> PixelBuffer {
        let outSize = PixelSize(width: min(max(1, requested.width), region.width),
                                height: min(max(1, requested.height), region.height))
        let output = PixelBuffer(width: outSize.width, height: outSize.height)
        let cols = BoxMap(sourceCount: region.width, outCount: outSize.width)
        let rows = BoxMap(sourceCount: region.height, outCount: outSize.height)
        let colMap = cols.inverse()
        let rw = region.width
        let maxRowsPerOut = (0..<outSize.height).map { rows.starts[$0 + 1] - rows.starts[$0] }.max() ?? 1

        let cores = ProcessInfo.processInfo.activeProcessorCount
        let chunkCount = min(outSize.height, max(1, cores * 4))
        let errorBox = ErrorBox()

        do {
            DispatchQueue.concurrentPerform(iterations: chunkCount) { chunk in
                let o0 = chunk * outSize.height / chunkCount
                let o1 = (chunk + 1) * outSize.height / chunkCount
                guard o0 < o1 else { return }
                let rgb = UnsafeMutablePointer<UInt8>.allocate(capacity: rw * 3 * maxRowsPerOut)
                let acc = UnsafeMutablePointer<UInt64>.allocate(capacity: outSize.width * 3)
                defer { rgb.deallocate(); acc.deallocate() }
                for oy in o0..<o1 {
                    if errorBox.failed || isCancelled() { return }
                    let sy0 = rows.starts[oy], sy1 = rows.starts[oy + 1]
                    do { try fillRows(region.y + sy0, region.y + sy1, rgb) } catch { errorBox.set(error); return }
                    acc.initialize(repeating: 0, count: outSize.width * 3)
                    colMap.withUnsafeBufferPointer { colMapPtr in
                    for r in 0..<(sy1 - sy0) {
                        let row = rgb + r * rw * 3
                        for x in 0..<rw {
                            let o = Int(colMapPtr[x]) * 3
                            acc[o] &+= UInt64(row[x * 3])
                            acc[o + 1] &+= UInt64(row[x * 3 + 1])
                            acc[o + 2] &+= UInt64(row[x * 3 + 2])
                        }
                    }
                    }
                    let dst = output.data.advanced(by: oy * output.bytesPerRow).assumingMemoryBound(to: UInt8.self)
                    let boxH = UInt64(sy1 - sy0)
                    for ox in 0..<outSize.width {
                        let count = UInt64(cols.starts[ox + 1] - cols.starts[ox]) * boxH
                        let half = count / 2
                        dst[ox * 4 + 0] = UInt8((acc[ox * 3 + 2] + half) / count)   // B
                        dst[ox * 4 + 1] = UInt8((acc[ox * 3 + 1] + half) / count)   // G
                        dst[ox * 4 + 2] = UInt8((acc[ox * 3 + 0] + half) / count)   // R
                        dst[ox * 4 + 3] = 255
                    }
                }
            }
        }
        if let error = errorBox.error { throw error }
        if isCancelled() { throw DecodeError.cancelled }
        return output
    }
}

/// Converts pixels from a file's color space to Display P3 in place (vImage spreads it over the cores).
public enum ColorConvert {
    public static func toDisplayP3(_ buffer: PixelBuffer, from source: CGColorSpace?) throws {
        let from = source ?? CGColorSpace(name: CGColorSpace.sRGB)!
        if from.name == CGColorSpace.displayP3 { return }
        guard var srcFormat = vImage_CGImageFormat(bitsPerComponent: 8, bitsPerPixel: 32, colorSpace: from,
                                                   bitmapInfo: CGBitmapInfo(rawValue: PixelBuffer.bitmapInfo)),
              var dstFormat = vImage_CGImageFormat(bitsPerComponent: 8, bitsPerPixel: 32, colorSpace: PixelBuffer.colorSpace,
                                                   bitmapInfo: CGBitmapInfo(rawValue: PixelBuffer.bitmapInfo))
        else { return }
        var error = vImage_Error(kvImageNoError)
        guard let converter = vImageConverter_CreateWithCGImageFormat(&srcFormat, &dstFormat, nil, vImage_Flags(kvImageNoFlags), &error)?
            .takeRetainedValue(), error == kvImageNoError else { return }
        var src = vImage_Buffer(data: buffer.data, height: vImagePixelCount(buffer.height),
                                width: vImagePixelCount(buffer.width), rowBytes: buffer.bytesPerRow)
        var dst = src
        // In-place conversion is supported when source and destination share the pixel layout.
        error = vImageConvert_AnyToAny(converter, &src, &dst, nil, vImage_Flags(kvImageNoFlags))
        if error != kvImageNoError { throw DecodeError.corrupt("chuyển màu thất bại (\(error))") }
    }
}

/// First error wins; read by every worker to stop early.
final class ErrorBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Error?
    var error: Error? { lock.withLock { stored } }
    var failed: Bool { error != nil }
    func set(_ error: Error) { lock.withLock { if stored == nil { stored = error } } }
}
