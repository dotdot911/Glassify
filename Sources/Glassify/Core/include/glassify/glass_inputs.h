//
//  glass_inputs.h
//  Glassify
//
//  Copyright © 2026 Hung Phan.
//  See LICENSE file for license information.
//

#pragma once

namespace glassify {

enum class GlassStyle { Regular, Clear };
enum class Appearance { Light, Dark };

// Core Animation's ColorMatrix inputs; color_matrix.h turns them into a 3×4 matrix.
struct ColorMatrixParams {
    float white = 1.f;
    float black = 0.f;
    float saturation = 1.f;
    // Straight (non-premultiplied) RGBA.
    float fill[4] = {0, 0, 0, 0};
};

// The glass parameters in Core Animation's own terms, in points.
struct GlassInputs {
    float blurRadius = 0;
    float blurDistance[4] = {0, 0, 0, 0};
    float blurOpacity[4] = {1, 1, 1, 1};

    float innerRefractionAmount = 0, innerRefractionHeight = 1;
    float outerRefractionAmount = 0, outerRefractionHeight = 1;
    float refractionDistance0 = 0, refractionDistance1 = 0, refractionOpacity = 0;

    float faceOpacity = 1;
    ColorMatrixParams face;

    float shadowOffset[2] = {0, 0};
    float shadowRadius = 0, shadowBlurRadius = 0;
    float shadowAmount = 0, shadowHeight = 1;
    float shadowOpacity = 0, sdrShadowOpacity = 0;
    float shadowDistanceOffset = 0, shadowVibrancyContribution = 0;
    ColorMatrixParams shadow;

    float bleedAmount = 0, bleedHeight = 1, bleedBlurRadius = 0, bleedOpacity = 0;
    float bleedDistance0 = 1, bleedDistance1 = 0;
    bool bleedDarkenBlend = false;
    ColorMatrixParams bleed;

    float sdrGradientDistance0 = 0, sdrGradientDistance1 = 0;
    bool sdrHoldingToneEnabled = false;
    float sdrHoldingToneWhite = 1;
    float maxHeadroom = 9999;
    float clamp = 0;
    bool clampPreserveHue = false;

    // Not an Apple input: offsets the blur pyramid level, because this pyramid is not Core Animation's.
    float blurLodBias = 0;

    float backdropScale = 0.25f;
    float marginWidth = 0;

    float keyAngle = 0, fillAngle = 0;
    float highlightSpread = 0, highlightAmount = 0, highlightHeight = 0, highlightCurvature = 0;
    float highlightOpacity = 1;
    // The vibrant matrix a·I − b·Y + c.
    float highlightMatrixA = 1, highlightMatrixB = 0, highlightMatrixC = 0;
    // Two highlight layers (key with keyRim*, then fill) instead of one KeyFill, as on the small lens.
    bool highlightSeparate = false;
    float fillHighlightAmount = 0;
    float keyRimScale[3] = {1, 1, 1}, keyRimOffset[3] = {0, 0, 0}, keyRimLuma = 0;

    // Straight RGBA; alpha 0 means no tint.
    float tint[4] = {0, 0, 0, 0};
    float tintFadeDistance = 1.0f;
    bool tintDark = false;

    // The BackdropView displacement under the liquid lens; 0 turns it off.
    float warpAmount = 0, warpHeight = 0;
    float warpBlurRadius = 0;
    // The resting knob (straight RGBA), between the warped backdrop and the glass, so the glass refracts it.
    float restingColor[4] = {0, 0, 0, 0};
    float contentWarpAmount = 0, contentWarpHeight = 0;
    float aberrationAmount = 0, aberrationAngle = 0;
    // Height 0 makes the profile a step at `aberrationOffset`.
    float aberrationHeight = 0, aberrationOffset = 0;
    float edgeStart = 0, edgeEnd = 0, edgeOpacityStart = 0, edgeOpacityEnd = 0;
    // Inverted inner shadow drawn under the glass face.
    float innerShadowOpacity = 0, innerShadowRadius = 0, innerShadowOffset[2] = {0, 0};
    // Displacement of the content portal drawn over the face.
    float contentLensAmount = 0, contentLensHeight = 0;
    // Opacity of the lifted content, min(4p, 1).
    float contentOpacity = 1;
};

// The tab bar selection drop; `materialize` false gives the full glass for the unlift, which fades out instead.
GlassInputs liquidLensInputs(float liftProgress, bool materialize = true);

// The tint-dependent colours of the small liquid lens (switch knob, slider thumb).
struct SmallLensMaterial {
    // Drop shadow fill, alpha 1.
    float shadowFill[3];
    // Key rim matrix scale a_c, with b = 0.75·a_c.
    float keyScale[3];
    float keyOffset[3];
};
SmallLensMaterial switchLensMaterial(Appearance appearance);
// A knob tinted with the sRGB colour `tint`, as on UISlider.
SmallLensMaterial tintedLensMaterial(const float tint[3]);
// `height` is the lifted lens height the size laws scale with.
GlassInputs smallLiquidLensInputs(float liftProgress, bool materialize, float height, Appearance appearance,
                                  const SmallLensMaterial& material, float warpLifted, float warpUnlifted);

// Glass over a scroll edge effect takes its frost from the edge effect.
enum class Frost { Automatic, Reduced, None };

// `backdropLuma` is the sRGB-encoded mean luma behind the glass, negative when unknown; only small glass uses it.
GlassInputs glassInputsFor(GlassStyle style, Appearance appearance, float width, float height,
                           float backdropLuma = -1.f, Frost frost = Frost::Automatic);

// The glass materialize starts from: no refraction, tint, shadow, bleed or highlight.
GlassInputs identityGlassLike(const GlassInputs& like);

// Booleans switch at t = 0.5.
GlassInputs lerp(const GlassInputs& a, const GlassInputs& b, float t);

// Luma thresholds that flip the glass between light and dark, with hysteresis so the scheme is sticky.
struct HysteresisRange {
    float lightRange[2] = {0.2f, 0.5f};
    float darkRange[2] = {0.6f, 0.9f};
};
Appearance adaptAppearance(Appearance current, float backdropLuma, const HysteresisRange& range = {});

// Rounds luma to 32 levels, as UIKit does before animating it.
float quantizeLuma(float luma);

void setTint(GlassInputs& g, Appearance appearance, const float rgba[4]);

}
