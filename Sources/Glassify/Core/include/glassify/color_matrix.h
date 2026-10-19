//
//  color_matrix.h
//  Glassify
//
//  Copyright © 2026 Hung Phan.
//  See LICENSE file for license information.
//

#pragma once

#include "glassify/glass_inputs.h"

namespace glassify {

// rgb' = M · (r, g, b, 1), on sRGB-encoded values.
struct ColorMatrix3x4 {
    float m[3][4];
};

// The luma weights Core Animation uses.
constexpr float kLumaR = 0.2125f, kLumaG = 0.7154f, kLumaB = 0.0721f;

ColorMatrix3x4 identityColorMatrix();

// Core Animation's ColorMatrix composite of white, black, saturation and fill.
ColorMatrix3x4 yccComposite(const ColorMatrixParams& p);

// a·I − b·[luma row] + c.
ColorMatrix3x4 vibrantMatrix(float a, float b, float c);

// Maps backdrop luma onto a range that ends at the tint colour, so the tint follows the backdrop.
ColorMatrix3x4 tintMatrix(const float rgb[3], bool dark);

void applyColorMatrix(const ColorMatrix3x4& cm, const float in[3], float out[3]);

}
