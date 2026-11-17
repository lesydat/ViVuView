import Foundation
import Observation
import ViVuCore

/// Every user option (docs/UI_SPEC.md §10). Backed by UserDefaults, the only thing the app writes to disk.
/// Changes take effect immediately: views observe this object.
@MainActor @Observable
final class Settings {
    /// Scripts and benchmarks run with a throwaway defaults domain so they never change the user's settings.
    static let shared: Settings = {
        let automated = CommandLine.arguments.contains { $0 == "--script" || $0.hasPrefix("--bench-") }
        guard automated else { return Settings(defaults: .standard) }
        let suite = "app.vivuview.ViVuView.automation"
        UserDefaults.standard.removePersistentDomain(forName: suite)
        return Settings(defaults: UserDefaults(suiteName: suite) ?? .standard)
    }()

    /// Sets an option by name (scripts): `setting transition fade`.
    func set(_ key: String, _ value: String) throws {
        switch key {
        case "transition": transition = try parse(value)
        case "transitionMilliseconds": transitionMilliseconds = Double(value) ?? transitionMilliseconds
        case "renderUnit": renderUnit = try parse(value)
        case "statusBar": statusBar = try parse(value)
        case "wrapAround": wrapAround = value == "true"
        case "openSize": openSize = try parse(value)
        case "filmstrip": filmstrip = try parse(value)
        case "keepZoom": keepZoom = value == "true"
        case "preloadEachSide": preloadEachSide = Int(value) ?? preloadEachSide
        case "background": background = try parse(value)
        case "clickPinsStatusBar": clickPinsStatusBar = value == "true"
        case "barClearGlass": barClearGlass = value == "true"
        case "barTint": barTint = Double(value) ?? barTint
        case "galleryColumnWidth": galleryColumnWidth = Double(value) ?? galleryColumnWidth
        default: throw ScriptError.message("unknown setting \(key)")
        }
    }

    private func parse<T: RawRepresentable>(_ value: String) throws -> T where T.RawValue == String {
        guard let parsed = T(rawValue: value) else { throw ScriptError.message("bad value \(value)") }
        return parsed
    }

    enum OpenSize: String, CaseIterable { case fitMax100, alwaysFit, always100 }
    enum Background: String, CaseIterable {
        case black, darkGray, gray, lightGray, translucent, checkerboard

        /// Display P3 color behind the picture; the checkerboard sits on black outside transparent images. The
        /// translucent background is black in full screen, where no other window is behind it.
        var rgb: SIMD3<Double> {
            switch self {
            case .black, .checkerboard, .translucent: SIMD3(0, 0, 0)
            case .darkGray: SIMD3(0.11, 0.11, 0.12)
            case .gray: SIMD3(0.32, 0.32, 0.33)
            case .lightGray: SIMD3(0.82, 0.82, 0.83)
            }
        }

        /// Light enough that messages drawn on it need dark text.
        var isLight: Bool { rgb.x > 0.5 }
    }
    enum StatusBarMode: String, CaseIterable { case onHover, always, never }
    enum Transition: String, CaseIterable { case slideFade, fade, none }
    enum FilmstripMode: String, CaseIterable { case autoHide, always }
    enum ThumbSize: String, CaseIterable {
        case small, medium, large
        var height: Double { switch self { case .small: 48; case .medium: 72; case .large: 104 } }
    }
    enum SortKey: String, CaseIterable { case name, modified, captured, size }
    enum RawMode: String, CaseIterable { case embeddedPreview, fullRaw }

    @ObservationIgnored private let defaults: UserDefaults

    // General
    var sortKey: SortKey { didSet { store(sortKey.rawValue, "sortKey") } }
    var sortAscending: Bool { didSet { store(sortAscending, "sortAscending") } }
    var wrapAround: Bool { didSet { store(wrapAround, "wrapAround") } }
    var confirmTrash: Bool { didSet { store(confirmTrash, "confirmTrash") } }
    var quitOnLastWindow: Bool { didSet { store(quitOnLastWindow, "quitOnLastWindow") } }
    // Display
    var renderUnit: RenderUnit { didSet { store(renderUnit.rawValue, "renderUnit") } }
    var openSize: OpenSize { didSet { store(openSize.rawValue, "openSize") } }
    var background: Background { didSet { store(background.rawValue, "background") } }
    var statusBar: StatusBarMode { didSet { store(statusBar.rawValue, "statusBar") } }
    /// Bars (title bar, status bar and the other overlays): clear glass instead of regular (macOS 26+), and how
    /// much black darkens them, 0…0.8 (docs/UI_SPEC.md §10).
    var barClearGlass: Bool { didSet { store(barClearGlass, "barClearGlass") } }
    var barTint: Double { didSet { store(barTint, "barTint") } }
    /// A single click on the picture pins the hover status bar (docs/UI_SPEC.md §2.3). Off by default.
    var clickPinsStatusBar: Bool { didSet { store(clickPinsStatusBar, "clickPinsStatusBar") } }
    var transition: Transition { didSet { store(transition.rawValue, "transition") } }
    var transitionMilliseconds: Double { didSet { store(transitionMilliseconds, "transitionMilliseconds") } }
    var filmstrip: FilmstripMode { didSet { store(filmstrip.rawValue, "filmstrip") } }
    var filmstripThumb: ThumbSize { didSet { store(filmstripThumb.rawValue, "filmstripThumb") } }
    var galleryColumnWidth: Double { didSet { store(galleryColumnWidth, "galleryColumnWidth") } }
    // Controls
    var invertSwipe: Bool { didSet { store(invertSwipe, "invertSwipe") } }
    var zoomStep: Double { didSet { store(zoomStep, "zoomStep") } }
    var keepZoom: Bool { didSet { store(keepZoom, "keepZoom") } }
    // Performance
    var preloadEachSide: Int { didSet { store(preloadEachSide, "preloadEachSide") } }
    var thumbnailMemoryMB: Int { didSet { store(thumbnailMemoryMB, "thumbnailMemoryMB") } }
    var tileMemoryMB: Int { didSet { store(tileMemoryMB, "tileMemoryMB") } }
    var rawMode: RawMode { didSet { store(rawMode.rawValue, "rawMode") } }
    // Remembered UI state
    var infoPanelOpen: Bool { didSet { store(infoPanelOpen, "infoPanelOpen") } }

