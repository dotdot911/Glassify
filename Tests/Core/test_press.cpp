//
//  test_press.cpp
//  GlassifyTests
//
//  Copyright © 2026 Hung Phan.
//  See LICENSE file for license information.
//

#include <algorithm>

#include "glassify/press.h"
#include "test.h"

using namespace glassify;

namespace {
struct Sample { float t, scale, glow; };

// Runs a press at t = 0 and a release at `releaseAt`, sampling at 120 Hz.
std::vector<Sample> simulate(float w, float h, float releaseAt, float until) {
    PressModel m;
    m.configure(w, h);
    m.begin(w / 2, h / 2);
    std::vector<Sample> out;
    const float dt = 1.f / 120.f;
    bool released = false;
    for (float t = 0; t < until; t += dt) {
        if (!released && t >= releaseAt) { m.end(); released = true; }
        m.step(dt);
        out.push_back({t + dt, m.scale(), m.bigGlowAlpha()});
    }
    return out;
}

float at(const std::vector<Sample>& s, float t) {
    for (const Sample& x : s) if (x.t >= t) return x.scale;
    return s.back().scale;
}
float glowAt(const std::vector<Sample>& s, float t) {
    for (const Sample& x : s) if (x.t >= t) return x.glow;
    return s.back().glow;
}
}

TEST(spring_critically_damped_settles_without_overshoot) {
    Spring s{0.f, 0.f, 1.f, {1.f, 0.5f}};
    float peak = 0;
    for (int i = 0; i < 240; ++i) { s.step(1.f / 120.f); peak = std::max(peak, s.value); }
    CHECK(peak <= 1.0001f);
    CHECK(s.settled());
}

TEST(press_small_44_matches_measured_curve) {
    const auto s = simulate(44, 44, 1.5f, 2.6f);
    float peak = 0, trough = 10;
    for (const Sample& x : s) {
        if (x.t < 1.5f) peak = std::max(peak, x.scale);
        else trough = std::min(trough, x.scale);
    }
    CHECK_NEAR(peak, 1.392, 0.01, "press overshoot peak");
    CHECK_NEAR(at(s, 1.4f), 1.3636, 0.003, "hold");
    CHECK_NEAR(trough, 0.898, 0.02, "release undershoot");
    CHECK_NEAR(glowAt(s, 0.066f), 0.792, 0.08, "glow fade-in");
    CHECK_NEAR(glowAt(s, 1.501f + 0.148f), 0.509, 0.06, "glow fade-out");
}

TEST(press_spec_panel_171x110) {
    const PressSpec p = pressSpecFor(171, 110);
    CHECK_NEAR(p.liftPoints, 9.17, 0.01, "lift");
    CHECK_NEAR(p.bigGlowOpacity, 0.431, 0.002, "big glow");
    CHECK_NEAR(p.littleGlowOpacity, 0.243, 0.002, "little glow");
    CHECK_NEAR(p.littleGlowDiameter, 160, 1e-4, "little diameter");
}

namespace {
// Presses at `from`, moves the finger to `to` over 0.25 s and reads the settled transform.
struct Pulled { float scaleX, scaleY, tx, ty; };
Pulled pull(float w, float h, float fx, float fy, float tx, float ty) {
    PressModel m;
    m.configure(w, h);
    m.begin(fx, fy);
    const float dt = 1.f / 120.f;
    for (int i = 0; i < 72; ++i) m.step(dt);
    for (int i = 1; i <= 30; ++i) {
        const float a = i / 30.f;
        m.move(fx + (tx - fx) * a, fy + (ty - fy) * a);
        m.step(dt);
    }
    for (int i = 0; i < 240; ++i) m.step(dt);
    return {m.scaleX(), m.scaleY(), m.driftX() * m.scaleX(), m.driftY() * m.scaleY()};
}
}

TEST(press_drag_far_small_44) {
    const Pulled p = pull(44, 44, 22, 22, 172, 22);
    CHECK_NEAR(p.scaleX, 1.4302, 0.002, "stretched along the drag");
    CHECK_NEAR(p.scaleY, 1.2971, 0.002, "squashed across");
    CHECK_NEAR(p.tx, 4.22, 0.05, "drift");
    CHECK_NEAR(p.ty, 0.0, 1e-4, "no vertical drift");
}

TEST(press_drag_far_panel_171x110) {
    const Pulled p = pull(171, 110, 85.7f, 55, 85.7f, 205);
    CHECK_NEAR(p.scaleY, 1.0603, 0.0008, "stretched along the drag");
    CHECK_NEAR(p.scaleX, 1.0470, 0.0008, "squashed across");
    CHECK_NEAR(p.ty, 0.79, 0.03, "drift");
}

TEST(press_spec_ultra_small_below_120) {
    const PressSpec p = pressSpecFor(62, 62);
    CHECK_NEAR(p.liftPoints, 16, 1e-4, "lift");
    CHECK_NEAR(p.bigGlowOpacity, 1, 1e-4, "big glow");
    CHECK_NEAR(p.littleGlowOpacity, 1, 1e-4, "little glow");
    CHECK_NEAR(p.scaleDistanceThreshold, 2000, 1e-3, "threshold");
}

TEST(press_little_glow_dissipates_when_pulled) {
    PressModel m;
    m.configure(44, 44);
    m.begin(22, 22);
    for (int i = 0; i < 72; ++i) m.step(1.f / 120.f);
    CHECK_NEAR(m.littleGlowAlpha(), 1.0, 0.01, "held");
    m.move(122, 22);
    for (int i = 0; i < 120; ++i) m.step(1.f / 120.f);
    CHECK_NEAR(m.littleGlowAlpha(), 0.5, 0.01, "dissipated");
    CHECK_NEAR(m.littleGlowScale(), 2.0, 0.02, "dissipated scale");
}
