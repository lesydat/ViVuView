/// Metal shaders, compiled at run time with `makeLibrary(source:)`: SwiftPM on the command line does not
/// compile `.metal` files (docs/TECH_SPEC.md §1).
enum Shaders {
    static let source = """
    #include <metal_stdlib>
    using namespace metal;

    struct QuadUniforms {
        float4x4 transform;
        float2 uv0; float2 uv1; float2 uv2; float2 uv3;
        float4 color;
        float4 borderColor;
        float2 sizePx;
        float cornerRadius;
        float borderWidth;
        uint flags;
        uint pad0; uint pad1; uint pad2;
    };

    struct VOut {
        float4 position [[position]];
        float2 uv;
        float2 local;   // position inside the quad in device pixels, origin at the center
    };

    vertex VOut quad_vertex(uint vid [[vertex_id]], constant QuadUniforms &u [[buffer(0)]]) {
        float2 corner = float2(float(vid & 1), float(vid >> 1));
        VOut out;
        out.position = u.transform * float4(corner, 0, 1);
        float2 uvs[4] = { u.uv0, u.uv1, u.uv2, u.uv3 };
        out.uv = uvs[vid];
        out.local = (corner - 0.5) * u.sizePx;
        return out;
    }

    // Signed distance to a rounded rectangle of half-size b and radius r.
    static float roundedBox(float2 p, float2 b, float r) {
        float2 q = abs(p) - b + r;
        return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
    }

    fragment float4 quad_fragment(VOut in [[stage_in]], constant QuadUniforms &u [[buffer(0)]],
                                  texture2d<float> tex [[texture(0)]],
                                  sampler smooth [[sampler(0)]], sampler sharp [[sampler(1)]]) {
        float4 c = u.color;
        if (u.flags & 4u) {
            float2 cell = floor((in.local + u.sizePx * 0.5) / 16.0);
            float g = fmod(cell.x + cell.y, 2.0) < 1.0 ? 0.42 : 0.30;
            c = float4(g, g, g, 1.0);
        }
        if (u.flags & 1u) {
            float4 t = (u.flags & 2u) ? tex.sample(sharp, in.uv) : tex.sample(smooth, in.uv);
            c = t * u.color;
        }
        float2 half_size = u.sizePx * 0.5;
        float d = roundedBox(in.local, half_size, min(u.cornerRadius, min(half_size.x, half_size.y)));
        if (u.borderWidth > 0.0) {
            float inner = smoothstep(-u.borderWidth - 0.5, -u.borderWidth + 0.5, d);
            c = mix(c, u.borderColor, inner);
        }
        if (u.cornerRadius > 0.0 || u.borderWidth > 0.0) {
            c *= 1.0 - smoothstep(-0.5, 0.5, d);
        }
        return c;
    }
    """
}
