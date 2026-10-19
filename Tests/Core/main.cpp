//
//  main.cpp
//  GlassifyTests
//
//  Copyright © 2026 Hung Phan.
//  See LICENSE file for license information.
//

#include "test.h"

namespace gls_test {
std::vector<Case>& registry() { static std::vector<Case> r; return r; }
int failures = 0;
}

int main() {
    for (auto& c : gls_test::registry()) {
        const int before = gls_test::failures;
        c.fn();
        std::printf("%s %s\n", gls_test::failures == before ? "ok  " : "FAIL", c.name);
    }
    std::printf("%d failure(s)\n", gls_test::failures);
    return gls_test::failures == 0 ? 0 : 1;
}
