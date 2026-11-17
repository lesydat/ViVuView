import Accelerate
import Foundation

/// RGB and luma histograms of a (small) picture, for the info panel (docs/TECH_SPEC.md §8).
public struct Histogram: Sendable, Equatable {
    public var red: [UInt32]
    public var green: [UInt32]
    public var blue: [UInt32]
    public var luma: [UInt32]

    public static func compute(_ pixels: PixelBuffer) -> Histogram {
        var buffer = pixels.vImage
        var b = [vImagePixelCount](repeating: 0, count: 256)
        var g = b, r = b, a = b
        b.withUnsafeMutableBufferPointer { bp in
            g.withUnsafeMutableBufferPointer { gp in
                r.withUnsafeMutableBufferPointer { rp in
                    a.withUnsafeMutableBufferPointer { ap in
                        // Memory order is B, G, R, A.
                        var channels: [UnsafeMutablePointer<vImagePixelCount>?] = [bp.baseAddress, gp.baseAddress, rp.baseAddress, ap.baseAddress]
                        _ = vImageHistogramCalculation_ARGB8888(&buffer, &channels, vImage_Flags(kvImageNoFlags))
                    }
                }
            }
        }
        var luma = [UInt32](repeating: 0, count: 256)
        for y in 0..<pixels.height {
            let row = pixels.data.advanced(by: y * pixels.bytesPerRow).assumingMemoryBound(to: UInt8.self)
            for x in 0..<pixels.width {
                let l = (Int(row[x * 4 + 2]) * 54 + Int(row[x * 4 + 1]) * 183 + Int(row[x * 4]) * 19) >> 8
                luma[min(l, 255)] += 1
            }
        }
        return Histogram(red: r.map { UInt32($0) }, green: g.map { UInt32($0) }, blue: b.map { UInt32($0) }, luma: luma)
    }

    /// Largest bin over all channels, ignoring the two end bins (clipped shadows and highlights would flatten
    /// everything else).
    public var peak: UInt32 {
        [red, green, blue, luma].map { $0[1..<255].max() ?? 0 }.max() ?? 0
    }
}

/// What to change so the chosen formats open with ViVuView and the others go back to their previous apps
/// (docs/TECH_SPEC.md §9.1). Pure logic; the app performs the steps through NSWorkspace.
public enum FileAssociationPlanner {
    public enum Step: Equatable, Sendable {
        /// Make ViVuView the default for `uti`, remembering `previous` (the app that had it) when known.
        case claim(uti: String, previous: String?)
        /// Give `uti` back to `to` (the remembered app, or Preview).
        case release(uti: String, to: String)
    }

    public static let previewBundlePath = "/System/Applications/Preview.app"

    /// - Parameters:
    ///   - current: default app path per UTI right now (nil when none).
    ///   - ours: ViVuView's app path.
    ///   - wanted: UTIs that should open with ViVuView.
    ///   - remembered: app paths saved when ViVuView claimed a UTI earlier.
    public static func plan(utis: [String], current: [String: String?], ours: String, wanted: Set<String>,
                            remembered: [String: String]) -> [Step] {
        var steps: [Step] = []
        for uti in utis {
            let owner = current[uti] ?? nil
            let isOurs = owner == ours
            if wanted.contains(uti) && !isOurs {
                steps.append(.claim(uti: uti, previous: owner))
            } else if !wanted.contains(uti) && isOurs {
                let back = remembered[uti].flatMap { $0 == ours ? nil : $0 } ?? previewBundlePath
                steps.append(.release(uti: uti, to: back))
            }
        }
        return steps
    }
}
