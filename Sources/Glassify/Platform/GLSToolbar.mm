//
//  GLSToolbar.mm
//  Glassify
//
//  Copyright © 2026 Hung Phan.
//  See LICENSE file for license information.
//

#import "Glassify/GLSToolbar.h"

#import "GLSBarButton.h"
#import "Glassify/GLSGlassContainerView.h"
#import "Glassify/GLSGlassView.h"
#import "Glassify/GLSScrollEdgeEffectView.h"

#include <algorithm>
#include <cmath>
#include <vector>

// Fixed spaces are taken as an 8 pt gap.
static constexpr CGFloat kHeight = 48, kInset = 5, kImageButton = 38, kTitlePad = 12, kFixedGap = 8;

@implementation GLSToolbar {
    GLSGlassContainerView *_group;
    NSArray<GLSGlassView *> *_platters;
    // Per platter: 0 no space, 1 fixed space, 2 flexible space before it.
    std::vector<int> _gapsBefore;
    int _trailingGap;
    __weak UIView *_backdropSourceView;
    __weak UIScrollView *_observed;
}

static void *kOffsetContext = &kOffsetContext;

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    _group = [[GLSGlassContainerView alloc] initWithFrame:self.bounds];
    _group.spacing = 12;
    _group.frost = GLSGlassFrostNone;
    _group.tracksBackdropMotion = YES;
    [self addSubview:_group];
    return self;
}

- (CGSize)sizeThatFits:(CGSize)size { return CGSizeMake(size.width, kHeight); }

- (void)dealloc {
    [_observed removeObserver:self forKeyPath:@"contentOffset" context:kOffsetContext];
    [_observed removeObserver:self forKeyPath:@"contentSize" context:kOffsetContext];
}

- (void)setScrollView:(UIScrollView *)scrollView {
    [_observed removeObserver:self forKeyPath:@"contentOffset" context:kOffsetContext];
    [_observed removeObserver:self forKeyPath:@"contentSize" context:kOffsetContext];
    _scrollView = scrollView;
    _observed = scrollView;
    [scrollView addObserver:self forKeyPath:@"contentOffset" options:0 context:kOffsetContext];
    [scrollView addObserver:self forKeyPath:@"contentSize" options:0 context:kOffsetContext];
    [self updateFrost];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change
                       context:(void *)context {
    if (context == kOffsetContext) [self updateFrost];
    else [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

- (void)setScrollEdgeEffect:(GLSScrollEdgeEffectView *)scrollEdgeEffect {
    _scrollEdgeEffect = scrollEdgeEffect;
    _group.scrollEdgeEffect = scrollEdgeEffect;
}

// The toolbar shows reduced frost only when no content remains under it.
- (void)updateFrost {
    UIScrollView *s = _scrollView;
    const BOOL under = !s || s.contentOffset.y + s.bounds.size.height - s.adjustedContentInset.bottom < s.contentSize.height;
    _group.frost = under ? GLSGlassFrostNone : GLSGlassFrostReduced;
}

- (UIView *)backdropSourceView { return _backdropSourceView; }
- (void)setBackdropSourceView:(UIView *)view {
    _backdropSourceView = view;
    _group.backdropSourceView = view ?: self.superview;
}

- (void)didMoveToSuperview {
    [super didMoveToSuperview];
    _group.backdropSourceView = _backdropSourceView ?: self.superview;
}

- (void)setItems:(NSArray<UIBarButtonItem *> *)items {
    _items = [items copy];
    for (UIView *p in _platters) [p removeFromSuperview];
    NSMutableArray<GLSGlassView *> *platters = [NSMutableArray array];
    _gapsBefore.clear();
    GLSGlassView *current = nil;
    int gap = 0;
    for (UIBarButtonItem *item in _items) {
        if (GLSBarButtonIsSpace(item)) {
            const BOOL flexible = GLSBarButtonSystemItem(item) == UIBarButtonSystemItemFlexibleSpace;
            gap = std::max(gap, flexible ? 2 : 1);
            current = nil;
            continue;
        }
        if (!current) {
            current = [GLSGlassView new];
            current.adaptsColorScheme = NO;
            current.contentVibrancyStyle = GLSContentVibrancyStyleControls;
            [_group addSubview:current];
            [platters addObject:current];
            _gapsBefore.push_back(gap);
            gap = 0;
        }
        GLSBarButton *b = [[GLSBarButton alloc] initWithItem:item];
        b.platter = current;
        b.highlightedAlpha = 0.70;
        [current.contentView addSubview:b];
    }
    _trailingGap = gap;
    _platters = platters;
    [self setNeedsLayout];
}

static CGFloat LayoutPlatter(GLSGlassView *platter) {
    CGFloat x = kInset;
    for (GLSBarButton *b in platter.contentView.subviews) {
        const CGFloat w = [b isTitle] ? std::ceil([b contentSize].width * 3) / 3 + 2 * kTitlePad : kImageButton;
        b.frame = CGRectMake(x, kInset, w, kHeight - 2 * kInset);
        b.contentCenter = CGPointMake(w / 2, kHeight / 2 - kInset);
        [b setNeedsLayout];
        x += w;
    }
    return std::max(x + kInset, kHeight);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _group.frame = self.bounds;
    std::vector<CGFloat> widths;
    CGFloat used = 0;
    int flexible = _trailingGap == 2 ? 1 : 0;
    for (NSUInteger i = 0; i < _platters.count; ++i) {
        widths.push_back(LayoutPlatter(_platters[i]));
        used += widths.back() + (_gapsBefore[i] == 1 ? kFixedGap : 0);
        if (_gapsBefore[i] == 2) ++flexible;
    }
    if (_trailingGap == 1) used += kFixedGap;
    const CGFloat flex = flexible ? std::max(self.bounds.size.width - used, CGFloat(0)) / flexible : 0;
    CGFloat x = 0;
    for (NSUInteger i = 0; i < _platters.count; ++i) {
        x += _gapsBefore[i] == 2 ? flex : _gapsBefore[i] == 1 ? kFixedGap : 0;
        GLSGlassView *p = _platters[i];
        const CGFloat px = std::round(x * 3) / 3;
        p.bounds = CGRectMake(0, 0, widths[i], kHeight);
        p.center = CGPointMake(px + widths[i] / 2, kHeight / 2);
        x += widths[i];
    }
}

@end
