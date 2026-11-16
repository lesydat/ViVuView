/// Every adjustable constant of the app (thresholds, durations, sizes) lives here,
/// so tuning never means hunting through the code. See docs/TECH_SPEC.md.
/// User-facing options live in `Settings` (app target), not here.
public enum Tuning {
    /// Bundle identifier, also used as the logging/signpost subsystem.
    public static let bundleID = "app.vivuview.ViVuView"
}
