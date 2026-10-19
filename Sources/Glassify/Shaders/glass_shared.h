//
//  glass_shared.h
//  Glassify
//
//  Copyright © 2026 Hung Phan.
//  See LICENSE file for license information.
//

#ifndef GLASSIFY_GLASS_SHARED_H
#define GLASSIFY_GLASS_SHARED_H

#ifdef __METAL_VERSION__
#include <metal_stdlib>
typedef metal::float4 gls_float4;
#else
#include <cstdint>
struct alignas(16) gls_float4 { float x, y, z, w; };
#endif

#define GLS_MAX_ELEMENTS 8

// Apple's continuous-corner rounded rect.
struct GLSElement {
    // center.xy, halfSize.zw (pt).
    gls_float4 rect;
    // radius, blend toward circular x, y, ovalization.
    gls_float4 corner;
};

// Every field is a float4 so C++ and Metal share the layout; points, y down.
struct GLSGlassUniforms {
    // ptToPx, smoothness (pt), element count, EDR scale.
    gls_float4 surface;
    // uv = (p − xy) · zw: backdrop origin and 1/size (pt).
    gls_float4 backdropMap;
    // backdrop px per pt, LOD bias, max LOD, unused.
    gls_float4 backdropInfo;
    // inner amount, inner 1/height, outer amount, outer 1/height.
    gls_float4 refraction0;
    // distance 0, distance 1, opacity, complex (0/1).
    gls_float4 refraction1;
    // blur, bleed blur, shadow blur radius (pt), unused.
    gls_float4 blurRadii;
    // opacity 0, then the drops 0→1, 1→2, 2→3.
    gls_float4 blurAlpha;
    // blur distances 0–3.
    gls_float4 blurDist;
    // amount, 1/height, distance 0, distance 1.
    gls_float4 bleed0;
    // opacity, darken blend x, y, face opacity.
    gls_float4 bleed1;
    // offset.xy, amount, 1/height.
    gls_float4 shadow0;
    // 1/radius, distance offset, opacity, vibrancy contribution.
    gls_float4 shadow1;
    // shadow fill opacity, unused ×3.
    gls_float4 shadow2;
    // Rows of a 3×4 colour matrix: rgb' = dot(row.xyz, rgb) + row.w.
    gls_float4 faceCM[3];
    // 3×4 colour matrix rows.
    gls_float4 bleedCM[3];
    // 3×4 colour matrix rows.
    gls_float4 shadowCM[3];
    // holding tone on, distance 0, distance 1, white.
    gls_float4 sdr;
    // limit (0 = off), preserve hue, unused ×2.
    gls_float4 clampInfo;
    // light dir.xy, cos(spread), 1/amount − 2.
    gls_float4 hlKey;
    // Same as hlKey, for the fill lobe.
    gls_float4 hlFill;
    // height, curvature, opacity, enabled.
    gls_float4 hlMisc;
    // Rim vibrant matrix rows (the key lobe when hlMode.x is 1).
    gls_float4 hlCM[3];
    // Fill lobe matrix rows when hlMode.x is 1.
    gls_float4 hlCM2[3];
    // separate key and fill layers (0/1), unused ×3.
    gls_float4 hlMode;
    // big glow opacity, little glow opacity, little glow center.xy (pt).
    gls_float4 glow0;
    // little glow diameter (pt), little glow scale, clip element (−1 = all), EDR bits.
    gls_float4 glow1;
    // Big glow vibrant matrix rows.
    gls_float4 glowCM[3];
    // Little glow vibrant matrix rows.
    gls_float4 littleGlowCM[3];
    // alpha (0 = off), outside fade distance (pt), unused ×2.
    gls_float4 tint;
    // Luma-to-tint matrix rows.
    gls_float4 tintCM[3];
    // amount (pt), 1/height, blur radius (pt), unused.
    gls_float4 warp;
    // resting knob colour, straight rgb and alpha.
    gls_float4 resting;
    // content0: on, warp amount, warp 1/height, 1/aberration height; content1: aberration amount, cos, sin, offset; content2: edge start, end, opacity start, end; contentMap: origin.xy, 1/size.zw.
    gls_float4 content0, content1, content2, contentMap;
    // opacity, offset.xy (pt), 1/(σ·√2).
    gls_float4 innerShadow;
    // content lens amount (pt), 1/height, content opacity, unused.
    gls_float4 content3;
    // on, 1/surface width, 1/surface height, unused.
    gls_float4 vibrant0;
    // Content vibrancy matrix rows.
    gls_float4 vibrantCM[3];
};

#endif
