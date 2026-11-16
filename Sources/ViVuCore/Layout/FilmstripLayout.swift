import CoreGraphics

/// Positions of the thumbnails in the one-row filmstrip (docs/UI_SPEC.md §7). Pure geometry, in points.
public struct FilmstripLayout: Sendable {
    public let thumbHeight: Double
    public let gap: Double
    /// Left edge of each cell in strip coordinates; count = cells + 1 (last = total width + gap).
    public let starts: [Double]

    public static let minAspect = 0.5
    public static let maxAspect = 2.5

    /// `aspects`: width/height of each image, nil when not known yet (drawn square).
    public init(aspects: [Double?], thumbHeight: Double, gap: Double = 4) {
        self.thumbHeight = thumbHeight
        self.gap = gap
        var starts: [Double] = [0]
        starts.reserveCapacity(aspects.count + 1)
        var x = 0.0
        for aspect in aspects {
            x += Self.cellWidth(aspect: aspect, height: thumbHeight) + gap
            starts.append(x)
        }
        self.starts = starts
    }

    public static func cellWidth(aspect: Double?, height: Double) -> Double {
        (min(max(aspect ?? 1, minAspect), maxAspect) * height).rounded()
    }

    public var count: Int { starts.count - 1 }
    public var totalWidth: Double { max(0, (starts.last ?? 0) - gap) }

    public func frame(_ i: Int) -> CGRect {
        CGRect(x: starts[i], y: 0, width: starts[i + 1] - starts[i] - gap, height: thumbHeight)
    }

    /// Strip offset (strip x shown at the view's left edge) that centers cell `i` in a view of `width`,
    /// stopping at the ends so the strip never leaves empty space when it is wider than the view.
    public func offset(centering i: Int, viewWidth: Double) -> Double {
        guard count > 0 else { return 0 }
        guard totalWidth > viewWidth else { return -(viewWidth - totalWidth) / 2 }
        let f = frame(i)
        let ideal = f.midX - viewWidth / 2
        return min(max(ideal, 0), totalWidth - viewWidth)
    }

    public func clampedOffset(_ offset: Double, viewWidth: Double) -> Double {
        guard totalWidth > viewWidth else { return -(viewWidth - totalWidth) / 2 }
        return min(max(offset, 0), totalWidth - viewWidth)
    }

    /// Indices of cells that intersect strip range [from, to).
    public func visible(from: Double, to: Double) -> Range<Int> {
        guard count > 0, to > from else { return 0..<0 }
        let first = max(0, upperBound(from) - 1)
        var last = upperBound(to)
        last = min(last, count)
        return first..<max(first, last)
    }

    /// Index of the cell at strip x, if any.
    public func index(at x: Double) -> Int? {
        let i = upperBound(x) - 1
        guard i >= 0, i < count, frame(i).contains(CGPoint(x: x, y: frame(i).midY)) else { return nil }
        return i
    }

    /// First index whose start is > x.
    private func upperBound(_ x: Double) -> Int {
        var lo = 0, hi = starts.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if starts[mid] <= x { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }
}
