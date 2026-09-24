/// The Metal Shading Language source for the fractal renderer. It is
/// compiled at runtime with fast math disabled: the double-float routines
/// depend on IEEE rounding, which fast math would optimize away.
enum FractalShaders {
    static let source = #"""
    #include <metal_stdlib>
    using namespace metal;

    // Mirrors `FractalUniforms` in Swift. Scalars only, so both languages
    // agree on the layout without padding rules getting involved.
    struct FractalUniforms {
        float centerXHi;
        float centerXLo;
        float centerYHi;
        float centerYLo;
        float juliaXHi;
        float juliaXLo;
        float juliaYHi;
        float juliaYLo;
        float scale;          // complex units per pixel
        float width;          // viewport size in pixels
        float height;
        float originX;        // viewport origin within the render target
        float originY;
        float colorDensity;
        float colorOffset;
        float cornerRadius;   // in pixels; rounds the Julia inset
        float interiorR;
        float interiorG;
        float interiorB;
        int maxIterations;
        int isJulia;
        int precise;
        int samplesPerAxis;
    };

    struct VertexOut {
        float4 position [[position]];
    };

    // One oversized triangle covers the whole viewport.
    vertex VertexOut fractal_vertex(uint vid [[vertex_id]]) {
        float2 p = float2(float((vid << 1) & 2), float(vid & 2));
        VertexOut out;
        out.position = float4(p * 2.0 - 1.0, 0.0, 1.0);
        return out;
    }

    // ---------------------------------------------------------------------
    // Double-float arithmetic. A value is the unevaluated sum hi + lo of two
    // floats, giving about 48 significant bits instead of 24.
    // ---------------------------------------------------------------------

    // Knuth's TwoSum: s + e == a + b exactly.
    inline float2 two_sum(float a, float b) {
        float s = a + b;
        float bb = s - a;
        float e = (a - (s - bb)) + (b - bb);
        return float2(s, e);
    }

    // Requires |a| >= |b|.
    inline float2 quick_two_sum(float a, float b) {
        float s = a + b;
        float e = b - (s - a);
        return float2(s, e);
    }

    // p + e == a * b exactly, using a fused multiply-add for the error.
    inline float2 two_prod(float a, float b) {
        float p = a * b;
        float e = fma(a, b, -p);
        return float2(p, e);
    }

    inline float2 df_add(float2 a, float2 b) {
        float2 s = two_sum(a.x, b.x);
        float2 t = two_sum(a.y, b.y);
        s.y += t.x;
        s = quick_two_sum(s.x, s.y);
        s.y += t.y;
        return quick_two_sum(s.x, s.y);
    }

    inline float2 df_mul(float2 a, float2 b) {
        float2 p = two_prod(a.x, b.x);
        p.y += a.x * b.y + a.y * b.x;
        return quick_two_sum(p.x, p.y);
    }

    inline float2 df_sqr(float2 a) {
        float2 p = two_prod(a.x, a.x);
        p.y += 2.0 * a.x * a.y;
        return quick_two_sum(p.x, p.y);
    }

    // ---------------------------------------------------------------------
    // Escape time. Both variants return the smooth iteration count, or -1
    // for points presumed inside the set.
    // ---------------------------------------------------------------------

    constant float kBailout2 = 65536.0; // |z| > 256 keeps the smoothing exact

    inline float smooth_count(int i, float modulus2) {
        float logModulus = 0.5 * log(modulus2);
        return float(i) + 1.0 - log2(logModulus / 0.69314718);
    }

    inline bool in_cardioid_or_bulb(float x, float y) {
        float y2 = y * y;
        float q = (x - 0.25) * (x - 0.25) + y2;
        if (q * (q + (x - 0.25)) <= 0.25 * y2) { return true; }
        return (x + 1.0) * (x + 1.0) + y2 <= 0.0625;
    }

