//
//  blur.metal
//  Glassify
//
//  Copyright © 2026 Hung Phan.
//  See LICENSE file for license information.
//

#include <metal_stdlib>

using namespace metal;

constexpr sampler kLinearClamp(filter::linear, address::clamp_to_edge);

// Halves the resolution with a 13-tap filter, the tap count of Core Animation's blur mipmap.
kernel void gls_downsample13(texture2d<float, access::sample> src [[texture(0)]],
                             texture2d<float, access::write> dst [[texture(1)]],
                             uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= dst.get_width() || gid.y >= dst.get_height()) return;
    const float2 texel = 1.0f / float2(src.get_width(), src.get_height());
    const float2 uv = (float2(gid) * 2.0f + 1.0f) * texel;

    float4 a = src.sample(kLinearClamp, uv + texel * float2(-2, -2));
    float4 b = src.sample(kLinearClamp, uv + texel * float2(0, -2));
    float4 c = src.sample(kLinearClamp, uv + texel * float2(2, -2));
    float4 d = src.sample(kLinearClamp, uv + texel * float2(-1, -1));
    float4 e = src.sample(kLinearClamp, uv + texel * float2(1, -1));
    float4 f = src.sample(kLinearClamp, uv + texel * float2(-2, 0));
    float4 g = src.sample(kLinearClamp, uv);
    float4 h = src.sample(kLinearClamp, uv + texel * float2(2, 0));
    float4 i = src.sample(kLinearClamp, uv + texel * float2(-1, 1));
    float4 j = src.sample(kLinearClamp, uv + texel * float2(1, 1));
    float4 k = src.sample(kLinearClamp, uv + texel * float2(-2, 2));
    float4 l = src.sample(kLinearClamp, uv + texel * float2(0, 2));
    float4 m = src.sample(kLinearClamp, uv + texel * float2(2, 2));

    float4 sum = (d + e + i + j) * 0.5f;
    sum += (a + b + g + f) * 0.125f;
    sum += (b + c + h + g) * 0.125f;
    sum += (f + g + l + k) * 0.125f;
    sum += (g + h + m + l) * 0.125f;
    dst.write(sum * 0.25f, gid);
}

// Backdrop level 0 for glass over glass: the snapshot over the other surface's last frame over an opaque base.
kernel void gls_composite_underlay(texture2d<float, access::read> snapshot [[texture(0)]],
                                   texture2d<float, access::sample> underlay [[texture(1)]],
                                   texture2d<float, access::write> dst [[texture(2)]],
                                   texture2d<float, access::sample> page [[texture(3)]],
                                   constant float4 *params [[buffer(0)]],
                                   uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= dst.get_width() || gid.y >= dst.get_height()) return;
    const float4 rect = params[0];
    const float4 pageRect = params[2];
    const float2 uv = (float2(gid) + 0.5f - rect.xy) / rect.zw;
    constexpr sampler kLinearZero(filter::linear, address::clamp_to_zero);
    constexpr sampler kLinearEdge(filter::linear, address::clamp_to_edge);
    const float4 base = pageRect.z > 0.0f ? page.sample(kLinearEdge, (float2(gid) + 0.5f - pageRect.xy) / pageRect.zw, level(0))
                                          : params[1];
    const float4 under = underlay.sample(kLinearZero, uv);
    const float4 below = under + (1.0f - under.a) * base;
    const float4 top = snapshot.read(gid);
    dst.write(top + (1.0f - top.a) * below, gid);
}

static float gls_phi(float z) {
    const float x = fabs(z) * 0.70710678f;
    const float t = 1.0f / (1.0f + 0.3275911f * x);
    const float e = 1.0f - (((((1.061405429f * t - 1.453152027f) * t) + 1.421413741f) * t - 0.284496736f) * t +
                            0.254829592f) * t * exp(-x * x);
    return 0.5f * (1.0f + (z < 0.0f ? -e : e));
}

// A scroll edge effect missing from the snapshot: a colour faded by the shadow of a rect.
kernel void gls_composite_veil(texture2d<float, access::read> snapshot [[texture(0)]],
                               texture2d<float, access::write> dst [[texture(1)]],
                               constant float4 *params [[buffer(0)]],
                               uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= dst.get_width() || gid.y >= dst.get_height()) return;
    const float4 p = params[0], m = params[1], color = params[2];
    const float y = p.x + (float(gid.y) + 0.5f) / p.y;
    float4 c = snapshot.read(gid);
    if (y >= p.z && y <= p.w) {
        const float a = color.a * clamp(gls_phi((y - m.x) / m.z) - gls_phi((y - m.y) / m.z), 0.0f, 1.0f);
        c = float4(c.rgb * (1.0f - a) + color.rgb * a, c.a);
    }
    dst.write(c, gid);
}
