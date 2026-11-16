import CoreGraphics
import Metal
import simd

/// One textured or solid rectangle. Every frame is a list of these (docs/TECH_SPEC.md §3).
public struct Quad {
    public var texture: MTLTexture?
    /// Unit square [0,1]² → clip space.
    public var transform: simd_float4x4
    /// Texture coordinates at the unit square corners (0,0), (1,0), (0,1), (1,1).
    public var uv: (SIMD2<Float>, SIMD2<Float>, SIMD2<Float>, SIMD2<Float>)
    /// Multiplies the texel (use alpha to fade), or is the fill when `texture` is nil. Premultiplied.
    public var color: SIMD4<Float>
    /// Size on screen in device pixels, for rounded corners and borders.
    public var sizePx: SIMD2<Float>
    public var cornerRadius: Float
    public var borderWidth: Float
    public var borderColor: SIMD4<Float>
    /// Nearest-neighbour sampling (pixel-peeping at high zoom).
    public var nearest: Bool
    /// Fill with a grey checkerboard (behind transparent images) instead of `color`.
    public var checker = false

    public init(texture: MTLTexture?, transform: simd_float4x4, sizePx: SIMD2<Float>,
                uv: (SIMD2<Float>, SIMD2<Float>, SIMD2<Float>, SIMD2<Float>) = Quad.fullUV,
                color: SIMD4<Float> = SIMD4(1, 1, 1, 1), cornerRadius: Float = 0, borderWidth: Float = 0,
                borderColor: SIMD4<Float> = SIMD4(1, 1, 1, 1), nearest: Bool = false) {
        self.texture = texture
        self.transform = transform
        self.uv = uv
        self.color = color
        self.sizePx = sizePx
        self.cornerRadius = cornerRadius
        self.borderWidth = borderWidth
        self.borderColor = borderColor
        self.nearest = nearest
    }

    public static let fullUV = (SIMD2<Float>(0, 0), SIMD2<Float>(1, 0), SIMD2<Float>(0, 1), SIMD2<Float>(1, 1))

    /// A rectangle placed in a view of `viewSize` device pixels (origin top-left), optionally rotated
    /// by `rotation` radians (clockwise on screen) around its center. `size` is the unrotated size.
    public static func placed(texture: MTLTexture?, center: CGPoint, size: CGSize, rotation: Double = 0,
                              viewSize: CGSize, uvRect: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1),
                              color: SIMD4<Float> = SIMD4(1, 1, 1, 1), cornerRadius: Float = 0,
                              borderWidth: Float = 0, borderColor: SIMD4<Float> = SIMD4(1, 1, 1, 1),
                              nearest: Bool = false) -> Quad {
        let w = Float(max(viewSize.width, 1)), h = Float(max(viewSize.height, 1))
        // unit square → centered rectangle of `size`
        var m = matrix_identity_float4x4
        m = translation(-0.5, -0.5) * m
        m = scale(Float(size.width), Float(size.height)) * m
        m = rotationZ(Float(rotation)) * m
        m = translation(Float(center.x), Float(center.y)) * m
        // pixels (y down) → clip space (y up)
        let toClip = translation(-1, 1) * scale(2 / w, -2 / h)
        let uv0 = SIMD2<Float>(Float(uvRect.minX), Float(uvRect.minY))
        let uv1 = SIMD2<Float>(Float(uvRect.maxX), Float(uvRect.minY))
        let uv2 = SIMD2<Float>(Float(uvRect.minX), Float(uvRect.maxY))
        let uv3 = SIMD2<Float>(Float(uvRect.maxX), Float(uvRect.maxY))
        return Quad(texture: texture, transform: toClip * m, sizePx: SIMD2(Float(size.width), Float(size.height)),
                    uv: (uv0, uv1, uv2, uv3), color: color, cornerRadius: cornerRadius,
                    borderWidth: borderWidth, borderColor: borderColor, nearest: nearest)
    }

    static func translation(_ x: Float, _ y: Float) -> simd_float4x4 {
        var m = matrix_identity_float4x4
        m.columns.3 = SIMD4(x, y, 0, 1)
        return m
    }

    static func scale(_ x: Float, _ y: Float) -> simd_float4x4 {
        simd_float4x4(diagonal: SIMD4(x, y, 1, 1))
    }

    /// Clockwise on a y-down screen.
    static func rotationZ(_ angle: Float) -> simd_float4x4 {
        let c = cos(angle), s = sin(angle)
        return simd_float4x4(SIMD4(c, s, 0, 0), SIMD4(-s, c, 0, 0), SIMD4(0, 0, 1, 0), SIMD4(0, 0, 0, 1))
    }
}

/// Uniforms passed per quad; layout must match `QuadUniforms` in Shaders.swift.
struct QuadUniforms {
    var transform: simd_float4x4
    var uv0: SIMD2<Float>
    var uv1: SIMD2<Float>
    var uv2: SIMD2<Float>
    var uv3: SIMD2<Float>
    var color: SIMD4<Float>
    var borderColor: SIMD4<Float>
    var sizePx: SIMD2<Float>
    var cornerRadius: Float
    var borderWidth: Float
    var flags: UInt32   // bit 0: textured, bit 1: nearest, bit 2: checkerboard
    var pad0: UInt32 = 0
    var pad1: UInt32 = 0
    var pad2: UInt32 = 0

    init(_ q: Quad) {
        transform = q.transform
        (uv0, uv1, uv2, uv3) = q.uv
        color = q.color
        borderColor = q.borderColor
        sizePx = q.sizePx
        cornerRadius = q.cornerRadius
        borderWidth = q.borderWidth
        flags = (q.texture != nil ? 1 : 0) | (q.nearest ? 2 : 0) | (q.checker ? 4 : 0)
    }
}
