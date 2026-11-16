import Foundation

/// Zoom rules shared by keys, wheel and pinch.
public enum ZoomSteps {
    /// Largest zoom, relative to 100%.
    public static let maxRelative = 32.0

    public static func limits(fitScale: Double, unitScale: Double) -> ClosedRange<Double> {
        let low = min(fitScale, unitScale) / 4
        return low...(unitScale * maxRelative)
    }

    /// One key step in or out. Crossing 100% or fit stops there first, so both are always reachable.
    public static func step(from scale: Double, factor: Double, zoomIn: Bool, fitScale: Double, unitScale: Double) -> Double {
        let target = zoomIn ? scale * factor : scale / factor
        let stops = [fitScale, unitScale].sorted()
        for stop in zoomIn ? stops : stops.reversed() {
            let crosses = zoomIn ? (scale < stop * 0.999 && target > stop * 1.001) : (scale > stop * 1.001 && target < stop * 0.999)
            if crosses { return stop }
        }
        let range = limits(fitScale: fitScale, unitScale: unitScale)
        return min(max(target, range.lowerBound), range.upperBound)
    }
}
