//
//  test_laws.cpp
//  GlassifyTests
//
//  Copyright © 2026 Hung Phan.
//  See LICENSE file for license information.
//

#include <fstream>
#include <map>
#include <sstream>

#include "glassify/glass_inputs.h"
#include "glassify/pack.h"
#include "test.h"

using namespace glassify;

namespace {

std::vector<std::string> splitCsv(const std::string& line) {
    std::vector<std::string> out;
    std::string cur;
    bool quoted = false;
    for (char c : line) {
        if (c == '"') quoted = !quoted;
        else if (c == ',' && !quoted) { out.push_back(cur); cur.clear(); }
        else cur += c;
    }
    out.push_back(cur);
    return out;
}

// Parses sweep names such as "square_120", "clear_square_16" and "rect_w360_h44".
bool parseSize(const std::string& name, float& w, float& h, bool& clear) {
    clear = name.rfind("clear_", 0) == 0;
    int a = 0, b = 0;
    if (std::sscanf(name.c_str(), clear ? "clear_square_%d" : "square_%d", &a) == 1) { w = h = a; return true; }
    if (std::sscanf(name.c_str(), "rect_w%d_h%d", &a, &b) == 2) { w = a; h = b; return true; }
    if (std::sscanf(name.c_str(), "rect_h%d_w%d", &b, &a) == 2) { w = a; h = b; return true; }
    int r = 0;
    if (std::sscanf(name.c_str(), "radius_%d_%dx%d", &r, &a, &b) == 3) { w = a; h = b; return true; }
    return false;
}

void checkSweep(const char* file, Appearance appearance) {
    std::ifstream in(std::string(GLS_TEST_DATA) + "/" + file);
    CHECK(in.good());
    std::string line;
    std::getline(in, line);
    const std::vector<std::string> header = splitCsv(line);
    int rows = 0;
    while (std::getline(in, line)) {
        const std::vector<std::string> cells = splitCsv(line);
        std::map<std::string, std::string> row;
        for (size_t i = 0; i < header.size() && i < cells.size(); ++i) row[header[i]] = cells[i];
        float w, h;
        bool clear;
        if (!parseSize(row["name"], w, h, clear)) continue;
        ++rows;
        const GlassInputs g = glassInputsFor(clear ? GlassStyle::Clear : GlassStyle::Regular, appearance, w, h);
        const float s = std::min(w, h);
        const std::string ctx = row["name"] + " " + file;
        auto num = [&](const char* key, float actual) {
            const std::string& v = row[key];
            if (v.empty()) return;
            CHECK_NEAR(actual, std::stod(v), 2e-3, ctx + " " + key);
        };
        num("bd.scale", g.backdropScale);
        if (!clear) num("bd.marginWidth", g.marginWidth);
        num("SDF.e.keySpread", g.highlightSpread);
        num("inputBleedAmount", g.bleedAmount);
        num("inputBleedHeight", g.bleedHeight);
        num("inputBleedBlurRadius", g.bleedBlurRadius);
        num("inputBleedOpacity", g.bleedOpacity);
        num("inputBleedColorMatrixBlack", g.bleed.black);
        num("inputBlurDistance0", g.blurDistance[0]);
        num("inputBlurRadius", g.blurRadius);
        num("inputInnerRefractionAmount", g.innerRefractionAmount);
        num("inputInnerRefractionHeight", g.innerRefractionHeight);
        num("inputOuterRefractionAmount", g.outerRefractionAmount);
        num("inputOuterRefractionHeight", g.outerRefractionHeight);
        num("inputRefractionOpacity", g.refractionOpacity);
        num("inputSDRShadowOpacity", g.sdrShadowOpacity);
        num("inputShadowAmount", g.shadowAmount);
        num("inputShadowBlurRadius", g.shadowBlurRadius);
        num("inputShadowHeight", g.shadowHeight);
        num("inputShadowOpacity", g.shadowOpacity);
        num("inputShadowRadius", g.shadowRadius);
        num("inputShadowVibrancyContribution", g.shadowVibrancyContribution);
        num("inputShadowColorMatrixSaturation", g.shadow.saturation);
        num("inputClamp", g.clamp > 0 && s <= 64 && !clear ? std::stof(row["inputClamp"]) : g.clamp);
        if (clear || s > 64) {
            num("inputFaceColorMatrixWhite", g.face.white);
            num("inputFaceColorMatrixBlack", g.face.black);
            num("inputFaceColorMatrixSaturation", g.face.saturation);
        }
    }
    CHECK(rows == 111);
}

}

TEST(laws_match_light_sweep) { checkSweep("sweep_light.csv", Appearance::Light); }
TEST(laws_match_dark_sweep) { checkSweep("sweep_dark.csv", Appearance::Dark); }

