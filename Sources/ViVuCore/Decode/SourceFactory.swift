import Foundation

/// A huge file read from disk at fine levels and from a RAM copy at coarse ones (docs/TECH_SPEC.md §4.4:
/// "level trung gian trên RAM"). The RAM copy is made in the same pass that produces the fit picture.
public final class HybridSource: RegionSource {
    public let base: RegionSource
    public let memory: RAMPyramidSource
    public var meta: ImageMeta { base.meta }
    public var maxLevel: Int { max(base.maxLevel, memory.maxLevel) }

    public init(base: RegionSource, memory: RAMPyramidSource) {
        self.base = base
        self.memory = memory
    }

    public func read(rect: PixelRect, outSize: PixelSize) throws -> PixelBuffer {
        let shrink = Double(rect.width) / Double(max(1, outSize.width))
        if shrink >= Double(memory.baseFactor) * 0.999 { return try memory.read(rect: rect, outSize: outSize) }
        return try base.read(rect: rect, outSize: outSize)
    }
}

/// Picks the reader for a file (docs/TECH_SPEC.md §4.1): own readers for huge TIFF and PSD/PSB (tier L-A),
/// ImageIO for everything else and whenever an own reader declines or fails.
public enum SourceFactory {
    static let tiffExtensions: Set<String> = ["tif", "tiff"]
    static let photoshopExtensions: Set<String> = ["psd", "psb"]

    /// Opens an own reader if the file is one it handles and is large enough to need it; nil otherwise.
    public static func openOwnReader(_ url: URL, minimumMegapixels: Double = Tuning.singleTextureMegapixels) -> RegionSource? {
        let ext = url.pathExtension.lowercased()
        let source: RegionSource?
        if tiffExtensions.contains(ext) {
            source = try? TIFFRegionSource(url: url)
        } else if photoshopExtensions.contains(ext) {
            source = try? PSBRegionSource(url: url)
        } else {
            source = nil
        }
        guard let source, source.fullSize.megapixels > minimumMegapixels else { return nil }
        return source
    }

    /// Stage 1 for any file. For huge TIFF/PSB also returns the region source to keep for zooming.
    public static func screenDecode(_ url: URL, screenLongSide: Int, preferEmbedded: Bool,
                                    isCancelled: @Sendable () -> Bool = { false }) throws -> (PixelBuffer, ImageMeta, RegionSource?) {
        if let base = openOwnReader(url) {
            do {
                let (fit, source) = try prepareHuge(base, fitLongSide: screenLongSide, isCancelled: isCancelled)
                return (fit, base.meta, source)
            } catch DecodeError.cancelled {
                throw DecodeError.cancelled
            } catch {
                // A reader bug costs speed, never the picture: fall through to ImageIO.
            }
        }
        let (pixels, meta) = try ImageIODecoder.screenDecode(url, screenLongSide: screenLongSide, preferEmbedded: preferEmbedded)
        return (pixels, meta, nil)
    }

    /// The fit picture and the source to zoom with. With usable overviews the fit is read from them; otherwise
    /// one pass over the whole file builds a RAM level (≤ 64 MP) and the fit comes from that.
    public static func prepareHuge(_ base: RegionSource, fitLongSide: Int,
                                   isCancelled: @Sendable () -> Bool = { false }) throws -> (PixelBuffer, RegionSource) {
        let full = base.fullSize
        if let tiff = base as? TIFFRegionSource, let coarsest = tiff.levels.last,
           coarsest.downscale >= Double(full.longSide) / Double(max(fitLongSide, 1)) / 2 {
            return (try base.fit(longSide: fitLongSide), base)
        }
        var factor = 1
        while Double(full.area) / Double(factor * factor) / 1_000_000 > Tuning.singleTextureMegapixels { factor *= 2 }
        let memorySize = PixelSize(width: max(1, full.width / factor), height: max(1, full.height / factor))
        let pixels = try base.read(rect: PixelRect(size: full), outSize: memorySize)
        if isCancelled() { throw DecodeError.cancelled }
        let memory = try RAMPyramidSource(pixels: pixels, meta: base.meta, baseFactor: factor)
        let source = HybridSource(base: base, memory: memory)
        return (try memory.fit(longSide: fitLongSide), source)
    }

    /// Thumbnail-size picture of a huge file through its own reader, or nil to use ImageIO.
    public static func ownThumbnail(_ url: URL, longSide: Int) -> PixelBuffer? {
        guard let base = openOwnReader(url) else { return nil }
        return try? base.fit(longSide: longSide)
    }
}
