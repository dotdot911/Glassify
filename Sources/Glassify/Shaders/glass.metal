//
//  glass.metal
//  Glassify
//
//  Copyright © 2026 Hung Phan.
//  See LICENSE file for license information.
//

#include <metal_stdlib>
#include "glass_shared.h"
#include "glass_sdf.h"

using namespace metal;

struct GLSVertexOut {
    float4 position [[position]];
    float2 pt;
};

// `surfaceSize.xy` is the render surface size in points.
vertex GLSVertexOut gls_fullscreen_vertex(uint vid [[vertex_id]], constant float4& surfaceSize [[buffer(0)]]) {
    const float2 uv = float2((vid << 1) & 2, vid & 2);
    GLSVertexOut out;
    out.position = float4(uv * float2(2, -2) + float2(-1, 1), 0, 1);
    out.pt = uv * surfaceSize.xy;
    return out;
}

static float3 sceneSDF(float2 pt, constant GLSGlassUniforms& u, constant GLSElement* elements) {
    return elementsSDF(pt, elements, int(u.surface.z), u.surface.y);
}

constexpr sampler kBackdropSampler(filter::linear, mip_filter::linear, address::clamp_to_edge);

static float3 applyCM(constant gls_float4* m, float3 c) {
    return float3(dot(m[0].xyz, c) + m[0].w, dot(m[1].xyz, c) + m[1].w, dot(m[2].xyz, c) + m[2].w);
}

static float3 applyCMLinear(constant gls_float4* m, float3 c) {
    return float3(dot(m[0].xyz, c), dot(m[1].xyz, c), dot(m[2].xyz, c));
}

static float3 cmOffset(constant gls_float4* m) { return float3(m[0].w, m[1].w, m[2].w); }

struct Backdrop {
    texture2d<float> tex;
    float2 uv0;
    float2 dirScale;
    float lodScale;
    float lodBias;
    float maxLod;

    float2 warpOffset;

    float lodFor(float radiusPt) const {
        const float r = radiusPt * lodScale;
        return clamp(max(0.f, log2(r < 2 ? r * 0.5f + 1 : r)) + lodBias, 0.f, maxLod);
    }
    float4 sample(float2 offsetPt, float radiusPt) const {
        return tex.sample(kBackdropSampler, uv0 + (offsetPt + warpOffset) * dirScale, level(lodFor(radiusPt)));
    }
};

static float3 unpremul(float4 c) { return c.rgb / max(c.a, 1e-6f); }

static float blurFactor(float x, constant GLSGlassUniforms& u) {
    return u.blurAlpha.x - u.blurAlpha.y * ramp(x, u.blurDist.x, u.blurDist.y) -
           u.blurAlpha.z * ramp(x, u.blurDist.y, u.blurDist.z) -
           u.blurAlpha.w * ramp(x, u.blurDist.z, u.blurDist.w);
}

constexpr sampler kContentSampler(filter::linear, address::clamp_to_zero);

struct LensScene {
    constant GLSGlassUniforms& u;
    constant GLSElement* elements;
    texture2d<float> backdrop;
    texture2d<float> content;
    float lod;
    float fw;
    Backdrop bd;

    float4 below(float2 q) const { return belowAt(q, lod); }
    float4 belowAt(float2 q, float l) const {
        const float3 sq = sceneSDF(q, u, elements);
        const float2 w = u.warp.x != 0 ? lens(sq.x, u.warp.x, u.warp.y) * sq.yz : float2(0);
        float4 c = backdrop.sample(kBackdropSampler, (q + w - u.backdropMap.xy) * u.backdropMap.zw, level(l));
        if (u.resting.w > 0) {
            const float k = u.resting.w * saturate(0.5f - sq.x / fw);
            c = float4(c.rgb * (1 - k) + u.resting.rgb * k, c.a * (1 - k) + k);
        }
        return c;
    }

