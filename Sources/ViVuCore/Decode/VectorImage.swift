import CoreGraphics
import Foundation
import os

/// SVG (docs/TECH_SPEC.md §4.5). ImageIO cannot read SVG; AppKit's NSImage can, but ViVuCore does not import
/// AppKit, so the app installs the drawing code here at launch (`SVGRasterizer` in the app target).
/// Without it (vivu-bench, tests) SVG files report `DecodeError.unsupported`.
///
/// A vector has no pixels: `meta` reports the document's own size (CSS pixels, so "100%" is the size the
/// author meant) and every decode draws afresh at the size asked for, so it stays sharp at any zoom.
public enum VectorImage {
    public static let uti = "public.svg-image"
    /// Largest side drawn for one picture (zoomed-in views re-draw up to this).
    public static let maxSide = 8192

    public struct Renderer: Sendable {
        /// The document's size in CSS pixels.
        public var size: @Sendable (URL) throws -> CGSize
        /// Draws the whole document into `size` pixels (Display P3, premultiplied, transparent background).
        public var draw: @Sendable (URL, PixelSize) throws -> PixelBuffer

        public init(size: @escaping @Sendable (URL) throws -> CGSize,
                    draw: @escaping @Sendable (URL, PixelSize) throws -> PixelBuffer) {
            self.size = size
            self.draw = draw
        }
    }

    private static let installed = OSAllocatedUnfairLock<Renderer?>(initialState: nil)

    public static func install(_ renderer: Renderer) { installed.withLock { $0 = renderer } }

    public static func isVector(_ url: URL) -> Bool { url.pathExtension.lowercased() == "svg" }

    private static func renderer() throws -> Renderer {
        guard let renderer = installed.withLock({ $0 }) else { throw DecodeError.unsupported }
        return renderer
    }

    public static func meta(_ url: URL) throws -> ImageMeta {
        // The root element's width/height/viewBox first: parsing the whole document can take very long (a 6 MB
        // diagram took 85 s in NSImage), and sizes are read for every file of a folder.
        let size = try declaredSize(url) ?? renderer().size(url)
        guard size.width > 0, size.height > 0, size.width.isFinite, size.height.isFinite else {
            throw DecodeError.corrupt(String(localized: "SVG không có kích thước"))
        }
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        return ImageMeta(storedSize: PixelSize(width: max(1, Int(size.width.rounded())), height: max(1, Int(size.height.rounded()))),
                         hasAlpha: true, uti: uti, fileSize: Int64(values?.fileSize ?? 0),
                         modificationDate: values?.contentModificationDate)
    }

    /// Files above this size are drawn on the separate large-thumbnail lane.
    public static let largeFileBytes = 1 << 20

    /// Size declared on the root `<svg>` element (width/height, else the viewBox), in the units NSImage uses
    /// (px and pt both 1:1). Nil when absent or relative (%, em): the renderer then parses the document.
    public static func declaredSize(_ url: URL) throws -> CGSize? {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let head = try handle.read(upToCount: 64 << 10) ?? Data()
        return declaredSize(String(decoding: head, as: UTF8.self))
    }

    static func declaredSize(_ text: String) -> CGSize? {
        guard let open = text.range(of: "<svg", options: .caseInsensitive),
              let close = text.range(of: ">", range: open.upperBound..<text.endIndex) else { return nil }
        let tag = String(text[open.upperBound..<close.lowerBound])
        func attribute(_ name: String) -> String? {
            let pattern = "(?:^|\\s)\(name)\\s*=\\s*[\"']([^\"']*)[\"']"
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)),
                  let range = Range(match.range(at: 1), in: tag) else { return nil }
            return String(tag[range])
        }
        func length(_ value: String?) -> Double? {
            guard let value = value?.trimmingCharacters(in: .whitespaces), !value.isEmpty else { return nil }
            let units: [(String, Double)] = [("px", 1), ("pt", 1), ("mm", 72 / 25.4), ("cm", 72 / 2.54), ("in", 72)]
            for (unit, factor) in units where value.hasSuffix(unit) {
                return Double(value.dropLast(unit.count)).map { $0 * factor }
            }
            return Double(value)   // unitless; %, em and the like give nil
        }
        let box = attribute("viewBox")?.split(whereSeparator: { $0 == " " || $0 == "," }).compactMap { Double($0) }
        let boxSize = box?.count == 4 ? CGSize(width: box![2], height: box![3]) : nil
        var width = length(attribute("width")), height = length(attribute("height"))
        if let boxSize, boxSize.width > 0, boxSize.height > 0 {
            if width == nil, let height { width = height * boxSize.width / boxSize.height }
            if height == nil, let width { height = width * boxSize.height / boxSize.width }
        }
        guard let w = width ?? boxSize.map({ Double($0.width) }), let h = height ?? boxSize.map({ Double($0.height) }),
              w > 0, h > 0, w.isFinite, h.isFinite else { return nil }
        return CGSize(width: w, height: h)
    }

    /// Draws the document with its long side `longSide` pixels (smaller or larger than its own size).
    public static func render(_ url: URL, longSide: Int) throws -> (PixelBuffer, ImageMeta) {
        let meta = try meta(url)
        let size = meta.orientedSize
        let scale = Double(min(max(longSide, 1), maxSide)) / Double(size.longSide)
        let target = PixelSize(width: max(1, Int((Double(size.width) * scale).rounded())),
                               height: max(1, Int((Double(size.height) * scale).rounded())))
        return (try renderer().draw(url, target), meta)
    }
}

public extension ImageMeta {
    /// Drawn from vectors: no native resolution, sharp at any size.
    var isVector: Bool { uti == VectorImage.uti }
}
