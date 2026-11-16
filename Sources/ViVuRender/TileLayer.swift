import CoreGraphics
import Metal
import ViVuCore

/// A decoded tile on the GPU: the texture (with a one-pixel border) and the uv rect of the tile inside it.
public struct TileTexture: @unchecked Sendable {
    // Sendable: Metal textures are thread-safe.
    public let texture: MTLTexture
    public let uv: CGRect

    public init(texture: MTLTexture, uv: CGRect) {
        self.texture = texture
        self.uv = uv
    }
}

/// Tiles of the current large image, LRU by bytes (docs/TECH_SPEC.md §4.3; budget from Settings).
public struct TileCache {
    private var lru: ByteLRU<TileKey, TileTexture>

    public init(budgetBytes: Int) { lru = ByteLRU(budget: budgetBytes) }

    public mutating func get(_ key: TileKey) -> TileTexture? { lru.value(for: key) }
    public func peek(_ key: TileKey) -> TileTexture? { lru.peek(key) }
    public func contains(_ key: TileKey) -> Bool { lru.contains(key) }
    public mutating func put(_ tile: TileTexture, for key: TileKey) {
        lru.insert(tile, for: key, cost: tile.texture.width * tile.texture.height * 4)
    }
    public mutating func removeAll() { lru.removeAll() }
    public mutating func setBudget(_ bytes: Int) { lru.setBudget(bytes) }
    public var bytes: Int { lru.totalCost }
    public var count: Int { lru.count }
}

public enum TileLayer {
    /// Quads for `tiles` (level-0 image space = oriented space of the region source) under `viewport`.
    public static func quads(_ tiles: [(TileKey, TileTexture)], imageSize: PixelSize, viewport: Viewport,
                             viewSize: CGSize, extraRotation: Double = 0, offsetX: Double = 0) -> [Quad] {
        let rotation = Double(viewport.quarterTurns) * .pi / 2 + extraRotation
        return tiles.map { key, tile in
            let r = TilePlanner.rect(of: key, imageSize: imageSize)
            var center = viewport.viewPoint(CGPoint(x: Double(r.x) + Double(r.width) / 2, y: Double(r.y) + Double(r.height) / 2),
                                            view: viewSize)
            center.x += offsetX
            // Neighbouring tiles share exact edge coordinates; the GPU's fill rule leaves no gap between them.
            let size = CGSize(width: Double(r.width) * viewport.scale, height: Double(r.height) * viewport.scale)
            return Quad.placed(texture: tile.texture, center: center, size: size, rotation: rotation, viewSize: viewSize,
                               uvRect: tile.uv, nearest: viewport.scale / Double(1 << key.level) >= 4)
        }
    }
}