    float4 clearGlass(float2 p) const {
        const float3 sp = sceneSDF(p, u, elements);
        const float clip = saturate(0.5f - sp.x / fw);
        if (clip <= 0) return float4(0);
        const float2 cq = p + lens(sp.x, u.content0.y, u.content0.z) * sp.yz;
        float4 c = content.sample(kContentSampler, (cq - u.contentMap.xy) * u.contentMap.zw) * u.content3.z;
        if (u.innerShadow.x > 0) {
            const float so = sceneSDF(p - u.innerShadow.yz, u, elements).x;
            const float s = u.innerShadow.x * erfcHalf(-so * u.innerShadow.w);
            c = float4(c.rgb * (1 - s), c.a + s * (1 - c.a));
        }
        return c * clip;
    }

    float4 lensed(float2 q) const {
        const float3 sq = sceneSDF(q, u, elements);
        const float h = u.content3.x != 0 ? lens(sq.x, u.content3.x, u.content3.y) : 0.f;
        return clearGlass(q + h * sq.yz) * saturate(0.5f - sq.x / fw);
    }

    float3 face(float2 q) const {
        const float3 sq = sceneSDF(q, u, elements);
        const float hi = u.refraction1.w > 0 ? lens(sq.x, u.refraction0.x, u.refraction0.y) : 0.f;
        const float gb = u.blurRadii.x > 0 ? u.blurRadii.x * blurFactor(hi + sq.x, u) : 0.f;
        const float l = gb > 0 ? bd.lodFor(sqrt(gb * gb + u.warp.z * u.warp.z)) : lod;
        float3 rgb = unpremul(belowAt(q + hi * sq.yz, l));
        if (u.bleed1.w > 0) rgb = mix(rgb, applyCM(u.faceCM, rgb), u.bleed1.w);
        if (u.sdr.x > 0) {
            const float d = sq.x;
            const float t = d < u.sdr.y ? 1.f : (d >= u.sdr.z ? 0.f : 1 - (d - u.sdr.y) / (u.sdr.z - u.sdr.y));
            rgb = mix(rgb, u.sdr.w * rgb, t * u.sdr.x);
        }
        return rgb;
    }

    float4 composite(float2 q) const {
        const float d = sceneSDF(q, u, elements).x;
        const float k = saturate(0.5f - d / fw);
        const float4 out = below(q);
        if (k <= 0) return out;
        const float4 l = lensed(q);
        return l + mix(out, float4(face(q), 1), k) * (1 - l.a);
    }
};

// The liquid lens's glassForeground layer, over `out` at `pt`.
static float4 lensForeground(float2 pt, float d, float2 n, float4 out, thread const LensScene& scene) {
    constant GLSGlassUniforms& u = scene.u;
    const float span = u.content2.y - u.content2.x;
    const float e = saturate((d - u.content2.x) / (span != 0 ? span : 1.f));
    const float opacity = 1 - mix(u.content2.z, u.content2.w, e);
    const float cov = saturate(0.5f - d / scene.fw);
    if (u.content1.x <= 0 || opacity <= 0 || cov <= 0) return out;
    const float t = saturate((-d - u.content1.w) * u.content0.w);
    const float amount = u.content1.x * (1 - sqrt(saturate(1 - (1 - t) * (1 - t))));
    const float2 na = float2(n.x * u.content1.y - n.y * u.content1.z, n.x * u.content1.z + n.y * u.content1.y);
    const float2 ab = amount * float2(na.y, na.x);
    float r = 0, g = 0, b = 0, a = 0;
    for (int i = 1; i <= 3; ++i) {
        const float w = float(4 - i) / 3.f;
        const float4 c = scene.composite(pt + w * ab);
        const float3 cu = unpremul(c);
        r += cu.r * w; g += cu.g * (1 - w); a += c.a;
    }
    for (int i = 0; i <= 3; ++i) {
        const float w = float(i) / 3.f;
        const float4 c = scene.composite(pt - w * ab);
        const float3 cu = unpremul(c);
        g += cu.g * (1 - w); b += cu.b * w; a += c.a;
    }
    const float alpha = cov * a / 7.f * opacity;
    const float4 f = float4(float3(r * 0.5f, g / 3.f, b * 0.5f) * alpha, alpha);
    return f + out * (1 - f.a);
}

