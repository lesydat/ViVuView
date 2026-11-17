import CoreGraphics

/// One display tile: `size`×`size` pixels of level `level` (docs/TECH_SPEC.md §4.3).
public struct TileKey: Hashable, Sendable, CustomStringConvertible {
    public let level: Int
    public let col: Int
    public let row: Int

    public init(level: Int, col: Int, row: Int) {
        self.level = level
        self.col = col
        self.row = row
    }

    public var description: String { "L\(level)/\(col),\(row)" }
}

/// Which tiles to draw and fetch for a viewport. Pure geometry; image space = the region source's space.
public enum TilePlanner {
    public static let tileSize = 512

    /// Level whose pixels are never shrunk more than 2× on screen: floor(log2(1/scale)), clamped.
    public static func level(scale: Double, maxLevel: Int) -> Int {
        guard scale > 0 else { return maxLevel }
        return min(max(Int(floor(log2(1 / scale))), 0), maxLevel)
    }

    /// Level-0 rect covered by a tile (clipped to the image).
    public static func rect(of tile: TileKey, imageSize: PixelSize) -> PixelRect {
        let span = tileSize << tile.level
        return PixelRect(x: tile.col * span, y: tile.row * span, width: span, height: span)
            .intersection(PixelRect(size: imageSize))
    }

    /// Image rect visible in the view (bounding box of the view corners in image space), clipped.
    public static func visibleRect(viewport: Viewport, view: CGSize, imageSize: PixelSize) -> PixelRect {
        let corners = [CGPoint.zero, CGPoint(x: view.width, y: 0), CGPoint(x: 0, y: view.height), CGPoint(x: view.width, y: view.height)]
            .map { viewport.imagePoint($0, view: view) }
        let x0 = corners.map(\.x).min()!, x1 = corners.map(\.x).max()!
        let y0 = corners.map(\.y).min()!, y1 = corners.map(\.y).max()!
        let r = PixelRect(x: Int(x0.rounded(.down)), y: Int(y0.rounded(.down)),
                          width: Int((x1 - x0).rounded(.up)) + 1, height: Int((y1 - y0).rounded(.up)) + 1)
        return r.intersection(PixelRect(size: imageSize))
    }

    /// Tiles at `level` covering `visible` (+ `ring` tiles around it), nearest to `center` first.
    public static func tiles(level: Int, visible: PixelRect, imageSize: PixelSize, ring: Int = 0, center: CGPoint) -> [TileKey] {
        guard !visible.isEmpty else { return [] }
        let span = tileSize << level
        let cols = (imageSize.width + span - 1) / span, rows = (imageSize.height + span - 1) / span
        let c0 = max(0, visible.x / span - ring), c1 = min(cols - 1, (visible.maxX - 1) / span + ring)
        let r0 = max(0, visible.y / span - ring), r1 = min(rows - 1, (visible.maxY - 1) / span + ring)
        guard c0 <= c1, r0 <= r1 else { return [] }
        var keys: [TileKey] = []
        for r in r0...r1 { for c in c0...c1 { keys.append(TileKey(level: level, col: c, row: r)) } }
        func distance(_ k: TileKey) -> Double {
            let x = (Double(k.col) + 0.5) * Double(span) - center.x, y = (Double(k.row) + 0.5) * Double(span) - center.y
            return x * x + y * y
        }
        return keys.sorted { distance($0) < distance($1) }
    }

    /// Level-0 rect to read for a tile, grown by one level pixel on each side so neighbouring tiles share
    /// their edge pixels and linear filtering shows no seams. Returns the read rect and the uv rect (0…1)
    /// of the tile itself inside it.
    public static func paddedRead(of tile: TileKey, imageSize: PixelSize) -> (read: PixelRect, uv: CGRect) {
        let core = rect(of: tile, imageSize: imageSize)
        let pad = 1 << tile.level
        let read = PixelRect(x: core.x - pad, y: core.y - pad, width: core.width + 2 * pad, height: core.height + 2 * pad)
            .intersection(PixelRect(size: imageSize))
        let uv = CGRect(x: Double(core.x - read.x) / Double(read.width), y: Double(core.y - read.y) / Double(read.height),
                        width: Double(core.width) / Double(read.width), height: Double(core.height) / Double(read.height))
        return (read, uv)
    }
}