    // Defaults of the sliders, marked on their tracks in Settings.
    static let defaultBarTint = 0.35
    static let defaultTransitionMilliseconds = 160.0
    static let defaultGalleryColumnWidth = 220.0

    init(defaults: UserDefaults) {
        self.defaults = defaults
        func value<T: RawRepresentable>(_ key: String, _ fallback: T) -> T where T.RawValue == String {
            defaults.string(forKey: key).flatMap(T.init(rawValue:)) ?? fallback
        }
        func bool(_ key: String, _ fallback: Bool) -> Bool { defaults.object(forKey: key) as? Bool ?? fallback }
        func double(_ key: String, _ fallback: Double) -> Double { defaults.object(forKey: key) as? Double ?? fallback }
        func int(_ key: String, _ fallback: Int) -> Int { defaults.object(forKey: key) as? Int ?? fallback }
        sortKey = value("sortKey", SortKey.name)
        sortAscending = bool("sortAscending", true)
        wrapAround = bool("wrapAround", false)
        confirmTrash = bool("confirmTrash", true)
        quitOnLastWindow = bool("quitOnLastWindow", true)
        renderUnit = value("renderUnit", RenderUnit.point)
        openSize = value("openSize", OpenSize.fitMax100)
        background = value("background", Background.checkerboard)
        statusBar = value("statusBar", StatusBarMode.onHover)
        clickPinsStatusBar = bool("clickPinsStatusBar", false)
        barClearGlass = bool("barClearGlass", true)
        barTint = double("barTint", Self.defaultBarTint)
        transition = value("transition", Transition.slideFade)
        transitionMilliseconds = double("transitionMilliseconds", Self.defaultTransitionMilliseconds)
        filmstrip = value("filmstrip", FilmstripMode.autoHide)
        filmstripThumb = value("filmstripThumb", ThumbSize.medium)
        galleryColumnWidth = double("galleryColumnWidth", Self.defaultGalleryColumnWidth)
        invertSwipe = bool("invertSwipe", false)
        zoomStep = double("zoomStep", 1.25)
        keepZoom = bool("keepZoom", false)
        preloadEachSide = int("preloadEachSide", 2)
        thumbnailMemoryMB = int("thumbnailMemoryMB", 0)
        tileMemoryMB = int("tileMemoryMB", 512)
        rawMode = value("rawMode", RawMode.embeddedPreview)
        infoPanelOpen = bool("infoPanelOpen", false)
    }

    /// 0 = automatic: 1/16 of the Mac's memory, 256 MB–2 GB (16 GB → 1 GB ≈ 20.000 thumbnails); memory
    /// pressure still shrinks it (MemoryPressure.swift).
    var effectiveThumbnailMemoryMB: Int { thumbnailMemoryMB > 0 ? thumbnailMemoryMB : Self.automaticThumbnailMemoryMB }

    static let automaticThumbnailMemoryMB: Int = {
        let physicalMB = Int(ProcessInfo.processInfo.physicalMemory >> 20)
        return min(max(physicalMB / 16, 256), 2048)
    }()

    private func store(_ value: Any, _ key: String) { defaults.set(value, forKey: key) }
}

/// Interface language (docs/UI_SPEC.md §10, §12). By default macOS picks from `CFBundleLocalizations` using the
/// user's preferred languages and falls back to English. Choosing one here writes `AppleLanguages` in the app's
/// own defaults domain (the same thing System Settings → Language & Region → Applications does); it applies
/// at the next launch.
enum AppLanguage {
    /// Every language the app ships, English first. Must match `CFBundleLocalizations` in Scripts/bundle.sh and
    /// the languages in Resources/Localizable.xcstrings.
    static let all = ["en", "vi", "zh-Hans", "zh-Hant", "ja", "ko", "fr", "de", "es", "pt-BR", "ru", "it"]

    /// The language's own name ("Tiếng Việt", "日本語").
    static func nativeName(_ code: String) -> String {
        let name = Locale(identifier: code).localizedString(forIdentifier: code) ?? code
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    /// The language set for this app only, or nil when it follows the system.
    static var chosen: String? {
        get {
            guard let id = Bundle.main.bundleIdentifier,
                  let list = UserDefaults.standard.persistentDomain(forName: id)?["AppleLanguages"] as? [String] else { return nil }
            return list.first.flatMap { code in all.first { code.hasPrefix($0) } }
        }
        set {
            if let newValue { UserDefaults.standard.set([newValue], forKey: "AppleLanguages") }
            else { UserDefaults.standard.removeObject(forKey: "AppleLanguages") }
        }
    }
}
