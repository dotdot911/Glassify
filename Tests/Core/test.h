//
//  test.h
//  GlassifyTests
//
//  Copyright © 2026 Hung Phan.
//  See LICENSE file for license information.
//

#pragma once

#include <cmath>
#include <cstdio>
#include <functional>
#include <string>
#include <vector>

namespace gls_test {
struct Case { const char* name; std::function<void()> fn; };
std::vector<Case>& registry();
extern int failures;
struct Register { Register(const char* n, std::function<void()> f) { registry().push_back({n, f}); } };
}

#define TEST(name) \
    static void name(); \
    static gls_test::Register reg_##name(#name, name); \
    static void name()

#define CHECK(cond) \
    do { if (!(cond)) { ++gls_test::failures; std::printf("  FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); } } while (0)

#define CHECK_NEAR(a, b, tol, ctx) \
    do { double a_ = (a), b_ = (b); \
         if (!(std::fabs(a_ - b_) <= (tol) * std::fmax(1.0, std::fabs(b_)))) { ++gls_test::failures; \
             std::printf("  FAIL %s:%d: %s = %g, expected %g (%s)\n", __FILE__, __LINE__, #a, a_, b_, std::string(ctx).c_str()); } } while (0)
