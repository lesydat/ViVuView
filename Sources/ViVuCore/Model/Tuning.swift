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
}