TEST(laws_regular_171x110_light_exact) {
    const GlassInputs g = glassInputsFor(GlassStyle::Regular, Appearance::Light, 171, 110);
    CHECK_NEAR(g.blurRadius, 2.809524, 1e-5, "blur");
    CHECK_NEAR(g.shadowOpacity, 0.361607, 1e-5, "shadow opacity");
    CHECK_NEAR(g.bleedOpacity, 0.239583, 1e-5, "bleed opacity");
    CHECK_NEAR(g.marginWidth, 76.75, 1e-5, "margin");
    CHECK_NEAR(g.shadowVibrancyContribution, 0.479167, 1e-5, "contribution");
}

TEST(lerp_endpoints_and_midpoint) {
    const GlassInputs a = glassInputsFor(GlassStyle::Regular, Appearance::Light, 100, 44);
    const GlassInputs b = glassInputsFor(GlassStyle::Regular, Appearance::Light, 200, 200);
    CHECK_NEAR(lerp(a, b, 0).blurRadius, a.blurRadius, 1e-6, "t=0");
    CHECK_NEAR(lerp(a, b, 1).blurRadius, b.blurRadius, 1e-6, "t=1");
    CHECK_NEAR(lerp(a, b, 0.5f).shadowAmount, 0.5 * (a.shadowAmount + b.shadowAmount), 1e-6, "mid");
}

TEST(identity_glass_matches_materialize_from_values) {
    const GlassInputs g = glassInputsFor(GlassStyle::Regular, Appearance::Light, 171, 110);
    const GlassInputs id = identityGlassLike(g);
    CHECK_NEAR(id.blurRadius, 0, 1e-6, "blur");
    CHECK_NEAR(id.innerRefractionAmount, 0, 1e-6, "inner");
    CHECK_NEAR(id.shadowOpacity, 0, 1e-6, "shadow");
    CHECK_NEAR(id.faceOpacity, 0, 1e-6, "face opacity");
    CHECK_NEAR(id.face.white, 1, 1e-6, "face white");
    CHECK_NEAR(id.face.fill[3], 0, 1e-6, "face fill alpha");
    CHECK_NEAR(id.clamp, 1, 1e-6, "clamp");
    CHECK_NEAR(id.maxHeadroom, 1.2, 1e-6, "headroom");
    CHECK_NEAR(id.backdropScale, 1, 1e-6, "backdrop scale");
    CHECK_NEAR(id.highlightOpacity, 0, 1e-6, "highlight");
    const GlassInputs m = lerp(id, g, 1.61f / 2.809524f);
    CHECK_NEAR(m.innerRefractionAmount, -34.3, 0.2, "inner at blur 1.61");
    CHECK_NEAR(m.backdropScale, 0.571, 0.01, "backdrop scale at blur 1.61");
}

TEST(laws_small_light_adaptive_matches_probe_e1) {
    const GlassInputs g = glassInputsFor(GlassStyle::Regular, Appearance::Light, 44, 44, 0.4525f);
    CHECK_NEAR(g.face.white, 0.901613, 3e-3, "white");
    CHECK_NEAR(g.face.black, 0.301613, 3e-3, "black");
    CHECK_NEAR(g.face.fill[3], 0.5242, 3e-3, "fill alpha");
    CHECK_NEAR(g.shadow.fill[3], 0.2887, 3e-3, "shadow fill alpha");
}

TEST(laws_frost_none_matches_tab_bar_over_scroll_pocket) {
    const GlassInputs d = glassInputsFor(GlassStyle::Regular, Appearance::Dark, 290, 62, 1.f / 31.f, Frost::None);
    CHECK_NEAR(d.blurRadius, 0, 1e-6, "dark blur");
    for (int i = 0; i < 4; ++i) CHECK_NEAR(d.blurOpacity[i], 0, 1e-6, "dark blur opacity");
    CHECK_NEAR(d.face.black, 0.1, 1e-6, "dark black");
    CHECK_NEAR(d.face.white, 0.482258, 1e-5, "dark white");
    CHECK_NEAR(d.face.saturation, 1.3, 1e-6, "dark sat");
    CHECK_NEAR(d.face.fill[3], 0, 1e-6, "dark fill");
    const GlassInputs l = glassInputsFor(GlassStyle::Regular, Appearance::Light, 290, 62, 1.f, Frost::None);
    CHECK_NEAR(l.face.black, 0.8, 1e-6, "light black");
    CHECK_NEAR(l.face.white, 1.03, 1e-6, "light white");
    CHECK_NEAR(l.face.saturation, 1.1, 1e-6, "light sat");
    CHECK_NEAR(l.face.fill[3], 0, 1e-6, "light fill");
    const GlassInputs a = glassInputsFor(GlassStyle::Regular, Appearance::Light, 290, 62, 1.f);
    CHECK_NEAR(a.face.black, 0.85, 1e-6, "automatic light black");
    CHECK_NEAR(a.blurRadius, 1.666667, 1e-4, "automatic blur");
}

