import Foundation
/// Every adjustable constant of the app (thresholds, durations, sizes) lives here,
/// so tuning never means hunting through the code. See docs/TECH_SPEC.md.
/// User-facing options live in `Settings` (app target), not here.
public enum Tuning {
    /// Bundle identifier, also used as the logging/signpost subsystem.
    public static let bundleID = "app.vivuview.ViVuView"

    // MARK: Image tiers (docs/TECH_SPEC.md §4.1)

    /// Up to this size (and the GPU's texture limit) an image is one texture (tier S).
    public static let singleTextureMegapixels = 64.0
    /// A full-size RAM pyramid may use at most physical memory / this (tier M); beyond, subsample (tier L-B).
    public static let pyramidMemoryDivisor = 8.0
    /// Zooming past the stage-1 pixels by this factor asks for full resolution.
    public static let detailTrigger = 1.05
    /// Dwell time before a large image starts building its full-resolution pyramid.
    public static let detailDwell = 0.25

    /// GPU textures of thumbnails (tier 2): the budget grows with what the gallery and filmstrip show at once,
    /// so on-screen thumbnails never evict each other (a 5K gallery shows ~100 cells, ~1.6 MB each).
    public static let thumbnailTextureMinimumMB = 128
    /// Upper bound only against runaway use: a quarter of the Mac's memory.
    public static let thumbnailTextureMaximumMB = Int(ProcessInfo.processInfo.physicalMemory >> 20) / 4
    /// Corner radius of the main window, points, for pictures drawn outside it during an image change (they
    /// must match the window they hand over to). Measured: 17 on macOS 26+ with the compact toolbar, ~10 before.
    public static let windowCornerRadius: Double =
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26 ? 17 : 10
    /// Pictures larger than this make their thumbnail on the separate one-at-a-time lane (a 500 MP PNG takes ~4 s
    /// in ImageIO whatever the options).
    public static let thumbnailLargeMegapixels = 60.0
    /// Estimated bytes of one thumbnail texture (640 px long side, BGRA, mipmaps).
    public static let thumbnailTextureEstimate = 640 * 480 * 4 * 4 / 3
}
