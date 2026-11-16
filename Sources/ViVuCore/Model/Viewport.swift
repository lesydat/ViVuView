import CoreGraphics
import Foundation

/// How one image sits in a view (docs/TECH_SPEC.md §2). All view numbers are device pixels,
/// origin top-left; image numbers are oriented-space pixels.
public struct Viewport: Equatable, Sendable {
    /// Device pixels per image pixel.
    public var scale: Double
    /// Image point shown at the view center.
    public var center: CGPoint
    /// User rotation, clockwise quarter turns 0...3.
    public var quarterTurns: Int
    /// While true the image follows the view size (fit); any zoom or pan clears it.
    public var isFit: Bool

    public init(scale: Double, center: CGPoint, quarterTurns: Int = 0, isFit: Bool = false) {
        self.scale = scale
        self.center = center
        self.quarterTurns = ((quarterTurns % 4) + 4) % 4
        self.isFit = isFit
    }

    /// Image size after the user rotation.
    public static func rotatedSize(_ image: PixelSize, quarterTurns: Int) -> CGSize {
        quarterTurns % 2 == 0 ? image.cgSize : image.transposed.cgSize
    }

    public static func fitScale(image: PixelSize, view: CGSize, quarterTurns: Int) -> Double {
        let size = rotatedSize(image, quarterTurns: quarterTurns)
        guard size.width > 0, size.height > 0, view.width > 0, view.height > 0 else { return 1 }
        return min(view.width / size.width, view.height / size.height)
    }

    public static func fit(image: PixelSize, view: CGSize, quarterTurns: Int = 0) -> Viewport {
        Viewport(scale: fitScale(image: image, view: view, quarterTurns: quarterTurns),
                 center: CGPoint(x: Double(image.width) / 2, y: Double(image.height) / 2),
                 quarterTurns: quarterTurns, isFit: true)
    }

    var angle: Double { Double(quarterTurns) * .pi / 2 }

    /// Image point → view point.
    public func viewPoint(_ p: CGPoint, view: CGSize) -> CGPoint {
        let d = rotate(CGPoint(x: (p.x - center.x) * scale, y: (p.y - center.y) * scale), by: angle)
        return CGPoint(x: view.width / 2 + d.x, y: view.height / 2 + d.y)
    }

    /// View point → image point.
    public func imagePoint(_ v: CGPoint, view: CGSize) -> CGPoint {
        let d = rotate(CGPoint(x: v.x - view.width / 2, y: v.y - view.height / 2), by: -angle)
        return CGPoint(x: center.x + d.x / scale, y: center.y + d.y / scale)
    }

    /// Zooms to `newScale` keeping the image point under `anchor` (view point) where it is.
    public func zoomed(to newScale: Double, anchor: CGPoint, view: CGSize) -> Viewport {
        let fixed = imagePoint(anchor, view: view)
        var result = self
        result.scale = newScale
        result.isFit = false
        let d = rotate(CGPoint(x: anchor.x - view.width / 2, y: anchor.y - view.height / 2), by: -angle)
        result.center = CGPoint(x: fixed.x - d.x / newScale, y: fixed.y - d.y / newScale)
        return result
    }

    /// Moves the image by a view-space delta (drag).
    public func panned(by delta: CGVector) -> Viewport {
        var result = self
        let d = rotate(CGPoint(x: delta.dx, y: delta.dy), by: -angle)
        result.center = CGPoint(x: center.x - d.x / scale, y: center.y - d.y / scale)
        result.isFit = false
        return result
    }

    /// Keeps the image from leaving the view: an axis smaller than the view is centered, a larger one
    /// cannot show empty space beyond its edges.
    public func clamped(image: PixelSize, view: CGSize) -> Viewport {
        var result = self
        let shown = Self.rotatedSize(image, quarterTurns: quarterTurns)
        // Work in rotated image axes.
        var c = rotate(CGPoint(x: center.x - Double(image.width) / 2, y: center.y - Double(image.height) / 2), by: angle)
        let halfW = shown.width / 2, halfH = shown.height / 2
        let viewHalfW = view.width / 2 / scale, viewHalfH = view.height / 2 / scale
        c.x = halfW <= viewHalfW ? 0 : min(max(c.x, -halfW + viewHalfW), halfW - viewHalfW)
        c.y = halfH <= viewHalfH ? 0 : min(max(c.y, -halfH + viewHalfH), halfH - viewHalfH)
        let back = rotate(c, by: -angle)
        result.center = CGPoint(x: back.x + Double(image.width) / 2, y: back.y + Double(image.height) / 2)
        return result
    }

    private func rotate(_ p: CGPoint, by a: Double) -> CGPoint {
        // Exact for quarter turns, avoiding floating error in cos/sin.
        let turns = Int((a / (.pi / 2)).rounded())
        switch ((turns % 4) + 4) % 4 {
        case 1: return CGPoint(x: -p.y, y: p.x)
        case 2: return CGPoint(x: -p.x, y: -p.y)
        case 3: return CGPoint(x: p.y, y: -p.x)
        default: return p
        }
    }
}

/// 100% in Point mode is one image pixel per point; in Pixel mode one image pixel per device pixel
/// (docs/UI_SPEC.md §3).
public enum RenderUnit: String, Sendable, CaseIterable {
    case point, pixel

    /// Device pixels per image pixel at 100%.
    public func unitScale(backingScale: Double) -> Double {
        self == .point ? backingScale : 1
    }
}

/// Window content size for an image (docs/UI_SPEC.md §2.1).
public enum WindowSizing {
    /// - Parameters:
    ///   - image: image size after rotation, in pixels.
    ///   - pointsPerPixel: points one image pixel takes at 100% (1 in Point mode, 1/backing in Pixel mode).
    ///   - available: the screen area the window may use, in points.
    ///   - minimum: smallest window content size, in points.
    ///   - zoom: optional zoom factor relative to 100% (window grows with zoom until it hits `available`).
    public static func contentSize(image: CGSize, pointsPerPixel: Double, available: CGSize,
                                   minimum: CGSize, zoom: Double? = nil) -> CGSize {
        let natural = CGSize(width: image.width * pointsPerPixel, height: image.height * pointsPerPixel)
        var size: CGSize
        if let zoom {
            size = CGSize(width: natural.width * zoom, height: natural.height * zoom)
            size = CGSize(width: min(size.width, available.width), height: min(size.height, available.height))
        } else if natural.width <= available.width, natural.height <= available.height {
            size = natural
        } else {
            let f = min(available.width / natural.width, available.height / natural.height)
            size = CGSize(width: natural.width * f, height: natural.height * f)
        }
        size.width = max(minimum.width, size.width.rounded())
        size.height = max(minimum.height, size.height.rounded())
        return CGSize(width: min(size.width, max(available.width, minimum.width)),
                      height: min(size.height, max(available.height, minimum.height)))
    }

    /// Places a window of `size` so its center stays at `center`, kept inside `available`.
    public static func frame(size: CGSize, center: CGPoint, available: CGRect) -> CGRect {
        var origin = CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2)
        origin.x = min(max(origin.x, available.minX), max(available.minX, available.maxX - size.width))
        origin.y = min(max(origin.y, available.minY), max(available.minY, available.maxY - size.height))
        return CGRect(origin: CGPoint(x: origin.x.rounded(), y: origin.y.rounded()), size: size)
    }
}
