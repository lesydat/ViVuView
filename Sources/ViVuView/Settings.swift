import Foundation
import Observation
import ViVuCore

/// Every user option (docs/UI_SPEC.md §10). Backed by UserDefaults, the only thing the app writes to disk.
/// Changes take effect immediately: views observe this object.
@MainActor @Observable
final class Settings {
    static let shared = Settings(defaults: .standard)

    enum OpenSize: String, CaseIterable { case fitMax100, alwaysFit, always100 }
    enum Background: String, CaseIterable { case black, darkGray, checkerboard }
    enum StatusBarMode: String, CaseIterable { case onHover, always, never }
    enum Transition: String, CaseIterable { case slideFade, fade, none }
    enum FilmstripMode: String, CaseIterable { case autoHide, always }
    enum ThumbSize: String, CaseIterable {
        case small, medium, large
        var height: Double { switch self { case .small: 48; case .medium: 72; case .large: 104 } }
    }
    enum SortKey: String, CaseIterable { case name, modified, captured, size }
    enum WheelAction: String, CaseIterable { case zoom, navigate }
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
    var transition: Transition { didSet { store(transition.rawValue, "transition") } }
    var transitionMilliseconds: Double { didSet { store(transitionMilliseconds, "transitionMilliseconds") } }
    var filmstrip: FilmstripMode { didSet { store(filmstrip.rawValue, "filmstrip") } }
    var filmstripThumb: ThumbSize { didSet { store(filmstripThumb.rawValue, "filmstripThumb") } }
    var galleryColumnWidth: Double { didSet { store(galleryColumnWidth, "galleryColumnWidth") } }
    // Controls
    var wheelAction: WheelAction { didSet { store(wheelAction.rawValue, "wheelAction") } }
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
        background = value("background", Background.black)
        statusBar = value("statusBar", StatusBarMode.onHover)
        transition = value("transition", Transition.slideFade)
        transitionMilliseconds = double("transitionMilliseconds", 160)
        filmstrip = value("filmstrip", FilmstripMode.autoHide)
        filmstripThumb = value("filmstripThumb", ThumbSize.medium)
        galleryColumnWidth = double("galleryColumnWidth", 220)
        wheelAction = value("wheelAction", WheelAction.zoom)
        invertSwipe = bool("invertSwipe", false)
        zoomStep = double("zoomStep", 1.25)
        keepZoom = bool("keepZoom", false)
        preloadEachSide = int("preloadEachSide", 2)
        thumbnailMemoryMB = int("thumbnailMemoryMB", 384)
        tileMemoryMB = int("tileMemoryMB", 512)
        rawMode = value("rawMode", RawMode.embeddedPreview)
        infoPanelOpen = bool("infoPanelOpen", false)
    }

    private func store(_ value: Any, _ key: String) { defaults.set(value, forKey: key) }
}
