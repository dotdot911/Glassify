//
//  press.cpp
//  Glassify
//
//  Copyright © 2026 Hung Phan.
//  See LICENSE file for license information.
//

#include "glassify/press.h"

#include <algorithm>
#include <cmath>

namespace glassify {
namespace {

constexpr float kTwoPi = 6.28318530718f;

float mixf(float a, float b, float t) { return a + (b - a) * t; }
float clampf(float x, float lo, float hi) { return std::min(std::max(x, lo), hi); }

// The glow fade springs, critically damped.
constexpr SpringParams kGlowIn{1.f, 0.16f};
constexpr SpringParams kGlowOut{1.f, 0.55f};

}

void Spring::step(float dt) {
    if (dt <= 0.f) return;
    const float omega = kTwoPi / std::max(params.response, 1e-4f);
    const float zeta = std::max(params.dampingRatio, 0.f);
    const float x0 = value - target;
    const float v0 = velocity;
    float x, v;
    if (zeta < 1.f - 1e-4f) {
        const float wd = omega * std::sqrt(1.f - zeta * zeta);
        const float e = std::exp(-zeta * omega * dt);
        const float c = std::cos(wd * dt), s = std::sin(wd * dt);
        const float b = (v0 + zeta * omega * x0) / wd;
        x = e * (x0 * c + b * s);
        v = e * (-zeta * omega * (x0 * c + b * s) + wd * (b * c - x0 * s));
    } else if (zeta > 1.f + 1e-4f) {
        const float r = omega * std::sqrt(zeta * zeta - 1.f);
        const float r1 = -zeta * omega + r, r2 = -zeta * omega - r;
        const float c2 = (v0 - r1 * x0) / (r2 - r1);
        const float c1 = x0 - c2;
        const float e1 = std::exp(r1 * dt), e2 = std::exp(r2 * dt);
        x = c1 * e1 + c2 * e2;
        v = c1 * r1 * e1 + c2 * r2 * e2;
    } else {
        const float e = std::exp(-omega * dt);
        const float b = v0 + omega * x0;
        x = (x0 + b * dt) * e;
        v = (b - omega * (x0 + b * dt)) * e;
    }
    value = target + x;
    velocity = v;
}

bool Spring::settled(float epsilon) const {
    return std::fabs(value - target) < epsilon && std::fabs(velocity) < epsilon * 10.f;
}

PressSpec pressSpecFor(float width, float height) {
    const float minSide = std::min(width, height), maxSide = std::max(width, height);
    PressSpec s;
    s.littleGlowDiameter = std::min(1.5f * minSide, 160.f);
    if (maxSide < 120.f) {
        s.liftPoints = 16.f;
        s.bigGlowOpacity = 1.f;
        s.littleGlowOpacity = 1.f;
        s.scaleDistanceThreshold = 2000.f;
        s.pressSpring = {0.625f, 0.262f};
        s.releaseSpring = {0.375f, 0.4f};
        return s;
    }
    const float tMin = clampf((minSide - 44.f) / (160.f - 44.f), 0.f, 1.f);
    const float tMax = clampf((maxSide - 44.f) / (160.f - 44.f), 0.f, 1.f);
    s.liftPoints = mixf(16.f, 4.f, tMin);
    s.bigGlowOpacity = mixf(1.f, 0.f, tMin);
    s.littleGlowOpacity = mixf(0.3f, 0.2f, tMin);
    s.scaleDistanceThreshold = mixf(6000.f, 24000.f, tMin);
    s.pressSpring = {mixf(0.625f, 0.625f, tMax), mixf(0.262f, 0.314f, tMax)};
    s.releaseSpring = {mixf(0.375f, 0.6f, tMax), mixf(0.4f, 0.36f, tMax)};
    return s;
}

void PressModel::configure(float width, float height) {
    width_ = width;
    height_ = height;
    spec_ = pressSpecFor(width, height);
}

void PressModel::begin(float x, float y) {
    down_ = true;
    littleScale_ = 1.f;
    startX_ = touchX_ = x;
    startY_ = touchY_ = y;
    dissipate_.value = dissipate_.velocity = dissipate_.target = 0.f;
    glowX_ = clampf(x, 0.f, width_);
    glowY_ = clampf(y, 0.f, height_);
    glow_.params = kGlowIn;
    glow_.target = 1.f;
    retarget();
}

void PressModel::move(float x, float y) {
    touchX_ = x;
    touchY_ = y;
    if (down_) {
        const float d = std::hypot(x - startX_, y - startY_);
        dissipate_.target = d > spec_.littleGlowDissipationDistance ? 1.f : 0.f;
    }
    glowX_ = clampf(x, 0.f, width_);
    glowY_ = clampf(y, 0.f, height_);
    if (down_) retarget();
}

// Pulling stretches the glass along the pull, squashes it across and drifts it towards the finger.
void PressModel::retarget() {
    const float maxSide = std::max(std::max(width_, height_), 1.f);
    float sx = 1.f, sy = 1.f, dx = 0.f, dy = 0.f;
    if (down_) {
        const float lift = (maxSide + spec_.liftPoints) / maxSide;
        sx = sy = lift;
        const float m = std::max(spec_.scaleDistanceThreshold, 1.f);
        const float tx = touchX_ - startX_, ty = touchY_ - startY_;
        if (tx != 0.f) {
            const float ix = std::fabs(glowX_ - startX_);
            const float k = ix / (4.f * m) + (std::fabs(tx) - ix) / m;
            sx += k;
            sy -= k;
            dx = width_ * k * (tx < 0 ? -1.f : 1.f);
        }
        if (ty != 0.f) {
            const float iy = std::fabs(glowY_ - startY_);
            const float k = iy / (4.f * m) + (std::fabs(ty) - iy) / m;
            sx -= k;
            sy += k;
            dy = height_ * k * (ty < 0 ? -1.f : 1.f);
        }
    }
    const SpringParams params = down_ ? spec_.pressSpring : spec_.releaseSpring;
    for (Spring* s : {&scaleX_, &scaleY_, &driftX_, &driftY_}) s->params = params;
    scaleX_.target = sx;
    scaleY_.target = sy;
    driftX_.target = dx;
    driftY_.target = dy;
}

void PressModel::end() {
    if (!down_) return;
    down_ = false;
    retarget();
    glow_.params = kGlowOut;
    glow_.target = 0.f;
    glowPeak_ = std::max(glow_.value, 1e-3f);
}

void PressModel::step(float dt) {
    for (Spring* s : {&scaleX_, &scaleY_, &driftX_, &driftY_}) s->step(dt);
    glow_.step(dt);
    glow_.value = clampf(glow_.value, 0.f, 1.f);
    dissipate_.step(dt);
    if (!down_) littleScale_ = 1.f + 3.f * clampf(1.f - glow_.value / glowPeak_, 0.f, 1.f);
}

bool PressModel::active() const {
    return down_ || !scaleX_.settled() || !scaleY_.settled() || !driftX_.settled(1e-3f) || !driftY_.settled(1e-3f) ||
           glow_.value > 1e-3f;
}

}
