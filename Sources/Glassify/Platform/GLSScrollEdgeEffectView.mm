//
//  GLSScrollEdgeEffectView.mm
//  Glassify
//
//  Copyright © 2026 Hung Phan.
//  See LICENSE file for license information.
//

#import "Glassify/GLSScrollEdgeEffectView.h"
#import "GLSScrollEdgeEffectViewInternal.h"

#include <algorithm>
#include <cmath>

// How far the effect view reaches past the bar edge.
static constexpr CGFloat kReach = 64.8;

@implementation GLSScrollEdgeEffectView {
    CAGradientLayer *_mask;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.userInteractionEnabled = NO;
    _barHeight = 48;
    self.backgroundColor = [UIColor.systemBackgroundColor colorWithAlphaComponent:0.85];
    _mask = [CAGradientLayer layer];
    self.layer.mask = _mask;
    return self;
}

- (void)setEdge:(GLSScrollEdge)edge {
    _edge = edge;
    [self updateFrame];
}

- (void)setBarEdge:(CGFloat)barEdge {
    _barEdge = barEdge;
    [self updateFrame];
}

- (CGRect)lumaRect {
    const CGFloat w = self.superview.bounds.size.width;
    return _edge == GLSScrollEdgeTop ? CGRectMake(0, _barEdge - 44, w, 44) : CGRectMake(0, _barEdge, w, _barHeight);
}

- (void)didMoveToSuperview {
    [super didMoveToSuperview];
    [self updateFrame];
}

- (void)updateFrame {
    UIView *s = self.superview;
    if (!s) return;
    const CGFloat w = s.bounds.size.width;
    if (_edge == GLSScrollEdgeTop) {
        self.frame = CGRectMake(0, 0, w, _barEdge + kReach);
    } else {
        const CGFloat top = _barEdge - kReach;
        self.frame = CGRectMake(0, top, w, std::max(s.bounds.size.height - top, CGFloat(0)));
    }
    [self setNeedsLayout];
}

- (void)maskY0:(CGFloat *)y0 y1:(CGFloat *)y1 sigma:(CGFloat *)sigma {
    const BOOL top = _edge == GLSScrollEdgeTop;
    *sigma = top ? 18 : 24;
    *y0 = top ? -1e4 : kReach + 10;
    *y1 = top ? _barEdge - self.frame.origin.y : 1e4;
}

- (GLSBackdropVeil)gls_veilInView:(UIView *)source {
    GLSBackdropVeil v = {};
    if (!source || !self.superview || self.hidden) return v;
    const CGRect r = [self convertRect:self.bounds toView:source];
    CGFloat y0, y1, sigma, red, green, blue, alpha;
    [self maskY0:&y0 y1:&y1 sigma:&sigma];
    if (![[self.backgroundColor resolvedColorWithTraitCollection:self.traitCollection] getRed:&red green:&green
                                                                                          blue:&blue alpha:&alpha])
        return v;
    v.on = YES;
    v.top = CGRectGetMinY(r);
    v.bottom = CGRectGetMaxY(r);
    v.y0 = y0 + v.top;
    v.y1 = y1 + v.top;
    v.sigma = sigma;
    v.color[0] = float(red); v.color[1] = float(green); v.color[2] = float(blue); v.color[3] = float(alpha * self.alpha);
    return v;
}

// UIKit masks with a shadow layer, which renders empty in -renderInContext:, so the same profile is a gradient.
- (void)layoutSubviews {
    [super layoutSubviews];
    const CGFloat height = self.bounds.size.height;
    if (height <= 0) return;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _mask.frame = self.bounds;
    CGFloat y0, y1, sigma;
    [self maskY0:&y0 y1:&y1 sigma:&sigma];
    constexpr int n = 97;
    NSMutableArray *colors = [NSMutableArray arrayWithCapacity:n];
    NSMutableArray<NSNumber *> *locations = [NSMutableArray arrayWithCapacity:n];
    auto phi = [](CGFloat z) { return 0.5 * (1 + std::erf(z / std::sqrt(2.0))); };
    for (int i = 0; i < n; ++i) {
        const CGFloat u = CGFloat(i) / (n - 1), y = u * height;
        const CGFloat a = phi((y - y0) / sigma) - phi((y - y1) / sigma);
        [colors addObject:(id)[UIColor colorWithWhite:0 alpha:a].CGColor];
        [locations addObject:@(u)];
    }
    _mask.colors = colors;
    _mask.locations = locations;
    [CATransaction commit];
}

- (void)gls_matchBackgroundOf:(UIView *)view {
    UIColor *color = nil;
    for (UIView *v = view; v && !color; v = v.superview) {
        UIColor *background = [v.backgroundColor resolvedColorWithTraitCollection:v.traitCollection];
        CGFloat alpha = 0;
        if (background && [background getWhite:nullptr alpha:&alpha] && alpha >= 1) color = v.backgroundColor;
    }
    self.backgroundColor = [color ?: UIColor.systemBackgroundColor colorWithAlphaComponent:0.85];
}

@end
