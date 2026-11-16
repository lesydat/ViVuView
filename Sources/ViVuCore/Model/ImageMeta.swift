import Foundation

/// Facts read from a file header, without decoding pixels (docs/TECH_SPEC.md §2).
public struct ImageMeta: Hashable, Sendable {
    /// Size as stored in the file.
    public var storedSize: PixelSize
    /// EXIF orientation 1...8.
    public var orientation: UInt8
    /// Size after applying orientation. The UI only uses this one.
    public var orientedSize: PixelSize
    public var frameCount: Int
    public var hasAlpha: Bool
    /// Uniform type identifier reported by ImageIO (or by an own reader).
    public var uti: String
    public var fileSize: Int64
    public var modificationDate: Date?

    public init(storedSize: PixelSize, orientation: UInt8 = 1, frameCount: Int = 1, hasAlpha: Bool = false,
                uti: String, fileSize: Int64 = 0, modificationDate: Date? = nil) {
        self.storedSize = storedSize
        self.orientation = (1...8).contains(orientation) ? orientation : 1
        self.orientedSize = Orientation.orientedSize(stored: storedSize, orientation: self.orientation)
        self.frameCount = frameCount
        self.hasAlpha = hasAlpha
        self.uti = uti
        self.fileSize = fileSize
        self.modificationDate = modificationDate
    }

    public var isAnimated: Bool { frameCount > 1 }
}
