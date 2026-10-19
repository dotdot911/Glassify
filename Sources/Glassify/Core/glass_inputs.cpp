//
//  glass_inputs.cpp
//  Glassify
//
//  Copyright © 2026 Hung Phan.
//  See LICENSE file for license information.
//

#include "glassify/glass_inputs.h"

#include <algorithm>
#include <cmath>

namespace glassify {
namespace {

constexpr float kPi = 3.14159265358979f;

float saturate(float x) { return std::min(std::max(x, 0.f), 1.f); }
float mixf(float a, float b, float t) { return a + (b - a) * t; }

void setFill(ColorMatrixParams& cm, float r, float g, float b, float a) {
    cm.fill[0] = r; cm.fill[1] = g; cm.fill[2] = b; cm.fill[3] = a;
}

float highlightSpreadFor(float s) {
    static const float xs[] = {160.f, 180.f, 200.f, 220.f};
    static const float ys[] = {1.570796f, 2.055335f, 2.747534f, 2.792527f};
    if (s <= xs[0]) return ys[0];
    for (int i = 1; i < 4; ++i) {
        if (s <= xs[i]) return mixf(ys[i - 1], ys[i], (s - xs[i - 1]) / (xs[i] - xs[i - 1]));
    }
    return ys[3];
}

// The face white, sRGB-decoded with its sign kept, at least 1.
float clampForWhite(float white) {
    const float a = std::fabs(white);
    float lin = a <= 0.04045f ? a * 0.0773993808f : (a == 1.f ? 1.f : std::pow(a * 0.947867299f + 0.0521327f, 2.4f));
    if (white <= 0.f) lin = -lin;
    return std::max(lin, 1.f);
}

}

GlassInputs glassInputsFor(GlassStyle style, Appearance appearance, float width, float height,
                           float backdropLuma, Frost frost) {
    const bool light = appearance == Appearance::Light;
    const float s = std::max(std::min(width, height), 0.f);
    const float t = saturate((s - 48.f) / 112.f);
    const float u = saturate((s - 64.f) / 96.f);
    const bool small = s <= 64.f;

    GlassInputs g;

    g.outerRefractionAmount = 0.2f * s;
    g.outerRefractionHeight = 0.125f * s;
    g.blurDistance[0] = -0.5f * s;
    g.blurDistance[1] = -1.f;
    g.blurDistance[2] = 0.f;
    g.blurDistance[3] = 0.f;
    g.blurOpacity[0] = 1.f;
    g.blurOpacity[1] = 0.5f;
    g.blurOpacity[2] = 0.5f;
    g.blurOpacity[3] = 1.f;
    g.refractionDistance0 = -1.f;
    g.refractionDistance1 = -0.666667f;
    g.shadowOffset[0] = 0.f;
    g.shadowOffset[1] = 8.f;
    g.shadowAmount = std::min(0.625f * s, 75.f);
    g.shadowHeight = 0.4f * s;
    g.sdrShadowOpacity = 0.08f + 0.16f * t;
    g.bleedDistance0 = 1.f;
    g.bleedDistance1 = 0.f;
    g.sdrGradientDistance0 = -0.666667f;
    g.sdrGradientDistance1 = -0.333333f;
    g.sdrHoldingToneEnabled = true;
    g.sdrHoldingToneWhite = 0.97f;
    g.maxHeadroom = 9999.f;

    g.keyAngle = -kPi / 4.f;
    g.fillAngle = 3.f * kPi / 4.f;
    g.highlightSpread = highlightSpreadFor(s);
    g.highlightAmount = 0.5f;
    g.highlightHeight = 1.f;
    g.highlightCurvature = 0.7f;
    g.highlightOpacity = 1.f;
    if (light) {
        g.highlightMatrixA = 1.5f; g.highlightMatrixB = 1.4f; g.highlightMatrixC = 0.9f;
    } else {
        g.highlightMatrixA = 3.f; g.highlightMatrixB = 1.65f; g.highlightMatrixC = 0.15f;
    }

    if (style == GlassStyle::Clear) {
        g.blurRadius = 1.f;
        g.innerRefractionAmount = -std::min(1.f * s, 60.f);
        g.innerRefractionHeight = std::min(0.36f * s, 20.f);
        g.refractionOpacity = 0.f;
        g.face.white = 1.15f; g.face.black = 0.075f; g.face.saturation = 1.06f;
        setFill(g.face, 1, 1, 1, 0);
        g.shadowRadius = 0.f;
        g.shadowBlurRadius = 0.f;
        g.shadowOpacity = 0.f;
        g.shadowVibrancyContribution = 0.f;
        g.shadow.white = 1.f; g.shadow.black = 0.f; g.shadow.saturation = 1.2f;
        setFill(g.shadow, 0, 0, 0, 0.1f);
        g.bleedAmount = 0.f; g.bleedHeight = 0.f; g.bleedBlurRadius = 0.f; g.bleedOpacity = 0.f;
        g.bleedDarkenBlend = true;
        g.bleed.white = 1.f; g.bleed.black = 0.75f; g.bleed.saturation = 1.2f;
        g.clamp = clampForWhite(g.face.white);
        g.blurLodBias = 0.25f;
        g.backdropScale = 0.5f;
        g.marginWidth = 0.f;
        return g;
    }

    g.blurRadius = 4.f / 3.f + 8.f / 3.f * t;
    g.blurLodBias = 0.5f;
    g.innerRefractionAmount = -std::min(0.8f * s, 60.f);
    g.innerRefractionHeight = std::min(0.25f * s, 20.f);
    g.refractionOpacity = 0.3f;

    float shadowFillAlpha = 0.12f;
    if (small) {
        const float L = backdropLuma < 0.f ? (light ? 1.f : 0.f) : saturate(backdropLuma);
        g.face.black = std::max(0.10f, L - (frost == Frost::Automatic ? 0.15f : 0.20f));
        g.face.white = std::min(light ? 1.03f : 0.90f, L + 0.45f);
        if (light) {
            setFill(g.face, 1, 1, 1, 0.60f - 0.35f * saturate((L - 0.3f) / 0.7f));
            if (L <= 0.4f) {
                shadowFillAlpha = 0.30f;
            } else if (L <= 0.95f) {
                shadowFillAlpha = 0.30f - 0.12f * (L - 0.4f) / 0.55f;
            } else {
                const float k = saturate((L - 0.95f) / 0.01f);
                shadowFillAlpha = 0.18f - 0.13f * k * k * (3.f - 2.f * k);
            }
        } else {
            setFill(g.face, 0, 0, 0, 0.25f + 0.25f * saturate(L / 0.7f));
        }
    } else if (light) {
        g.face.white = 1.03f;
        g.face.black = 0.5f;
        setFill(g.face, 1, 1, 1, 0.4f);
    } else {
        g.face.white = 0.6f;
        g.face.black = 0.2f;
        setFill(g.face, 0, 0, 0, 0.4f);
    }
    g.face.saturation = 1.f;
    if (frost != Frost::Automatic) {
        if (frost == Frost::Reduced) {
            g.blurRadius = 2.f / 3.f;
        } else {
            g.blurRadius = 0.f;
            for (float& o : g.blurOpacity) o = 0.f;
        }
        g.face.fill[3] = 0.f;
        g.face.saturation = light ? 1.1f : 1.3f;
    }

    g.shadowRadius = 24.f;
    g.shadowBlurRadius = small ? 0.f : 40.f;
    g.shadowOpacity = light ? 0.5f - 0.25f * t : 0.4f - 0.15f * t;
    g.shadowVibrancyContribution = u;
    if (light) {
        g.shadow.white = 1.f; g.shadow.black = 0.f; g.shadow.saturation = 1.8f;
        setFill(g.shadow, 0, 0, 0, shadowFillAlpha);
    } else {
        g.shadow.white = 0.5f; g.shadow.black = 0.f; g.shadow.saturation = 1.f;
        setFill(g.shadow, 0, 0, 0, 0.f);
    }

    g.bleedAmount = 0.35f * s;
    g.bleedHeight = 0.35f * s;
    g.bleedBlurRadius = small ? 0.f : std::min(0.7f * s, 160.f);
    g.bleedOpacity = (light ? 0.5f : 0.8f) * u;
    g.bleedDarkenBlend = light;
    if (light) {
        g.bleed.white = 1.f; g.bleed.black = 0.9f; g.bleed.saturation = 1.2f;
    } else {
        g.bleed.white = 0.5f; g.bleed.black = 0.f; g.bleed.saturation = 1.f;
    }

    g.clamp = clampForWhite(g.face.white);
    g.backdropScale = frost == Frost::Reduced ? 0.5f : 0.25f;
    g.marginWidth = small ? 0.2f * s : std::max(g.shadowAmount + 8.f, g.bleedAmount);
    return g;
}

GlassInputs identityGlassLike(const GlassInputs& like) {
    GlassInputs g;
    g.blurRadius = 0.f;
    for (int i = 0; i < 4; ++i) { g.blurDistance[i] = 0.f; g.blurOpacity[i] = 0.f; }
    g.innerRefractionAmount = 0.f; g.innerRefractionHeight = 0.f;
    g.outerRefractionAmount = 0.f; g.outerRefractionHeight = 0.f;
    g.refractionDistance0 = 0.f; g.refractionDistance1 = 0.f; g.refractionOpacity = 0.f;
    g.faceOpacity = 0.f;
    g.face = ColorMatrixParams{};
    for (int i = 0; i < 3; ++i) g.face.fill[i] = like.face.fill[i];
    g.shadowRadius = 0.f; g.shadowBlurRadius = 0.f; g.shadowAmount = 0.f; g.shadowHeight = 0.f;
    g.shadowOpacity = 0.f; g.sdrShadowOpacity = 0.f;
    g.shadowDistanceOffset = 0.f; g.shadowVibrancyContribution = 0.f;
    g.shadow = ColorMatrixParams{};
    for (int i = 0; i < 3; ++i) g.shadow.fill[i] = like.shadow.fill[i];
    g.shadow.black = 0.f;
    g.bleedAmount = 0.f; g.bleedHeight = 0.f; g.bleedBlurRadius = 0.f; g.bleedOpacity = 0.f;
    g.bleedDistance0 = 0.f; g.bleedDistance1 = 0.f;
    g.bleed = ColorMatrixParams{};
    g.bleed.black = 0.f;
    g.bleedDarkenBlend = like.bleedDarkenBlend;
    g.sdrGradientDistance0 = 0.f; g.sdrGradientDistance1 = 0.f;
    g.sdrHoldingToneEnabled = like.sdrHoldingToneEnabled;
    g.sdrHoldingToneWhite = 1.f;
    g.maxHeadroom = 1.2f;
    g.clamp = 1.f;
    g.clampPreserveHue = like.clampPreserveHue;
    g.blurLodBias = like.blurLodBias;
    g.backdropScale = 1.f;
    g.marginWidth = 0.f;
    g.keyAngle = like.keyAngle; g.fillAngle = like.fillAngle;
    g.highlightSpread = like.highlightSpread; g.highlightAmount = like.highlightAmount;
    g.highlightHeight = like.highlightHeight;
    g.highlightMatrixA = like.highlightMatrixA; g.highlightMatrixB = like.highlightMatrixB;
    g.highlightMatrixC = like.highlightMatrixC;
    g.highlightCurvature = like.highlightCurvature;
    g.highlightOpacity = 0.f;
    g.highlightSeparate = like.highlightSeparate;
    g.fillHighlightAmount = like.fillHighlightAmount;
    g.keyRimLuma = like.keyRimLuma;
    for (int i = 0; i < 3; ++i) { g.keyRimScale[i] = like.keyRimScale[i]; g.keyRimOffset[i] = like.keyRimOffset[i]; }
    g.warpHeight = like.warpHeight; g.contentWarpHeight = like.contentWarpHeight;
    g.aberrationAngle = like.aberrationAngle; g.aberrationHeight = like.aberrationHeight;
    g.aberrationOffset = like.aberrationOffset;
    g.edgeStart = like.edgeStart; g.edgeEnd = like.edgeEnd;
    g.edgeOpacityStart = like.edgeOpacityStart; g.edgeOpacityEnd = like.edgeOpacityEnd;
    g.contentLensHeight = like.contentLensHeight;
    g.contentOpacity = like.contentOpacity;
    for (int i = 0; i < 3; ++i) g.tint[i] = like.tint[i];
    g.tint[3] = 0.f;
    g.tintFadeDistance = like.tintFadeDistance;
    g.tintDark = like.tintDark;
    return g;
}

void setTint(GlassInputs& g, Appearance appearance, const float rgba[4]) {
    for (int i = 0; i < 4; ++i) g.tint[i] = rgba[i];
    g.tintDark = appearance == Appearance::Dark;
}

namespace {
void lerpCM(ColorMatrixParams& o, const ColorMatrixParams& a, const ColorMatrixParams& b, float t) {
    o.white = mixf(a.white, b.white, t);
    o.black = mixf(a.black, b.black, t);
    o.saturation = mixf(a.saturation, b.saturation, t);
    for (int i = 0; i < 4; ++i) o.fill[i] = mixf(a.fill[i], b.fill[i], t);
}
}

GlassInputs lerp(const GlassInputs& a, const GlassInputs& b, float t) {
    GlassInputs o = t < 0.5f ? a : b;
#define GLS_L(f) o.f = mixf(a.f, b.f, t)
    GLS_L(blurRadius);
    for (int i = 0; i < 4; ++i) { GLS_L(blurDistance[i]); GLS_L(blurOpacity[i]); }
    GLS_L(innerRefractionAmount); GLS_L(innerRefractionHeight);
    GLS_L(outerRefractionAmount); GLS_L(outerRefractionHeight);
    GLS_L(refractionDistance0); GLS_L(refractionDistance1); GLS_L(refractionOpacity);
    GLS_L(faceOpacity);
    GLS_L(shadowOffset[0]); GLS_L(shadowOffset[1]);
    GLS_L(shadowRadius); GLS_L(shadowBlurRadius); GLS_L(shadowAmount); GLS_L(shadowHeight);
    GLS_L(shadowOpacity); GLS_L(sdrShadowOpacity); GLS_L(shadowDistanceOffset);
    GLS_L(shadowVibrancyContribution);
    GLS_L(bleedAmount); GLS_L(bleedHeight); GLS_L(bleedBlurRadius); GLS_L(bleedOpacity);
    GLS_L(bleedDistance0); GLS_L(bleedDistance1);
    GLS_L(sdrGradientDistance0); GLS_L(sdrGradientDistance1); GLS_L(sdrHoldingToneWhite);
    GLS_L(maxHeadroom); GLS_L(clamp); GLS_L(blurLodBias); GLS_L(backdropScale); GLS_L(marginWidth);
    GLS_L(keyAngle); GLS_L(fillAngle); GLS_L(highlightSpread); GLS_L(highlightAmount);
    GLS_L(highlightHeight); GLS_L(highlightCurvature); GLS_L(highlightOpacity);
    GLS_L(highlightMatrixA); GLS_L(highlightMatrixB); GLS_L(highlightMatrixC);
    GLS_L(fillHighlightAmount); GLS_L(keyRimLuma);
    for (int i = 0; i < 3; ++i) { GLS_L(keyRimScale[i]); GLS_L(keyRimOffset[i]); }
    for (int i = 0; i < 4; ++i) GLS_L(tint[i]);
    GLS_L(tintFadeDistance);
    for (int i = 0; i < 4; ++i) GLS_L(restingColor[i]);
    GLS_L(warpAmount); GLS_L(warpBlurRadius); GLS_L(contentWarpAmount); GLS_L(aberrationAmount); GLS_L(contentLensAmount);
    GLS_L(innerShadowOpacity); GLS_L(innerShadowRadius); GLS_L(innerShadowOffset[0]); GLS_L(innerShadowOffset[1]);
    GLS_L(contentOpacity);
#undef GLS_L
    lerpCM(o.face, a.face, b.face, t);
    lerpCM(o.shadow, a.shadow, b.shadow, t);
    lerpCM(o.bleed, a.bleed, b.bleed, t);
    return o;
}

float quantizeLuma(float luma) {
    return std::min(std::floor(32.f * saturate(luma)), 31.f) / 31.f;
}

Appearance adaptAppearance(Appearance current, float backdropLuma, const HysteresisRange& range) {
    if (backdropLuma < 0.f) return current;
    const float* r = current == Appearance::Dark ? range.darkRange : range.lightRange;
    if (backdropLuma < r[0]) return Appearance::Dark;
    if (backdropLuma > r[1]) return Appearance::Light;
    return current;
}

GlassInputs liquidLensInputs(float liftProgress, bool materialize) {
    GlassInputs g;
    g.blurRadius = 0.f;
    g.blurDistance[0] = -10.f;
    for (float& o : g.blurOpacity) o = 0.f;
    g.innerRefractionAmount = -17.5f;
    g.innerRefractionHeight = 7.f;
    g.outerRefractionAmount = 0.f;
    g.outerRefractionHeight = 0.f;
    g.refractionDistance0 = -1.f;
    g.refractionDistance1 = -0.666667f;
    g.refractionOpacity = 0.f;
    g.faceOpacity = 1.f;
    g.face = ColorMatrixParams{};
    setFill(g.face, 1, 1, 1, 0);
    g.shadowOffset[0] = 0.f;
    g.shadowOffset[1] = 7.f;
    g.shadowRadius = 8.f;
    g.shadowBlurRadius = 0.f;
    g.shadowAmount = 17.5f;
    g.shadowHeight = 0.f;
    g.shadowOpacity = 0.1f;
    g.sdrShadowOpacity = 0.111429f;
    g.shadowVibrancyContribution = 0.f;
    g.shadow = ColorMatrixParams{};
    setFill(g.shadow, 0, 0, 0, 1);
    g.bleedAmount = 0.f; g.bleedHeight = 0.f; g.bleedBlurRadius = 0.f; g.bleedOpacity = 0.f;
    g.bleedDistance0 = 1.f; g.bleedDistance1 = 0.f;
    g.sdrGradientDistance0 = -0.666667f;
    g.sdrGradientDistance1 = -0.333333f;
    g.sdrHoldingToneEnabled = true;
    g.sdrHoldingToneWhite = 0.97f;
    g.maxHeadroom = 9999.f;
    g.clamp = 0.f;
    g.blurLodBias = 0.f;
    g.backdropScale = 1.f;
    g.marginWidth = 0.f;
    g.keyAngle = -kPi / 4.f;
    g.fillAngle = 3.f * kPi / 4.f;
    g.highlightSpread = 1.570796f;
    g.highlightAmount = 0.5f;
    g.highlightHeight = 1.f;
    g.highlightCurvature = 0.8f;
    g.highlightOpacity = 1.f;
    g.highlightMatrixA = 1.5f; g.highlightMatrixB = 1.f; g.highlightMatrixC = 0.75f;
    g.warpAmount = 9.f * liftProgress;
    g.warpHeight = 36.f;
    g.contentWarpAmount = -17.5f * liftProgress;
    g.contentWarpHeight = 11.2f;
    g.aberrationAmount = 3.684211f;
    g.aberrationAngle = -0.261799f;
    g.aberrationHeight = 0.f;
    g.aberrationOffset = 38.888889f;
    g.edgeStart = -14.f; g.edgeEnd = 0.f; g.edgeOpacityStart = 1.f; g.edgeOpacityEnd = 0.f;
    g.contentLensAmount = -17.5f;
    g.contentLensHeight = 14.f;
    g.innerShadowOpacity = 0.12f * liftProgress;
    g.innerShadowRadius = 3.f * liftProgress;
    g.innerShadowOffset[0] = 0.f;
    g.innerShadowOffset[1] = 7.f * liftProgress;
    g.contentOpacity = std::min(4.f * liftProgress, 1.f);
    if (!materialize) {
        g.contentOpacity = 1.f;
        return g;
    }
    GlassInputs m = lerp(identityGlassLike(g), g, std::min(std::max(liftProgress, 0.f), 1.f));
    m.warpAmount = g.warpAmount; m.warpHeight = g.warpHeight;
    m.contentWarpAmount = g.contentWarpAmount; m.contentWarpHeight = g.contentWarpHeight;
    m.innerShadowOpacity = g.innerShadowOpacity; m.innerShadowRadius = g.innerShadowRadius;
    m.innerShadowOffset[0] = g.innerShadowOffset[0]; m.innerShadowOffset[1] = g.innerShadowOffset[1];
    m.contentOpacity = g.contentOpacity;
    return m;
}

SmallLensMaterial switchLensMaterial(Appearance appearance) {
    if (appearance == Appearance::Light) {
        return SmallLensMaterial{{0.4438f, 0.4438f, 0.4562f}, {3.4360f, 3.4360f, 3.2206f}, {-1.2906f, -1.2906f, -1.1470f}};
    }
    return SmallLensMaterial{{0.4125f, 0.4125f, 0.4875f}, {1.2858f, 1.2858f, 1.2414f}, {0.1428f, 0.1428f, 0.1724f}};
}

SmallLensMaterial tintedLensMaterial(const float tint[3]) {
    SmallLensMaterial m;
    for (int c = 0; c < 3; ++c) {
        const float t = tint[c];
        m.shadowFill[c] = 0.3375f + 0.225f * t;
        m.keyScale[c] = 2.4f / (1.f + t);
        m.keyOffset[c] = m.keyScale[c] * (5.f * t - 3.f) / 12.f;
    }
    return m;
}

GlassInputs smallLiquidLensInputs(float liftProgress, bool materialize, float height, Appearance appearance,
                                  const SmallLensMaterial& material, float warpLifted, float warpUnlifted) {
    const float h = std::max(height, 1.f);
    GlassInputs g;
    g.blurRadius = 2.f;
    g.blurDistance[0] = -10.f; g.blurDistance[1] = 0.f; g.blurDistance[2] = 0.f; g.blurDistance[3] = 0.f;
    g.blurOpacity[0] = 0.f; g.blurOpacity[1] = 0.25f; g.blurOpacity[2] = 0.6f; g.blurOpacity[3] = 0.8f;
    g.innerRefractionAmount = -0.5f * h;
    g.innerRefractionHeight = 0.18f * h;
    g.outerRefractionAmount = 0.f;
    g.outerRefractionHeight = 0.f;
    g.refractionDistance0 = -1.f;
    g.refractionDistance1 = -0.666667f;
    g.refractionOpacity = 0.f;
    g.faceOpacity = 1.f;
    g.face = ColorMatrixParams{};
    g.face.black = 0.1f;
    g.face.white = 1.f;
    setFill(g.face, 1, 1, 1, 0);
    g.shadowOffset[0] = 0.f;
    g.shadowOffset[1] = 7.f;
    g.shadowRadius = 8.f;
    g.shadowBlurRadius = 0.f;
    g.shadowAmount = 0.25f * h;
    g.shadowHeight = 0.f;
    g.shadowOpacity = 0.18f;
    g.sdrShadowOpacity = 0.08f;
    g.shadowVibrancyContribution = 0.f;
    g.shadow = ColorMatrixParams{};
    setFill(g.shadow, material.shadowFill[0], material.shadowFill[1], material.shadowFill[2], 1);
    g.bleedAmount = 0.f; g.bleedHeight = 0.f; g.bleedBlurRadius = 0.f; g.bleedOpacity = 0.f;
    g.bleedDistance0 = 1.f; g.bleedDistance1 = 0.f;
    g.bleedDarkenBlend = true;
    g.sdrGradientDistance0 = -0.666667f;
    g.sdrGradientDistance1 = -0.333333f;
    g.sdrHoldingToneEnabled = true;
    g.sdrHoldingToneWhite = 0.97f;
    g.maxHeadroom = 9999.f;
    g.clamp = 0.f;
    g.blurLodBias = 0.f;
    g.backdropScale = 1.f;
    g.marginWidth = 0.f;
    g.highlightSeparate = true;
    g.keyAngle = -kPi / 4.f;
    g.fillAngle = 3.f * kPi / 4.f;
    g.highlightSpread = kPi;
    g.highlightAmount = 0.5f;
    g.fillHighlightAmount = 0.25f;
    g.highlightHeight = 1.f;
    g.highlightCurvature = 1.f;
    g.highlightOpacity = 1.f;
    g.keyRimLuma = 0.75f;
    for (int c = 0; c < 3; ++c) { g.keyRimScale[c] = material.keyScale[c]; g.keyRimOffset[c] = material.keyOffset[c]; }
    if (appearance == Appearance::Light) {
        g.highlightMatrixA = 1.5f; g.highlightMatrixB = 1.0625f; g.highlightMatrixC = 1.125f;
    } else {
        g.highlightMatrixA = 1.5f; g.highlightMatrixB = 1.f; g.highlightMatrixC = 0.75f;
    }
    const float p = liftProgress;
    g.warpAmount = warpUnlifted + (warpLifted - warpUnlifted) * p;
    g.warpHeight = 36.f;
    g.warpBlurRadius = warpUnlifted > 0 ? 6.f * (1.f - std::min(std::max(p, 0.f), 1.f)) : 0.f;
    g.contentWarpAmount = -17.5f * p;
    g.contentWarpHeight = 11.2f;
    g.aberrationAmount = h / 19.f;
    g.aberrationAngle = -0.261799f;
    g.aberrationHeight = 0.f;
    g.aberrationOffset = 5.f * h / 9.f;
    g.edgeStart = -0.2f * h; g.edgeEnd = 0.f; g.edgeOpacityStart = 1.f; g.edgeOpacityEnd = 0.f;
    g.contentLensAmount = 0.f;
    g.contentLensHeight = 0.f;
    g.innerShadowOpacity = 0.12f * p;
    g.innerShadowRadius = 3.f * p;
    g.innerShadowOffset[0] = 0.f;
    g.innerShadowOffset[1] = 7.f * p;
    g.contentOpacity = 1.f;
    if (!materialize) return g;
    GlassInputs m = lerp(identityGlassLike(g), g, std::min(std::max(p, 0.f), 1.f));
    m.warpAmount = g.warpAmount; m.warpHeight = g.warpHeight; m.warpBlurRadius = g.warpBlurRadius;
    for (int i = 0; i < 4; ++i) m.restingColor[i] = g.restingColor[i];
    m.contentWarpAmount = g.contentWarpAmount; m.contentWarpHeight = g.contentWarpHeight;
    m.innerShadowOpacity = g.innerShadowOpacity; m.innerShadowRadius = g.innerShadowRadius;
    m.innerShadowOffset[0] = g.innerShadowOffset[0]; m.innerShadowOffset[1] = g.innerShadowOffset[1];
    m.contentOpacity = g.contentOpacity;
    return m;
}

}
