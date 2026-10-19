//
//  press.h
//  Glassify
//
//  Copyright © 2026 Hung Phan.
//  See LICENSE file for license information.
//

#pragma once

#include <algorithm>

namespace glassify {

// stiffness = (2π/response)², damping = 4π·ζ/response, mass 1.
struct SpringParams {
    float dampingRatio = 1.f;
    float response = 0.5f;
};

struct Spring {
    float value = 0.f;
    float velocity = 0.f;
    float target = 0.f;
    SpringParams params;

    // Closed-form, so stable for any dt.
    void step(float dt);
    bool settled(float epsilon = 1e-4f) const;
};

// Springs scale with the long side, the other fields with the short side.
struct PressSpec {
    // The larger side grows by this much.
    float liftPoints = 0;
    float bigGlowOpacity = 0;
    float littleGlowOpacity = 0;
    float littleGlowDiameter = 0;
    // Points of pull per unit of stretch.
    float scaleDistanceThreshold = 0;
    // The pull from the touch-down point past which the little glow dissipates.
    float littleGlowDissipationDistance = 50;
    SpringParams pressSpring;
    SpringParams releaseSpring;
};

PressSpec pressSpecFor(float width, float height);

class PressModel {
public:
    void configure(float width, float height);
    void begin(float x, float y);
    void move(float x, float y);
    void end();
    void step(float dt);
    // Whether anything is still moving or visible.
    bool active() const;

    // The layer transform is scale(scaleX, scaleY) · translate(driftX, driftY).
    float scale() const { return scaleX_.value; }
    float scaleX() const { return scaleX_.value; }
    float scaleY() const { return scaleY_.value; }
    float driftX() const { return driftX_.value; }
    float driftY() const { return driftY_.value; }
    float bigGlowAlpha() const { return glow_.value * spec_.bigGlowOpacity; }
    float littleGlowAlpha() const { return glow_.value * spec_.littleGlowOpacity * (1.f - 0.5f * dissipate_.value); }
    // 1 while held, 2 once pulled past the dissipation distance, 4 after release.
    float littleGlowScale() const { return std::max(littleScale_, 1.f + dissipate_.value); }
    float glowX() const { return glowX_; }
    float glowY() const { return glowY_; }
    const PressSpec& spec() const { return spec_; }

private:
    PressSpec spec_;
    float width_ = 0, height_ = 0;
    void retarget();
    Spring scaleX_{1.f, 0.f, 1.f, {}}, scaleY_{1.f, 0.f, 1.f, {}};
    Spring driftX_{0.f, 0.f, 0.f, {}}, driftY_{0.f, 0.f, 0.f, {}};
    float startX_ = 0, startY_ = 0;
    float touchX_ = 0, touchY_ = 0;
    Spring glow_{0.f, 0.f, 0.f, {}};
    float glowPeak_ = 0.f;
    float littleScale_ = 1.f;
    Spring dissipate_{0.f, 0.f, 0.f, {1.f, 0.44f}};
    float glowX_ = 0, glowY_ = 0;
    bool down_ = false;
};

}