fragment float4 gls_glass_background(GLSVertexOut in [[stage_in]],
                                     constant GLSGlassUniforms& u [[buffer(0)]],
                                     constant GLSElement* elements [[buffer(1)]],
                                     texture2d<float> backdrop [[texture(0)]],
                                     texture2d<float> content [[texture(2)]]) {
    const float3 s = sceneSDF(in.pt, u, elements);
    const float d = s.x;
    const float2 n = s.yz;
    const float face = saturate(0.5f - d / max(fwidth(d), 1e-4f));

    Backdrop bd{backdrop, (in.pt - u.backdropMap.xy) * u.backdropMap.zw, u.backdropMap.zw,
                u.backdropInfo.x * 1.6f, u.backdropInfo.y, u.backdropInfo.z,
                u.warp.x != 0 ? lens(d, u.warp.x, u.warp.y) * n : float2(0)};

    float4 shadow = float4(0);
    if (face < 1 && u.shadow1.z > 0) {
        const float sd = sceneSDF(in.pt - u.shadow0.xy, u, elements).x;
        const float hS = lens(d + u.shadow1.y, u.shadow0.z, u.shadow0.w);
        const float sA = u.shadow1.z * erfcHalf(u.shadow1.x * sd);
        const float contribution = u.shadow1.w;
        float3 rgb;
        float a;
        if (contribution > 1e-6f) {
            const float3 c = unpremul(bd.sample(hS * n, u.blurRadii.z));
            rgb = applyCMLinear(u.shadowCM, c) * contribution + cmOffset(u.shadowCM);
            a = mix(u.shadow2.x, 1.f, contribution);
        } else {
            rgb = cmOffset(u.shadowCM);
            a = u.shadow2.x;
        }
        shadow = float4(rgb, a) * sA;
    }
    if (face <= 0 && shadow.a < 1e-6f) discard_fragment();

    if (u.content0.x > 0) {
        const LensScene scene{u, elements, backdrop, content, bd.lodFor(u.warp.z), max(fwidth(d), 1e-4f), bd};
        float4 out = mix(shadow, float4(scene.face(in.pt), 1), face);
        const float4 l = scene.lensed(in.pt);
        out = l + out * (1 - l.a);
        return lensForeground(in.pt, d, n, out, scene);
    }

    float4 c;
    if (u.refraction1.w > 0) {
        const float hi = lens(d, u.refraction0.x, u.refraction0.y);
        c = bd.sample(hi * n, u.blurRadii.x * blurFactor(hi + d, u));
        if (u.refraction1.z > 0) {
            const float ho = lens(d, u.refraction0.z, u.refraction0.w);
            const float4 c2 = bd.sample(ho * n, u.blurRadii.x * blurFactor(ho + d, u));
            c = mix(c, c2, ramp(d, u.refraction1.x, u.refraction1.y) * u.refraction1.z);
        }
    } else {
        c = bd.sample(float2(0), u.blurRadii.x);
    }
    float3 rgb = unpremul(c);
    if (u.bleed1.w > 0) rgb = mix(rgb, applyCM(u.faceCM, rgb), u.bleed1.w);

    if (u.bleed1.x > 0) {
        const float hb = lens(d, u.bleed0.x, u.bleed0.y);
        const float3 b = applyCM(u.bleedCM, unpremul(bd.sample(hb * n, u.blurRadii.y)));
        const float e = ramp(d, u.bleed0.z, u.bleed0.w);
        const float lum = saturate(dot(rgb, float3(0.2125f, 0.7154f, 0.0721f)));
        float k = u.bleed1.y * lum + u.bleed1.z;
        k = k * k * e;
        k = k * k * u.bleed1.x;
        rgb = mix(rgb, b, k);
    }

    float4 out = mix(shadow, float4(rgb, 1), face);

    if (u.sdr.x > 0) {
        const float t = d < u.sdr.y ? 1.f : (d >= u.sdr.z ? 0.f : 1 - (d - u.sdr.y) / (u.sdr.z - u.sdr.y));
        const float a = saturate(out.a);
        const float4 ht = float4(u.sdr.w * out.rgb * a / max(out.a, 1e-6f), a);
        out = mix(out, ht, t * u.sdr.x);
    }
    return out;
}