TEST(laws_frost_reduced_matches_navigation_bar) {
    const GlassInputs g = glassInputsFor(GlassStyle::Regular, Appearance::Light, 44, 44, 1.f, Frost::Reduced);
    CHECK_NEAR(g.blurRadius, 0.666667, 1e-5, "blur");
    CHECK_NEAR(g.blurOpacity[0], 1, 1e-6, "blur opacity 0");
    CHECK_NEAR(g.blurOpacity[1], 0.5, 1e-6, "blur opacity 1");
    CHECK_NEAR(g.backdropScale, 0.5, 1e-6, "scale");
    CHECK_NEAR(g.clamp, 1.06961, 1e-5, "clamp");
    CHECK_NEAR(g.face.black, 0.8, 1e-6, "black");
    CHECK_NEAR(g.face.white, 1.03, 1e-6, "white");
    CHECK_NEAR(g.face.saturation, 1.1, 1e-6, "sat");
    CHECK_NEAR(g.face.fill[3], 0, 1e-6, "fill");
    CHECK_NEAR(g.shadow.fill[3], 0.05, 1e-4, "shadow fill");
    CHECK_NEAR(g.innerRefractionAmount, -35.2, 1e-4, "inner amount");
    CHECK_NEAR(g.bleedAmount, 15.4, 1e-4, "bleed");
    CHECK_NEAR(g.marginWidth, 8.8, 1e-4, "margin");
    CHECK_NEAR(glassInputsFor(GlassStyle::Clear, Appearance::Light, 44, 44).clamp, 1.375824, 1e-5, "clear clamp");
    CHECK_NEAR(glassInputsFor(GlassStyle::Regular, Appearance::Dark, 200, 200).clamp, 1, 1e-6, "dark clamp");
    CHECK_NEAR(glassInputsFor(GlassStyle::Regular, Appearance::Light, 44, 44, 0.1f).clamp, 1, 1e-6, "small dark backdrop clamp");
}

TEST(adaptive_appearance_hysteresis) {
    CHECK(adaptAppearance(Appearance::Light, 0.0f) == Appearance::Dark);
    CHECK(adaptAppearance(Appearance::Light, 0.1f) == Appearance::Dark);
    CHECK(adaptAppearance(Appearance::Light, 0.25f) == Appearance::Light);
    CHECK(adaptAppearance(Appearance::Light, 1.0f) == Appearance::Light);
    CHECK(adaptAppearance(Appearance::Dark, 0.75f) == Appearance::Dark);
    CHECK(adaptAppearance(Appearance::Dark, 0.95f) == Appearance::Light);
    CHECK(adaptAppearance(Appearance::Dark, 0.3f) == Appearance::Dark);
    CHECK(adaptAppearance(Appearance::Dark, -1.f) == Appearance::Dark);
}

TEST(liquid_lens_content_warp_follows_lift) {
    CHECK_NEAR(liquidLensInputs(1.f).contentWarpAmount, -17.5, 1e-6, "lifted");
    CHECK_NEAR(liquidLensInputs(0.5f).contentWarpAmount, -8.75, 1e-6, "half way");
    CHECK_NEAR(liquidLensInputs(0.f).contentWarpAmount, 0.0, 1e-6, "resting");
    CHECK_NEAR(liquidLensInputs(0.5f).warpAmount, 4.5, 1e-6, "below-glass warp 9 p");
}

TEST(liquid_lens_inner_shadow) {
    const GlassInputs g = liquidLensInputs(0.5f);
    CHECK_NEAR(g.innerShadowOpacity, 0.06, 1e-6, "opacity 0.12 p");
    CHECK_NEAR(g.innerShadowOffset[1], 3.5, 1e-6, "offset 7 p");
    GLSGlassUniforms u{};
    packUniforms(liquidLensInputs(1.f), PackContext{}, u);
    CHECK_NEAR(u.innerShadow.x, 0.12, 1e-6, "packed opacity");
    CHECK_NEAR(u.innerShadow.z, 7.0, 1e-6, "packed offset y");
    CHECK_NEAR(u.innerShadow.w, 1.0 / (3.0 * 1.41421356), 1e-5, "1 / (sigma sqrt 2), sigma = radius");
    CHECK_NEAR(u.content3.x, -17.5, 1e-6, "content lensing amount");
    CHECK_NEAR(u.content3.y, 1.0 / 14.0, 1e-6, "content lensing 1 / height");
}
