import CoreGraphics

/// Size in image pixels.
public struct PixelSize: Hashable, Sendable, CustomStringConvertible {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    public var area: Int { width * height }
    public var megapixels: Double { Double(area) / 1_000_000 }
    public var longSide: Int { max(width, height) }
    public var transposed: PixelSize { PixelSize(width: height, height: width) }
    public var aspect: Double { height > 0 ? Double(width) / Double(height) : 1 }
    public var cgSize: CGSize { CGSize(width: width, height: height) }
    public var description: String { "\(width)×\(height)" }
}

/// Rectangle in image pixels (origin top-left).
public struct PixelRect: Hashable, Sendable, CustomStringConvertible {
    public var x: Int
    public var y: Int
    public var width: Int
    public var height: Int

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public init(size: PixelSize) {
        self.init(x: 0, y: 0, width: size.width, height: size.height)
    }

    public var maxX: Int { x + width }
    public var maxY: Int { y + height }
    public var size: PixelSize { PixelSize(width: width, height: height) }
    public var isEmpty: Bool { width <= 0 || height <= 0 }

    public func intersection(_ other: PixelRect) -> PixelRect {
        let x0 = max(x, other.x), y0 = max(y, other.y)
        let x1 = min(maxX, other.maxX), y1 = min(maxY, other.maxY)
        return PixelRect(x: x0, y: y0, width: max(0, x1 - x0), height: max(0, y1 - y0))
    }

    public var description: String { "(\(x),\(y) \(width)×\(height))" }
}

/// EXIF orientation 1...8 helpers. Values outside 1...8 are treated as 1.
public enum Orientation {
    /// Orientations 5...8 swap width and height.
    public static func swapsAxes(_ orientation: UInt8) -> Bool { (5...8).contains(orientation) }

    public static func orientedSize(stored: PixelSize, orientation: UInt8) -> PixelSize {
        swapsAxes(orientation) ? stored.transposed : stored
    }
}