// Radial profile of a disc blurred by a Gaussian with σ equal to its radius, every 0.125 radii.
constant float kGlowLUT[41] = {0.393469f, 0.391107f, 0.384103f, 0.372699f, 0.357286f, 0.338379f, 0.316591f,
    0.292601f, 0.267120f, 0.240856f, 0.214483f, 0.188614f, 0.163781f, 0.140416f, 0.118849f, 0.099300f, 0.081892f,
    0.066654f, 0.053538f, 0.042433f, 0.033183f, 0.025600f, 0.019483f, 0.014626f, 0.010829f, 0.007908f, 0.005694f,
    0.004043f, 0.002831f, 0.001954f, 0.001330f, 0.000892f, 0.000590f, 0.000385f, 0.000247f, 0.000156f, 0.000098f,
    0.000060f, 0.000036f, 0.000022f, 0.000013f};

// Saturates on SDR; with EDR (bit 2) clamps at 1.2 and gains 1.2.
static float3 rimLit(float3 m, int edr) {
    return (edr & 2) ? 1.2f * clamp(m, 0.f, 1.2f) : saturate(m);
}

static float blurredDisc(float r, float R) {
    const float x = clamp(r / R, 0.f, 5.f) * 8.f;
    const int i = min(int(x), 39);
    return mix(kGlowLUT[i], kGlowLUT[i + 1], x - float(i));
}

