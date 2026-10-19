//
//  pack.h
//  Glassify
//
//  Copyright © 2026 Hung Phan.
//  See LICENSE file for license information.
//

#pragma once

#include "glassify/glass_inputs.h"
#include "../../../Shaders/glass_shared.h"

namespace glassify {

struct ShapeElement {
    // Points, in render-surface space.
    float centerX, centerY;
    float width, height;
    // Continuous ("supercircle") corners.
    float cornerRadius;
    float ovalization = 0.5f;
};

struct PackContext {
    float ptToPx = 2.f;
    // The merge distance between elements (the container spacing).
    float smoothness = 0.f;
    const ShapeElement* elements = nullptr;
    int elementCount = 0;
    float backdropOriginX = 0, backdropOriginY = 0;
    float backdropWidth = 1, backdropHeight = 1;
    float backdropPxPerPt = 0.5f;
    float backdropMaxLod = 0.f;
    // 0 keeps Apple's formula.
    float lodBias = 0.f;
    // Whether a lifted lens content texture is bound.
    bool hasContent = false;
    float contentOriginX = 0, contentOriginY = 0, contentWidth = 1, contentHeight = 1;
};

// 0 while halfSize >= K·r, 1 once halfSize <= r (a capsule).
float supercircleBlend(float halfSize, float radius);

void packUniforms(const GlassInputs& in, const PackContext& ctx, GLSGlassUniforms& out);

struct GlowState {
    float bigAlpha = 0, littleAlpha = 0;
    float centerX = 0, centerY = 0;
    float littleDiameter = 0, littleScale = 1;
    bool dark = false;
    // The luma handed to the little glow, or −1 for none.
    float luma = -1.f;
    // The element the glow clips to, or −1 for the whole scene.
    int element = -1;
    // EDR screens. Bit 1: the glow mix is unclamped; bit 2: the rim clamps at 1.2 and gains 1.2.
    int edr = 0;
};
void packGlow(const GlowState& glow, GLSGlassUniforms& out);

// Returns how many elements were written, at most GLS_MAX_ELEMENTS.
int packElements(const PackContext& ctx, GLSElement out[GLS_MAX_ELEMENTS]);

}
