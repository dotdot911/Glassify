//
//  pack.cpp
//  Glassify
//
//  Copyright © 2026 Hung Phan.
//  See LICENSE file for license information.
//

#include "glassify/pack.h"

#include <algorithm>
#include <cmath>

#include "glassify/color_matrix.h"

namespace glassify {
namespace {

// Half-size-to-radius ratio below which corners start blending toward circular.
constexpr float kSupercircleK = 1.5286649f;

gls_float4 f4(float x, float y = 0, float z = 0, float w = 0) { return {x, y, z, w}; }
float inv(float h) { return std::fabs(h) > 1e-6f ? 1.f / h : 0.f; }

void putMatrix(gls_float4 rows[3], const ColorMatrix3x4& cm) {
    for (int r = 0; r < 3; ++r) rows[r] = f4(cm.m[r][0], cm.m[r][1], cm.m[r][2], cm.m[r][3]);
}

gls_float4 lobe(float angle, float spread, float amount) {
    if (amount <= 0.f || spread <= 0.f) return f4(0, 0, 2, 0);
    float c = std::cos(spread);
    if (c <= -1.f && amount >= 1.f) c = -1.01f;
    return f4(std::sin(angle), -std::cos(angle), c, 1.f / amount - 2.f);
}

}

float supercircleBlend(float halfSize, float radius) {
    if (radius <= 0.f) return 0.f;
    const float x = (kSupercircleK - halfSize / radius) / (kSupercircleK - 1.f);
    return std::min(std::max(x, 0.f), 1.f);
}

void packUniforms(const GlassInputs& in, const PackContext& ctx, GLSGlassUniforms& out) {
    out = GLSGlassUniforms{};
    const int count = std::min(ctx.elementCount, GLS_MAX_ELEMENTS);

    out.surface = f4(ctx.ptToPx, ctx.smoothness, float(count), 1.f);
    out.backdropMap = f4(ctx.backdropOriginX, ctx.backdropOriginY,
                         inv(ctx.backdropWidth), inv(ctx.backdropHeight));
    out.backdropInfo = f4(ctx.backdropPxPerPt, in.blurLodBias + ctx.lodBias, ctx.backdropMaxLod, 0);

    const bool opacitiesEqual = in.blurOpacity[0] == in.blurOpacity[1] &&
                                in.blurOpacity[1] == in.blurOpacity[2] &&
                                in.blurOpacity[2] == in.blurOpacity[3];
    const bool complex = in.innerRefractionAmount != 0.f || in.outerRefractionAmount != 0.f ||
                         !opacitiesEqual;
    out.refraction0 = f4(in.innerRefractionAmount, inv(in.innerRefractionHeight),
                         in.outerRefractionAmount, inv(in.outerRefractionHeight));
    out.refraction1 = f4(in.refractionDistance0, in.refractionDistance1,
                         std::min(std::max(in.refractionOpacity, 0.f), 1.f), complex ? 1.f : 0.f);

    const float bleedBlur = in.bleedOpacity > 0.f ? in.bleedBlurRadius * 0.5f : 0.f;
    out.blurRadii = f4(in.blurRadius, bleedBlur, in.shadowBlurRadius * 0.5f, 0);
    out.blurAlpha = f4(in.blurOpacity[0], in.blurOpacity[0] - in.blurOpacity[1],
                       in.blurOpacity[1] - in.blurOpacity[2], in.blurOpacity[2] - in.blurOpacity[3]);
    out.blurDist = f4(in.blurDistance[0], in.blurDistance[1], in.blurDistance[2], in.blurDistance[3]);

    out.bleed0 = f4(in.bleedAmount, inv(in.bleedHeight), in.bleedDistance0, in.bleedDistance1);
    out.bleed1 = f4(std::min(std::max(in.bleedOpacity, 0.f), 1.f),
                    in.bleedDarkenBlend ? 1.f : -1.f, in.bleedDarkenBlend ? 0.f : 1.f,
                    std::min(std::max(in.faceOpacity, 0.f), 1.f));

    out.shadow0 = f4(in.shadowOffset[0], in.shadowOffset[1], in.shadowAmount, inv(in.shadowHeight));
    out.shadow1 = f4(inv(in.shadowRadius), in.shadowDistanceOffset,
                     std::min(std::max(in.shadowOpacity, 0.f), 1.f), in.shadowVibrancyContribution);
    ColorMatrixParams shadowCM = in.shadow;
    shadowCM.fill[3] = std::min(shadowCM.fill[3] + in.sdrShadowOpacity, 1.f);
    out.shadow2 = f4(shadowCM.fill[3], 0, 0, 0);

    putMatrix(out.faceCM, yccComposite(in.face));
    putMatrix(out.bleedCM, yccComposite(in.bleed));
    putMatrix(out.shadowCM, yccComposite(shadowCM));

    out.sdr = f4(in.sdrHoldingToneEnabled ? 1.f : 0.f, in.sdrGradientDistance0,
                 in.sdrGradientDistance1, in.sdrHoldingToneWhite);
    out.clampInfo = f4(in.clamp > 0.f ? in.clamp : 0.f, in.clampPreserveHue ? 1.f : 0.f, 0, 0);

    out.hlKey = lobe(in.keyAngle, in.highlightSpread, in.highlightAmount);
    out.hlFill = lobe(in.fillAngle, in.highlightSpread, in.highlightSeparate ? in.fillHighlightAmount : in.highlightAmount);
    out.hlMisc = f4(in.highlightHeight, std::min(std::max(in.highlightCurvature, 0.f), 1.f),
                    in.highlightOpacity, in.highlightOpacity > 0.f ? 1.f : 0.f);
    putMatrix(out.hlCM, vibrantMatrix(in.highlightMatrixA, in.highlightMatrixB, in.highlightMatrixC));
    out.hlMode = f4(in.highlightSeparate ? 1.f : 0.f, 0, 0, 0);
    putMatrix(out.hlCM2, identityColorMatrix());
    if (in.highlightSeparate) {
        static const float kY[3] = {0.2126f, 0.7152f, 0.0722f};
        ColorMatrix3x4 key{};
        for (int r = 0; r < 3; ++r) {
            for (int c = 0; c < 3; ++c) key.m[r][c] = in.keyRimScale[r] * ((r == c ? 1.f : 0.f) - in.keyRimLuma * kY[c]);
            key.m[r][3] = in.keyRimOffset[r];
        }
        putMatrix(out.hlCM, key);
        putMatrix(out.hlCM2, vibrantMatrix(in.highlightMatrixA, in.highlightMatrixB, in.highlightMatrixC));
    }
    putMatrix(out.glowCM, identityColorMatrix());

    out.tint = f4(std::min(std::max(in.tint[3], 0.f), 1.f), std::max(in.tintFadeDistance, 1e-3f), 0, 0);
    putMatrix(out.tintCM, tintMatrix(in.tint, in.tintDark));

    out.warp = f4(in.warpAmount, in.warpHeight > 0 ? 1.f / in.warpHeight : 0.f, in.warpBlurRadius, 0);
    out.resting = f4(in.restingColor[0], in.restingColor[1], in.restingColor[2], in.restingColor[3]);
    const bool content = ctx.hasContent && (in.contentWarpAmount != 0.f || in.aberrationAmount != 0.f);
    out.content0 = f4(content ? 1.f : 0.f, in.contentWarpAmount, in.contentWarpHeight > 0 ? 1.f / in.contentWarpHeight : 0.f,
                      in.aberrationHeight > 0 ? 1.f / in.aberrationHeight : 1e6f);
    out.content1 = f4(in.aberrationAmount, std::cos(in.aberrationAngle), std::sin(in.aberrationAngle), in.aberrationOffset);
    out.content2 = f4(in.edgeStart, in.edgeEnd, in.edgeOpacityStart, in.edgeOpacityEnd);
    out.contentMap = f4(ctx.contentOriginX, ctx.contentOriginY, 1.f / std::max(ctx.contentWidth, 1e-3f),
                        1.f / std::max(ctx.contentHeight, 1e-3f));
    const float sigma = std::max(in.innerShadowRadius, 1e-3f);
    out.innerShadow = f4(in.innerShadowOpacity, in.innerShadowOffset[0], in.innerShadowOffset[1],
                         1.f / (sigma * 1.41421356f));
    out.content3 = f4(in.contentLensAmount, in.contentLensHeight > 0 ? 1.f / in.contentLensHeight : 0.f,
                      in.contentOpacity, 0);
}

void packGlow(const GlowState& glow, GLSGlassUniforms& out) {
    out.glow0 = f4(glow.bigAlpha, glow.littleAlpha, glow.centerX, glow.centerY);
    out.glow1 = f4(glow.littleDiameter, glow.littleScale, float(glow.element), float(glow.edr));
    putMatrix(out.glowCM, vibrantMatrix(1.2f, 0.2f, 0.05f));
    const float c = glow.luma >= 0.f ? 0.9f + (0.25f - 0.9f) * std::pow(std::min(glow.luma, 1.f), 1.25f)
                                     : (glow.dark ? 0.85f : 0.45f);
    const float k = 1.5f / (1.f - c);
    putMatrix(out.littleGlowCM, vibrantMatrix(k, k / 3.f, 0.f));
}

int packElements(const PackContext& ctx, GLSElement out[GLS_MAX_ELEMENTS]) {
    const int count = std::min(ctx.elementCount, GLS_MAX_ELEMENTS);
    for (int i = 0; i < count; ++i) {
        const ShapeElement& e = ctx.elements[i];
        const float hx = e.width * 0.5f, hy = e.height * 0.5f;
        const float r = std::max(e.cornerRadius, 0.f);
        out[i].rect = f4(e.centerX, e.centerY, hx, hy);
        out[i].corner = f4(r, supercircleBlend(hx, r), supercircleBlend(hy, r), e.ovalization);
    }
    return count;
}

}
