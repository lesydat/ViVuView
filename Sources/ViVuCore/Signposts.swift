import os

/// Shared signposters for Instruments and the benchmarks (docs/TECH_SPEC.md §11.2).
/// Interval names used across the app: Decode, Navigate, FitDecode, RegionDecode, ThumbFill.
public enum Signposts {
    public static let decode = OSSignposter(subsystem: Tuning.bundleID, category: "Decode")
    public static let navigate = OSSignposter(subsystem: Tuning.bundleID, category: "Navigate")
    public static let tiles = OSSignposter(subsystem: Tuning.bundleID, category: "Tiles")
    public static let thumbs = OSSignposter(subsystem: Tuning.bundleID, category: "Thumbs")
}
