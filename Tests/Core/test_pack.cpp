//
//  test_pack.cpp
//  GlassifyTests
//
//  Copyright © 2026 Hung Phan.
//  See LICENSE file for license information.
//

#include "glassify/color_matrix.h"
#include "glassify/pack.h"
#include "test.h"

using namespace glassify;

TEST(supercircle_blend_limits) {
    CHECK_NEAR(supercircleBlend(100, 28), 0, 1e-6, "large rect");
    CHECK_NEAR(supercircleBlend(22, 22), 1, 1e-6, "capsule");
    CHECK_NEAR(supercircleBlend(1.5286649f * 10, 10), 0, 1e-5, "threshold");
}

TEST(vibrant_matrix_matches_runtime_dump) {
    const ColorMatrix3x4 m = vibrantMatrix(1.5f, 1.4f, 0.9f);
    CHECK_NEAR(m.m[0][0], 1.2024, 2e-3, "r.r");
    CHECK_NEAR(m.m[0][1], -1.0014, 2e-3, "r.g");
    CHECK_NEAR(m.m[0][2], -0.1010, 2e-3, "r.b");
    CHECK_NEAR(m.m[0][3], 0.9, 1e-6, "r.offset");
}

TEST(pack_light_direction_compass) {
    GlassInputs g = glassInputsFor(GlassStyle::Regular, Appearance::Light, 171, 110);
    PackContext ctx;
    GLSGlassUniforms u;
    packUniforms(g, ctx, u);
    CHECK_NEAR(u.hlKey.x, -0.70710678, 1e-5, "key x");
    CHECK_NEAR(u.hlKey.y, -0.70710678, 1e-5, "key y");
    CHECK_NEAR(u.hlFill.x, 0.70710678, 1e-5, "fill x");
    CHECK_NEAR(u.hlFill.y, 0.70710678, 1e-5, "fill y");
    CHECK_NEAR(u.hlKey.w, 0, 1e-6, "amount 0.5 → linear bias");
}

TEST(pack_elements_capsule) {
    ShapeElement e{50, 50, 44, 44, 22};
    PackContext ctx;
    ctx.elements = &e;
    ctx.elementCount = 1;
    GLSElement out[GLS_MAX_ELEMENTS];
    CHECK(packElements(ctx, out) == 1);
    CHECK_NEAR(out[0].rect.z, 22, 1e-6, "half width");
    CHECK_NEAR(out[0].corner.y, 1, 1e-6, "circular x");
}

TEST(ycc_composite_light_face) {
    ColorMatrixParams p;
    p.white = 1.03f; p.black = 0.5f; p.saturation = 1.f;
    p.fill[0] = p.fill[1] = p.fill[2] = 1.f; p.fill[3] = 0.4f;
    const ColorMatrix3x4 m = yccComposite(p);
    CHECK_NEAR(m.m[0][0], 0.6 - 0.282 * 0.2126, 1e-5, "r.r");
    CHECK_NEAR(m.m[0][1], -0.282 * 0.7152, 1e-5, "r.g");
    CHECK_NEAR(m.m[2][2], 0.6 - 0.282 * 0.0722, 1e-5, "b.b");
    CHECK_NEAR(m.m[1][3], 0.7, 1e-5, "offset");
    const float grey[3] = {0.5f, 0.5f, 0.5f};
    float out[3];
    applyColorMatrix(m, grey, out);
    CHECK_NEAR(out[1], 0.6 * 0.5 - 0.282 * 0.5 + 0.7, 1e-5, "grey");
}

TEST(ycc_composite_identity) {
    const ColorMatrix3x4 m = yccComposite(ColorMatrixParams{});
    for (int r = 0; r < 3; ++r)
        for (int c = 0; c < 4; ++c) CHECK_NEAR(m.m[r][c], r == c ? 1.0 : 0.0, 1e-6, "identity");
}

TEST(little_glow_matrix_follows_pocket_luma) {
    GLSGlassUniforms u{};
    GlowState g;
    g.dark = true;
    packGlow(g, u);
    CHECK_NEAR(u.littleGlowCM[0].x, 9.2914, 2e-3, "dark nil r.r");
    CHECK_NEAR(u.littleGlowCM[0].y, -2.3847, 2e-3, "dark nil r.g");
    g.luma = 1.f / 31.f;
    packGlow(g, u);
    CHECK_NEAR(u.littleGlowCM[0].x, 12.7996, 5e-3, "dark 1/31 r.r");
    CHECK_NEAR(u.littleGlowCM[0].y, -3.2851, 5e-3, "dark 1/31 r.g");
    g = GlowState{};
    packGlow(g, u);
    CHECK_NEAR(u.littleGlowCM[1].y, 2.7273 * (1 - 0.7152 / 3), 2e-3, "light nil g.g");
}
