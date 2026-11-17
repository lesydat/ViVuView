import CoreGraphics
import Foundation
import ImageIO

/// Animated GIF / APNG / WebP / AVIF / HEICS (docs/TECH_SPEC.md §10): frame timing from the file's
/// properties, frames decoded one at a time on demand (never the whole animation in RAM).
public enum AnimatedDecoder {
    /// Browsers treat delays of 10 ms or less as 100 ms; so do we.
    public static let minimumDelay = 0.011
    public static let fallbackDelay = 0.1

    /// Delay of every frame, seconds.
    public static func durations(_ url: URL) throws -> [Double] {
        let source = try ImageIODecoder.source(url)
        let count = CGImageSourceGetCount(source)
        return (0..<count).map { i in
            let props = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [CFString: Any] ?? [:]
            return delay(in: props) ?? fallbackDelay
        }
    }

    /// Finds "UnclampedDelayTime" or "DelayTime" in whichever format dictionary the file has
    /// ({GIF}, {PNG}, {WebP}, {HEICS}, {AVIS} …).
    static func delay(in props: [CFString: Any]) -> Double? {
        for value in props.values {
            guard let dict = value as? [String: Any] else { continue }
            let raw = (dict["UnclampedDelayTime"] as? NSNumber)?.doubleValue ?? (dict["DelayTime"] as? NSNumber)?.doubleValue
            if let raw { return raw < minimumDelay ? fallbackDelay : raw }
        }
        return nil
    }

    /// Frame `index` fitted to `maxPixel` (oriented, Display P3).
    public static func frame(_ url: URL, index: Int, maxPixel: Int) throws -> PixelBuffer {
        let source = try ImageIODecoder.source(url)
        guard index < CGImageSourceGetCount(source) else { throw DecodeError.corrupt("khung không tồn tại") }
        return try ImageIODecoder.viaThumbnailAPI(source: source, index: index, maxPixel: maxPixel, fromImage: true)
    }
}