    float escape_fast(constant FractalUniforms &u, float dx, float dy) {
        float px = u.centerXHi + (u.centerXLo + dx);
        float py = u.centerYHi + (u.centerYLo + dy);
        float2 z;
        float2 c;
        if (u.isJulia != 0) {
            z = float2(px, py);
            c = float2(u.juliaXHi, u.juliaYHi);
        } else {
            if (in_cardioid_or_bulb(px, py)) { return -1.0; }
            z = float2(0.0);
            c = float2(px, py);
        }
        for (int i = 0; i < u.maxIterations; i++) {
            float x2 = z.x * z.x;
            float y2 = z.y * z.y;
            if (x2 + y2 > kBailout2) { return smooth_count(i, x2 + y2); }
            z = float2(x2 - y2 + c.x, 2.0 * z.x * z.y + c.y);
        }
        return -1.0;
    }

    float escape_precise(constant FractalUniforms &u, float dx, float dy) {
        float2 px = df_add(float2(u.centerXHi, u.centerXLo), float2(dx, 0.0));
        float2 py = df_add(float2(u.centerYHi, u.centerYLo), float2(dy, 0.0));
        float2 zx;
        float2 zy;
        float2 cx;
        float2 cy;
        if (u.isJulia != 0) {
            zx = px;
            zy = py;
            cx = float2(u.juliaXHi, u.juliaXLo);
            cy = float2(u.juliaYHi, u.juliaYLo);
        } else {
            if (in_cardioid_or_bulb(px.x, py.x)) { return -1.0; }
            zx = float2(0.0);
            zy = float2(0.0);
            cx = px;
            cy = py;
        }
        for (int i = 0; i < u.maxIterations; i++) {
            float2 x2 = df_sqr(zx);
            float2 y2 = df_sqr(zy);
            float modulus2 = x2.x + y2.x;
            if (modulus2 > kBailout2) { return smooth_count(i, modulus2); }
            float2 xy = df_mul(zx, zy);
            zy = df_add(float2(2.0 * xy.x, 2.0 * xy.y), cy);
            zx = df_add(df_add(x2, float2(-y2.x, -y2.y)), cx);
        }
        return -1.0;
    }

    inline float3 to_linear(float3 c) { return pow(max(c, float3(0.0)), float3(2.2)); }
    inline float3 to_display(float3 c) { return pow(max(c, float3(0.0)), float3(1.0 / 2.2)); }

    fragment float4 fractal_fragment(VertexOut in [[stage_in]],
                                     constant FractalUniforms &u [[buffer(0)]],
                                     texture2d<float> palette [[texture(0)]]) {
        constexpr sampler paletteSampler(filter::linear, address::repeat);

        // Pixel coordinates within this viewport, origin top left.
        float2 local = in.position.xy - float2(u.originX, u.originY);

        // Rounded corners (used by the Julia inset), antialiased.
        float coverage = 1.0;
        if (u.cornerRadius > 0.0) {
            float2 halfSize = float2(u.width, u.height) * 0.5;
            float2 q = abs(local - halfSize) - (halfSize - u.cornerRadius);
            float distance = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - u.cornerRadius;
            coverage = clamp(0.5 - distance, 0.0, 1.0);
            if (coverage <= 0.0) { discard_fragment(); }
        }

        float3 interior = float3(u.interiorR, u.interiorG, u.interiorB);
        int n = max(u.samplesPerAxis, 1);
        float3 accumulated = float3(0.0);
        for (int sy = 0; sy < n; sy++) {
            for (int sx = 0; sx < n; sx++) {
                float2 sample = floor(local) + (float2(sx, sy) + 0.5) / float(n);
                float dx = (sample.x - u.width * 0.5) * u.scale;
                float dy = (u.height * 0.5 - sample.y) * u.scale;
                float count = u.precise != 0 ? escape_precise(u, dx, dy) : escape_fast(u, dx, dy);
                float3 color;
                if (count < 0.0) {
                    color = interior;
                } else {
                    float t = sqrt(max(count, 0.0)) * u.colorDensity + u.colorOffset;
                    color = palette.sample(paletteSampler, float2(t, 0.5)).rgb;
                }
                accumulated += to_linear(color);
            }
        }
        float3 color = to_display(accumulated / float(n * n));
        return float4(color, coverage);
    }

    // Copies the cached fractal image to the screen.
    fragment float4 composite_fragment(VertexOut in [[stage_in]],
                                       texture2d<float> source [[texture(0)]]) {
        uint2 p = uint2(in.position.xy);
        p = min(p, uint2(source.get_width() - 1, source.get_height() - 1));
        return float4(source.read(p).rgb, 1.0);
    }
    """#
}
