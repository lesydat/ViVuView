import CoreGraphics

/// Gallery layout (docs/UI_SPEC.md §8): equal-width columns, cell height from the image's aspect ratio,
/// each image (in folder order) goes into the currently shortest column (ties → leftmost).
///
/// Stability: only the leading run of images whose size is known is laid out for real; everything after
/// the first unknown size is a 3:2 placeholder. Because a known cell's position depends only on the cells
/// before it, a cell never changes column when more sizes arrive (docs/TECH_SPEC.md §7).
public struct MasonryLayout: Sendable {
    public let columns: Int
    public let columnWidth: Double
    public let gap: Double
    public let margin: Double
    public let top: Double
    public let frames: [CGRect]
    /// Column of each cell.
    public let columnOf: [Int]
    /// Cells per column, top to bottom.
    public let cellsInColumn: [[Int]]
    /// Cells [0, settledCount) have their real size; the rest are placeholders.
    public let settledCount: Int
    public let totalHeight: Double

    public static let minRatio = 0.3
    public static let maxRatio = 3.0
    public static let placeholderAspect = 1.5

    public init(aspects: [Double?], width: Double, targetColumnWidth: Double, gap: Double = 6, margin: Double = 12, top: Double = 0) {
        let usable = max(1, width - 2 * margin)
        let columns = max(1, Int((usable + gap) / (targetColumnWidth + gap)))
        let columnWidth = (usable - Double(columns - 1) * gap) / Double(columns)
        self.columns = columns
        self.columnWidth = columnWidth
        self.gap = gap
        self.margin = margin
        self.top = top
        var heights = [Double](repeating: top + margin, count: columns)
        var frames: [CGRect] = []
        var columnOf: [Int] = []
        var cells = [[Int]](repeating: [], count: columns)
        frames.reserveCapacity(aspects.count)
        columnOf.reserveCapacity(aspects.count)
        let settled = aspects.firstIndex(where: { $0 == nil }) ?? aspects.count
        for (i, aspect) in aspects.enumerated() {
            let a = i < settled ? (aspect ?? Self.placeholderAspect) : Self.placeholderAspect
            let ratio = min(max(1 / max(a, 0.0001), Self.minRatio), Self.maxRatio)   // height / width
            let h = (columnWidth * ratio).rounded()
            var c = 0
            for k in 1..<columns where heights[k] < heights[c] { c = k }
            let x = margin + Double(c) * (columnWidth + gap)
            frames.append(CGRect(x: x, y: heights[c], width: columnWidth, height: h))
            columnOf.append(c)
            cells[c].append(i)
            heights[c] += h + gap
        }
        self.frames = frames
        self.columnOf = columnOf
        self.cellsInColumn = cells
        self.settledCount = settled
        self.totalHeight = (heights.max() ?? top) - gap + margin
    }

    public var count: Int { frames.count }

    /// Cells intersecting the vertical range [y0, y1).
    public func visible(y0: Double, y1: Double) -> [Int] {
        var result: [Int] = []
        for column in cellsInColumn {
            // Binary search the first cell whose bottom is below y0.
            var lo = 0, hi = column.count
            while lo < hi {
                let mid = (lo + hi) / 2
                if frames[column[mid]].maxY <= y0 { lo = mid + 1 } else { hi = mid }
            }
            var k = lo
            while k < column.count, frames[column[k]].minY < y1 {
                result.append(column[k])
                k += 1
            }
        }
        return result.sorted()
    }

    public func index(at point: CGPoint) -> Int? {
        let near = visible(y0: point.y - 1, y1: point.y + 1)
        return near.first { frames[$0].contains(point) }
    }

    /// The cell above / below `i` in the same column, or the nearest one by x in the neighbouring row.
    public func neighbour(of i: Int, up: Bool) -> Int? {
        let column = cellsInColumn[columnOf[i]]
        guard let k = column.firstIndex(of: i) else { return nil }
        let next = up ? k - 1 : k + 1
        return column.indices.contains(next) ? column[next] : nil
    }

    /// Scroll offset that keeps `i` fully visible in a viewport of `height` starting at `scroll`.
    public func scrollToReveal(_ i: Int, scroll: Double, height: Double, topInset: Double = 0) -> Double {
        let f = frames[i]
        var s = scroll
        if f.minY - topInset < s { s = f.minY - topInset - margin }
        if f.maxY > s + height { s = f.maxY - height + margin }
        return clampScroll(s, height: height)
    }

    public func clampScroll(_ s: Double, height: Double) -> Double {
        min(max(s, 0), max(0, totalHeight - height))
    }
}
