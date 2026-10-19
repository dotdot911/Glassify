//
//  color_matrix.cpp
//  Glassify
//
//  Copyright © 2026 Hung Phan.
//  See LICENSE file for license information.
//

#include "glassify/color_matrix.h"

namespace glassify {

ColorMatrix3x4 identityColorMatrix() {
    ColorMatrix3x4 cm = {};
    for (int r = 0; r < 3; ++r) cm.m[r][r] = 1.f;
    return cm;
}

// out = (1 − a)·((white − black)·Y + black + sat·(rgb − Y)) + fill.rgb·a.
ColorMatrix3x4 yccComposite(const ColorMatrixParams& p) {
    const float luma[3] = {0.2126f, 0.7152f, 0.0722f};
    const float a = p.fill[3];
    const float keep = 1.f - a;
    const float range = p.white - p.black;
    ColorMatrix3x4 cm = {};
    for (int r = 0; r < 3; ++r) {
        for (int c = 0; c < 3; ++c) {
            cm.m[r][c] = keep * ((r == c ? p.saturation : 0.f) + (range - p.saturation) * luma[c]);
        }
        cm.m[r][3] = keep * p.black + p.fill[r] * a;
    }
    return cm;
}

ColorMatrix3x4 vibrantMatrix(float a, float b, float c) {
    const float luma[3] = {kLumaR, kLumaG, kLumaB};
    ColorMatrix3x4 cm = {};
    for (int r = 0; r < 3; ++r) {
        for (int k = 0; k < 3; ++k) cm.m[r][k] = (r == k ? a : 0.f) - b * luma[k];
        cm.m[r][3] = c;
    }
    return cm;
}

ColorMatrix3x4 tintMatrix(const float rgb[3], bool dark) {
    const float luma[3] = {0.2126f, 0.7152f, 0.0722f};
    const float low = dark ? 1.f : 0.57f;
    ColorMatrix3x4 cm = {};
    for (int r = 0; r < 3; ++r) {
        for (int c = 0; c < 3; ++c) cm.m[r][c] = rgb[r] * (1.f - low) * luma[c];
        cm.m[r][3] = rgb[r] * low;
    }
    return cm;
}

void applyColorMatrix(const ColorMatrix3x4& cm, const float in[3], float out[3]) {
    for (int r = 0; r < 3; ++r) {
        out[r] = cm.m[r][0] * in[0] + cm.m[r][1] * in[1] + cm.m[r][2] * in[2] + cm.m[r][3];
    }
}

}
