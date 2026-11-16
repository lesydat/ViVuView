/// Which neighbours to keep decoded, in which order (docs/TECH_SPEC.md §5.2).
/// With index i, browsing direction d and n per side, stage-1 priority is
/// i → i+d → i+2d → i−d → i+3d → i−2d …: n+1 ahead, n behind.
public enum PreloadPlanner {
    public struct Plan: Equatable, Sendable {
        /// Indices to decode at screen size, most urgent first (the current image first).
        public var screen: [Int]
        /// Indices whose small thumbnail (stage 0) should be ready.
        public var thumbnails: [Int]
    }

    public static func plan(index: Int, count: Int, direction: Int, perSide: Int, wrap: Bool, thumbnailRadius: Int = 20) -> Plan {
        guard count > 0, (0..<count).contains(index) else { return Plan(screen: [], thumbnails: []) }
        let d = direction >= 0 ? 1 : -1
        var order: [Int] = [0]
        var ahead = 1, behind = 1
        // Alternate: two ahead, one behind, while either side still has room.
        while ahead <= perSide + 1 || behind <= perSide {
            for _ in 0..<2 where ahead <= perSide + 1 { order.append(d * ahead); ahead += 1 }
            if behind <= perSide { order.append(-d * behind); behind += 1 }
        }
        var screen: [Int] = []
        for offset in order {
            if let i = resolve(index + offset, count: count, wrap: wrap), !screen.contains(i) { screen.append(i) }
        }
        var thumbs: [Int] = []
        for r in 0...thumbnailRadius {
            for offset in r == 0 ? [0] : [d * r, -d * r] {
                if let i = resolve(index + offset, count: count, wrap: wrap), !thumbs.contains(i) { thumbs.append(i) }
            }
        }
        return Plan(screen: screen, thumbnails: thumbs)
    }

    static func resolve(_ i: Int, count: Int, wrap: Bool) -> Int? {
        if (0..<count).contains(i) { return i }
        guard wrap else { return nil }
        return ((i % count) + count) % count
    }
}
