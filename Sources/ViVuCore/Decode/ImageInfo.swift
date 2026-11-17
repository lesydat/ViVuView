import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Facts for the status bar and the info panel (docs/TECH_SPEC.md §8), read from file properties only.
public struct ImageInfo: Sendable, Equatable {
    public var url: URL
    public var pixelSize: PixelSize          // oriented
    public var fileSize: Int64
    public var typeName: String
    public var uti: String
    public var dateTaken: Date?
    public var dateModified: Date?
    public var cameraMake: String?
    public var cameraModel: String?
    public var lens: String?
    public var focalLength: Double?
    public var fNumber: Double?
    public var exposureTime: Double?
    public var iso: Int?
    public var exposureBias: Double?
    public var flashFired: Bool?
    public var whiteBalanceAuto: Bool?
    public var latitude: Double?
    public var longitude: Double?
    public var dpi: Double?
    public var bitDepth: Int?
    public var colorModel: String?
    public var profileName: String?
    public var frameCount: Int

    public var megapixels: Double { pixelSize.megapixels }
    public var hasLocation: Bool { latitude != nil && longitude != nil }

    public var camera: String? {
        guard let model = cameraModel else { return cameraMake }
        if let make = cameraMake, !model.lowercased().hasPrefix(make.lowercased().components(separatedBy: " ").first ?? "") {
            return "\(make) \(model)"
        }
        return model
    }

    /// "ƒ/2.8 1/250s ISO 200 35mm", only the parts that exist.
    public var exposureSummary: String? {
        var parts: [String] = []
        if let f = fNumber { parts.append("ƒ/\(Self.trim(f))") }
        if let t = exposureTime { parts.append(Self.shutter(t)) }
        if let iso { parts.append("ISO \(iso)") }
        if let focal = focalLength { parts.append("\(Self.trim(focal))mm") }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    public static func shutter(_ t: Double) -> String {
        t >= 1 ? "\(trim(t))s" : "1/\(Int((1 / t).rounded()))s"
    }

    static func trim(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }

    public static func read(_ url: URL) throws -> ImageInfo {
        if VectorImage.isVector(url) {
            let meta = try VectorImage.meta(url)
            return ImageInfo(url: url, pixelSize: meta.orientedSize, fileSize: meta.fileSize,
                             typeName: UTType(meta.uti)?.localizedDescription ?? "SVG", uti: meta.uti,
                             dateModified: meta.modificationDate, frameCount: 1)
        }
        let source = try ImageIODecoder.source(url)
        let meta = try ImageIODecoder.meta(source: source, url: url)
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        let gps = props[kCGImagePropertyGPSDictionary] as? [CFString: Any] ?? [:]
        let aux = props[kCGImagePropertyExifAuxDictionary] as? [CFString: Any] ?? [:]
        func number(_ dict: [CFString: Any], _ key: CFString) -> Double? { (dict[key] as? NSNumber)?.doubleValue }
        func string(_ dict: [CFString: Any], _ key: CFString) -> String? {
            (dict[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        }
        var info = ImageInfo(url: url, pixelSize: meta.orientedSize, fileSize: meta.fileSize,
                             typeName: UTType(meta.uti)?.localizedDescription ?? meta.uti, uti: meta.uti,
                             dateModified: meta.modificationDate, frameCount: meta.frameCount)
        info.dateTaken = (string(exif, kCGImagePropertyExifDateTimeOriginal) ?? string(tiff, kCGImagePropertyTIFFDateTime))
            .flatMap(Self.parseEXIFDate)
        info.cameraMake = string(tiff, kCGImagePropertyTIFFMake)
        info.cameraModel = string(tiff, kCGImagePropertyTIFFModel)
        info.lens = string(exif, kCGImagePropertyExifLensModel) ?? string(aux, kCGImagePropertyExifAuxLensModel)
        info.focalLength = number(exif, kCGImagePropertyExifFocalLength)
        info.fNumber = number(exif, kCGImagePropertyExifFNumber)
        info.exposureTime = number(exif, kCGImagePropertyExifExposureTime)
        info.iso = (exif[kCGImagePropertyExifISOSpeedRatings] as? [NSNumber])?.first?.intValue
        info.exposureBias = number(exif, kCGImagePropertyExifExposureBiasValue)
        if let flash = (exif[kCGImagePropertyExifFlash] as? NSNumber)?.intValue { info.flashFired = flash & 1 == 1 }
        if let wb = (exif[kCGImagePropertyExifWhiteBalance] as? NSNumber)?.intValue { info.whiteBalanceAuto = wb == 0 }
        if let lat = number(gps, kCGImagePropertyGPSLatitude), let lon = number(gps, kCGImagePropertyGPSLongitude) {
            info.latitude = (gps[kCGImagePropertyGPSLatitudeRef] as? String) == "S" ? -lat : lat
            info.longitude = (gps[kCGImagePropertyGPSLongitudeRef] as? String) == "W" ? -lon : lon
        }
        info.dpi = number(props, kCGImagePropertyDPIWidth)
        info.bitDepth = (props[kCGImagePropertyDepth] as? NSNumber)?.intValue
        info.colorModel = props[kCGImagePropertyColorModel] as? String
        info.profileName = props[kCGImagePropertyProfileName] as? String
        return info
    }

    /// EXIF dates look like "2026:03:14 09:12:30" and carry no time zone: read them as local time.
    static func parseEXIFDate(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.date(from: String(text.prefix(19)))
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

public enum Format {
    public static func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }

    public static func percent(_ value: Double) -> String {
        value >= 10 ? "\(Int(value.rounded()))%" : String(format: "%.1f%%", value)
    }
}
