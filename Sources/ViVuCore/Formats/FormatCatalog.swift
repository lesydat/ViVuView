import Foundation

/// The one list of image formats (docs/TECH_SPEC.md §9.1). It feeds the Formats settings tab, the
/// extensions FolderIndex accepts, and CFBundleDocumentTypes in Info.plist (via `vivu-bench doc-types`).
public struct ImageFormat: Hashable, Sendable, Identifiable {
    public enum Group: String, CaseIterable, Sendable {
        case common, raw, special
    }

    public let id: String
    public let name: String
    public let group: Group
    public let utis: [String]
    public let extensions: [String]
}

public enum FormatCatalog {
    public static let all: [ImageFormat] = [
        .init(id: "jpeg", name: "JPEG", group: .common, utis: ["public.jpeg"], extensions: ["jpg", "jpeg", "jpe", "jfif"]),
        .init(id: "png", name: "PNG", group: .common, utis: ["public.png"], extensions: ["png", "apng"]),
        .init(id: "heic", name: "HEIC / HEIF", group: .common, utis: ["public.heic", "public.heif", "public.heics"], extensions: ["heic", "heif", "hif", "heics"]),
        .init(id: "gif", name: "GIF", group: .common, utis: ["com.compuserve.gif"], extensions: ["gif"]),
        .init(id: "webp", name: "WebP", group: .common, utis: ["org.webmproject.webp"], extensions: ["webp"]),
        .init(id: "avif", name: "AVIF", group: .common, utis: ["public.avif"], extensions: ["avif", "avifs"]),
        .init(id: "bmp", name: "BMP", group: .common, utis: ["com.microsoft.bmp"], extensions: ["bmp"]),
        .init(id: "jxl", name: "JPEG XL", group: .common, utis: ["public.jpeg-xl"], extensions: ["jxl"]),
        .init(id: "svg", name: "SVG", group: .common, utis: ["public.svg-image"], extensions: ["svg"]),
        .init(id: "ico", name: "ICO / ICNS", group: .common, utis: ["com.microsoft.ico", "com.apple.icns"], extensions: ["ico", "icns"]),
        .init(id: "canon", name: "Canon", group: .raw, utis: ["com.canon.cr2-raw-image", "com.canon.cr3-raw-image", "com.canon.crw-raw-image"], extensions: ["cr2", "cr3", "crw"]),
        .init(id: "nikon", name: "Nikon", group: .raw, utis: ["com.nikon.raw-image", "com.nikon.nrw-raw-image"], extensions: ["nef", "nrw"]),
        .init(id: "sony", name: "Sony", group: .raw, utis: ["com.sony.arw-raw-image", "com.sony.sr2-raw-image", "com.sony.raw-image"], extensions: ["arw", "sr2", "srf"]),
        .init(id: "fuji", name: "Fujifilm", group: .raw, utis: ["com.fuji.raw-image"], extensions: ["raf"]),
        .init(id: "dng", name: "Adobe DNG", group: .raw, utis: ["com.adobe.raw-image"], extensions: ["dng"]),
        .init(id: "olympus", name: "Olympus / OM", group: .raw, utis: ["com.olympus.or-raw-image", "com.olympus.raw-image"], extensions: ["orf", "ori"]),
        .init(id: "panasonic", name: "Panasonic", group: .raw, utis: ["com.panasonic.rw2-raw-image", "com.panasonic.raw-image"], extensions: ["rw2", "raw"]),
        .init(id: "pentax", name: "Pentax", group: .raw, utis: ["com.pentax.raw-image"], extensions: ["pef"]),
        .init(id: "otherraw", name: String(localized: "RAW khác"), group: .raw, utis: ["public.camera-raw-image"],
              extensions: ["srw", "x3f", "3fr", "mrw", "rwl", "iiq", "erf", "kdc", "dcr", "mos", "mef"]),
        .init(id: "tiff", name: "TIFF / BigTIFF", group: .special, utis: ["public.tiff"], extensions: ["tif", "tiff"]),
        .init(id: "psd", name: "PSD / PSB", group: .special, utis: ["com.adobe.photoshop-image", "com.adobe.photoshop-large-image"], extensions: ["psd", "psb"]),
        .init(id: "exr", name: "OpenEXR", group: .special, utis: ["com.ilm.openexr-image"], extensions: ["exr"]),
        .init(id: "jp2", name: "JPEG 2000", group: .special, utis: ["public.jpeg-2000"], extensions: ["jp2", "j2k", "jpf", "jpx"]),
        .init(id: "tga", name: "TGA", group: .special, utis: ["com.truevision.tga-image"], extensions: ["tga"]),
    ]

    /// Lower-case extensions FolderIndex accepts.
    public static let extensions: Set<String> = Set(all.flatMap(\.extensions))

    public static func isImage(_ url: URL) -> Bool {
        extensions.contains(url.pathExtension.lowercased())
    }

    public static func format(forExtension ext: String) -> ImageFormat? {
        let ext = ext.lowercased()
        return all.first { $0.extensions.contains(ext) }
    }

    /// CFBundleDocumentTypes as plist XML (array), every type as a Viewer with rank Alternate, so the app
    /// is always in "Open With" without claiming any default (docs/TECH_SPEC.md §9.1).
    public static func documentTypesPlistXML() -> String {
        var xml = "<array>\n"
        for format in all {
            xml += """
                <dict>
                    <key>CFBundleTypeName</key><string>\(format.name)</string>
                    <key>CFBundleTypeRole</key><string>Viewer</string>
                    <key>LSHandlerRank</key><string>Alternate</string>
                    <key>LSItemContentTypes</key>
                    <array>\(format.utis.map { "<string>\($0)</string>" }.joined())</array>
                </dict>

            """
        }
        return xml + "</array>"
    }
}
