//
//  glass_sdf.h
//  Glassify
//
//  Copyright © 2026 Hung Phan.
//  See LICENSE file for license information.
//

#ifndef GLASSIFY_GLASS_SDF_H
#define GLASSIFY_GLASS_SDF_H

#include <metal_stdlib>
#include "glass_shared.h"

using namespace metal;

constant float kSupercircleK = 1.5286649f;

static float cornerPoly(float t) {
    return (((-0.926054f * t + 3.15601f) * t - 3.64122f) * t + 1.26803f) * t + 0.268531f;
}

// Continuous-corner distance in the first quadrant, as (d, outward normal).
static float3 supercircleQuadrant(float2 p, float2 b, float r, float2 k) {
    const float R = r * kSupercircleK;
    const float rr = mix(R, r, max(k.x, k.y));
    const float2 q = p - b + rr;
    const float2 a = max(float2(0), (p - b + R) / R);
    const float len = length(a);
    const float mx = max(a.x, a.y);
    const float t = mx == 0 ? 0 : saturate(min(a.x, a.y) / mx);
    const float fSc = len + 1 - 1 / (1 - t * t * saturate(len) * cornerPoly(t));
    const float fCirc = length(max(float2(0), a * kSupercircleK - (kSupercircleK - 1))) * (1 / kSupercircleK) +
                        (1 - 1 / kSupercircleK);
    const float dx = mix(fSc, fCirc, k.x);
    const float dy = mix(fSc, fCirc, k.y);
    const float s = a.y > a.x ? 1 : -1;
    const float w = saturate(0.5f - s + s * t);
    const float m = mix(dx, dy, w) - 1;
    const float d = min(max(q.x, q.y), 0.f) + R * m;
    float2 n;
    if (q.x + q.y > 0 && any(q > 0)) n = normalize(max(q, float2(0)));
    else n = q.x > q.y ? float2(1, 0) : float2(0, 1);
    return float3(d, n);
}

static float3 elementSDF(float2 pt, GLSElement e) {
    const float2 local = pt - e.rect.xy;
    const float2 b = e.rect.zw;
    const float2 p = abs(local);
    const float r = e.corner.x;
    float3 s;
    if (r < 1e-3f) {
        const float2 q = p - b;
        s.x = length(max(q, float2(0))) + min(max(q.x, q.y), 0.f);
        s.yz = q.x > q.y ? float2(1, 0) : float2(0, 1);
    } else {
        s = supercircleQuadrant(p, b, r, e.corner.yz);
    }
    s.yz *= select(float2(1), float2(-1), local < 0);
    const float ov = e.corner.w;
    if (ov > 0) {
        const float2 radial = float2(local.x, local.y * b.x / max(b.y, 1e-4f));
        if (any(radial != 0)) s.yz = normalize(mix(s.yz, normalize(radial), ov));
    }
    return s;
}

// Polynomial smooth-min whose radius shrinks where the normals agree.
static float3 sdfUnion(float3 src, float3 dst, float k) {
    const float r = saturate(0.5f - 0.5f * dot(src.yz, dst.yz)) * k;
    if (r <= 1e-5f) return src.x < dst.x ? src : dst;
    const float h = saturate(0.5f + 0.5f * (dst.x - src.x) / r);
    return float3(mix(dst.x, src.x, h) - r * h * (1 - h), mix(dst.yz, src.yz, h));
}

// Smooth union of `count` elements; `k` is the container spacing.
static float3 elementsSDF(float2 pt, constant GLSElement* elements, int count, float k) {
    float3 s = elementSDF(pt, elements[0]);
    for (int i = 1; i < count; ++i) s = sdfUnion(elementSDF(pt, elements[i]), s, k);
    return s;
}

static float lens(float d, float amount, float invHeight) {
    const float t = saturate(-d * invHeight);
    return amount - amount * saturate(sqrt((2 - t) * t));
}

static float erfcHalf(float x) {
    const float t = 4 * saturate(x / 4 + 0.5f) - 2;
    const float t2 = t * t;
    return 0.5f + t * (-0.56055f + t2 * (0.16821f + t2 * (-0.034454f + t2 * 0.0029545f)));
}

static float ramp(float x, float a, float b) {
    return b == a ? (x >= a ? 1.f : 0.f) : saturate((x - a) / (b - a));
}

static float lobe(float2 n, float4 l) {
    return saturate((dot(l.xy, n) - l.z) / max(1 - l.z, 1e-6f));
}

static float schlickBias(float i, float k) { return i / max(1 + (1 - i) * k, 1e-6f); }

#endif