static float4 applyHighlight(GLSVertexOut in, float4 dst, constant GLSGlassUniforms& u,
                             constant GLSElement* elements, texture2d<float> backdrop,
                             texture2d<float> vibrantMask) {
    const float3 s = sceneSDF(in.pt, u, elements);
    float4 out = dst;

    if (u.tint.x > 0) {
        const float fade = u.tint.y;
        const float t = saturate(s.x / fade);
        const float mask = s.x <= 0 ? 1.f : 1.f - t * t * (3.f - 2.f * t);
        const float k = mask * u.tint.x;
        if (k > 0) {
            const float2 uv = (in.pt - u.backdropMap.xy) * u.backdropMap.zw;
            const float4 bg = backdrop.sample(kBackdropSampler, uv, level(0.f));
            const float3 under = out.rgb + (1 - out.a) * bg.rgb;
            const float3 tinted = saturate(applyCM(u.tintCM, under));
            out = float4(out.rgb * (1 - k) + tinted * k, out.a * (1 - k) + k);
        }
    }

    if (u.hlMisc.w > 0) {
        const float g = max(length(s.yz), 1e-6f);
        const float2 n = s.yz / g;
        const float e = -s.x / g;
        const float height = u.hlMisc.x;
        const float t = saturate(e / height);
        const float prof = mix(t < 1 ? 1.f : 0.f, 1 - t, u.hlMisc.y);
        const float fw = max(fwidth(e), 1e-4f);
        const float band = saturate(e / fw + 0.5f) * prof * saturate((height - e) / fw + 0.5f);
        if (e >= -5 && band > 0) {
            const float ik = schlickBias(band * lobe(n, u.hlKey), u.hlKey.w);
            const float ifl = schlickBias(band * lobe(n, u.hlFill), u.hlFill.w);
            if (u.hlMode.x > 0) {
                const int edr = int(u.glow1.w);
                const float3 litK = rimLit(applyCM(u.hlCM, unpremul(out)), edr);
                out.rgb = mix(out.rgb, litK * out.a, saturate(ik) * u.hlMisc.z);
                const float3 litF = rimLit(applyCM(u.hlCM2, unpremul(out)), edr);
                out.rgb = mix(out.rgb, litF * out.a, saturate(ifl) * u.hlMisc.z);
            } else {
                const float i = saturate(ik + ifl) * u.hlMisc.z;
                const float3 lit = rimLit(applyCM(u.hlCM, out.rgb), int(u.glow1.w));
                out.rgb = mix(out.rgb, lit * out.a, i);
            }
        }
    }

    if (u.vibrant0.x > 0) {
        constexpr sampler kMaskSampler(filter::linear, address::clamp_to_zero);
        const float k = vibrantMask.sample(kMaskSampler, in.pt * u.vibrant0.yz).a;
        if (k > 0) {
            const float2 uv = (in.pt - u.backdropMap.xy) * u.backdropMap.zw;
            const float4 bg = backdrop.sample(kBackdropSampler, uv, level(0.f));
            const float3 under = out.rgb + (1 - out.a) * bg.rgb;
            const float3 lit = saturate(applyCM(u.vibrantCM, under));
            out = float4(out.rgb * (1 - k) + lit * k, out.a * (1 - k) + k);
        }
    }

    if (u.glow0.x > 0 || u.glow0.y > 0) {
        const int glowElement = int(u.glow1.z);
        const float clipD = glowElement >= 0 ? elementSDF(in.pt, elements[glowElement]).x : s.x;
        const float inside = saturate(0.5f - clipD / max(fwidth(clipD), 1e-4f));
        if (u.glow0.x > 0) {
            const float3 m = applyCM(u.glowCM, unpremul(out));
            const float3 lit = (int(u.glow1.w) & 1) ? max(m, 0.f) : saturate(m);
            out.rgb = mix(out.rgb, lit * out.a, u.glow0.x * inside);
        }
        const float3 behind = unpremul(out);
        if (u.glow0.y > 0) {
            const float radius = max(0.5f * u.glow1.x * u.glow1.y, 1e-3f);
            const float disc = blurredDisc(length(in.pt - u.glow0.zw), radius);
            const float3 m = applyCM(u.littleGlowCM, behind);
            const float3 lit = (int(u.glow1.w) & 1) ? max(m, 0.f) : saturate(m);
            out.rgb = mix(out.rgb, lit * out.a, saturate(u.glow0.y * disc) * inside);
        }
    }
    return out;
}

// Reads the destination with framebuffer fetch.
fragment float4 gls_glass_highlight(GLSVertexOut in [[stage_in]],
                                    float4 dst [[color(0)]],
                                    constant GLSGlassUniforms& u [[buffer(0)]],
                                    constant GLSElement* elements [[buffer(1)]],
                                    texture2d<float> backdrop [[texture(0)]],
                                    texture2d<float> vibrantMask [[texture(3)]]) {
    return applyHighlight(in, dst, u, elements, backdrop, vibrantMask);
}

// The simulator has no framebuffer fetch: the background pass went to an offscreen texture.
fragment float4 gls_glass_highlight_texture(GLSVertexOut in [[stage_in]],
                                            constant GLSGlassUniforms& u [[buffer(0)]],
                                            constant GLSElement* elements [[buffer(1)]],
                                            texture2d<float> backdrop [[texture(0)]],
                                            texture2d<float, access::read> background [[texture(1)]],
                                            texture2d<float> vibrantMask [[texture(3)]]) {
    return applyHighlight(in, background.read(uint2(in.position.xy)), u, elements, backdrop, vibrantMask);
}
