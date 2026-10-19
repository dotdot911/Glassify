//
//  GLSNavigationBar.mm
//  Glassify
//
//  Copyright © 2026 Hung Phan.
//  See LICENSE file for license information.
//

#import "Glassify/GLSNavigationBar.h"

#import "GLSBarButton.h"
#import "Glassify/GLSGlassContainerView.h"
#import "Glassify/GLSGlassView.h"
#import "Glassify/GLSScrollEdgeEffectView.h"

#include <algorithm>
#include <cmath>

static constexpr CGFloat kPlatterHeight = 44, kMargin = 16, kItemInset = 4, kItemGap = 16, kItemPad = 14;

@implementation GLSNavigationBar {
    GLSGlassContainerView *_group;
    UILabel *_titleLabel;
    GLSGlassView *_backPlatter;
    NSArray<GLSGlassView *> *_leftPlatters, *_rightPlatters;
    __weak UIView *_backdropSourceView;
    __weak UIScrollView *_observed;
}

static void *kOffsetContext = &kOffsetContext;

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    _group = [[GLSGlassContainerView alloc] initWithFrame:self.bounds];
    _group.spacing = 12;
    _group.frost = GLSGlassFrostReduced;
    _group.tracksBackdropMotion = YES;
    [self addSubview:_group];
    _titleLabel = [UILabel new];
    _titleLabel.font = [UIFont fontWithDescriptor:[[UIFontDescriptor preferredFontDescriptorWithTextStyle:UIFontTextStyleHeadline]
                                                      fontDescriptorWithSymbolicTraits:UIFontDescriptorTraitBold]
                                             size:0];
    _titleLabel.textColor = UIColor.labelColor;
    _titleLabel.textAlignment = NSTextAlignmentCenter;
    [self addSubview:_titleLabel];
    return self;
}

- (CGSize)sizeThatFits:(CGSize)size { return CGSizeMake(size.width, 54); }

- (void)dealloc {
    [_observed removeObserver:self forKeyPath:@"contentOffset" context:kOffsetContext];
}

- (void)setScrollView:(UIScrollView *)scrollView {
    [_observed removeObserver:self forKeyPath:@"contentOffset" context:kOffsetContext];
    _scrollView = scrollView;
    _observed = scrollView;
    [scrollView addObserver:self forKeyPath:@"contentOffset" options:0 context:kOffsetContext];
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

// Frost is reduced at rest and drops to none as soon as content scrolls under the bar.
- (void)updateFrost {
    UIScrollView *s = _scrollView;
    const BOOL under = s && s.contentOffset.y > -s.adjustedContentInset.top;
    _group.frost = under ? GLSGlassFrostNone : GLSGlassFrostReduced;
}

- (void)setTitle:(NSString *)title {
    _title = [title copy];
    _titleLabel.text = title;
    [self setNeedsLayout];
}

- (void)setTitleView:(UIView *)titleView {
    if (titleView == _titleView) return;
    if (_titleView.superview == self) [_titleView removeFromSuperview];
    _titleView = titleView;
    if (titleView) [self addSubview:titleView];
    _titleLabel.hidden = titleView != nil;
    [self setNeedsLayout];
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

- (GLSGlassView *)makePlatter {
    GLSGlassView *p = [GLSGlassView new];
    p.adaptsColorScheme = NO;
    p.contentVibrancyStyle = GLSContentVibrancyStyleControls;
    [_group addSubview:p];
    return p;
}

- (void)setShowsBackButton:(BOOL)showsBackButton {
    _showsBackButton = showsBackButton;
    [_backPlatter removeFromSuperview];
    _backPlatter = nil;
    if (showsBackButton) {
        _backPlatter = [self makePlatter];
        GLSBarButton *b = [[GLSBarButton alloc] initBackButton];
        b.platter = _backPlatter;
        b.highlightedAlpha = 0.2;
        __weak GLSNavigationBar *weakSelf = self;
        b.handler = ^{
            GLSNavigationBar *bar = weakSelf;
            if (bar.backHandler) bar.backHandler();
        };
        [_backPlatter.contentView addSubview:b];
    }
    [self setNeedsLayout];
}

// Adjacent items share a platter; spaces split them.
- (NSArray<GLSGlassView *> *)plattersForItems:(NSArray<UIBarButtonItem *> *)items {
    NSMutableArray<GLSGlassView *> *platters = [NSMutableArray array];
    GLSGlassView *current = nil;
    for (UIBarButtonItem *item in items) {
        if (GLSBarButtonIsSpace(item)) {
            current = nil;
            continue;
        }
        if (!current) {
            current = [self makePlatter];
            [platters addObject:current];
        }
        GLSBarButton *b = [[GLSBarButton alloc] initWithItem:item];
        b.platter = current;
        b.highlightedAlpha = 0.2;
        [current.contentView addSubview:b];
    }
    return platters;
}

- (void)setLeftItems:(NSArray<UIBarButtonItem *> *)leftItems {
    _leftItems = [leftItems copy];
    for (UIView *p in _leftPlatters) [p removeFromSuperview];
    _leftPlatters = [self plattersForItems:_leftItems];
    [self setNeedsLayout];
}

// Right items run from the trailing edge inwards.
- (void)setRightItems:(NSArray<UIBarButtonItem *> *)rightItems {
    _rightItems = [rightItems copy];
    for (UIView *p in _rightPlatters) [p removeFromSuperview];
    _rightPlatters = [self plattersForItems:_rightItems.reverseObjectEnumerator.allObjects];
    [self setNeedsLayout];
}

// Lays the platter's buttons out left to right; returns the platter width.
static CGFloat LayoutPlatter(GLSGlassView *platter) {
    CGFloat x = kItemInset;
    NSArray<UIView *> *buttons = platter.contentView.subviews;
    for (NSUInteger i = 0; i < buttons.count; ++i) {
        GLSBarButton *b = (GLSBarButton *)buttons[i];
        const CGFloat w = std::ceil(([b contentSize].width + kItemPad) * 3) / 3;
        b.frame = CGRectMake(x, kItemInset, w, kPlatterHeight - 2 * kItemInset);
        b.contentCenter = CGPointMake(w / 2, kPlatterHeight / 2 - kItemInset);
        [b setNeedsLayout];
        x += w + (i + 1 < buttons.count ? kItemGap : 0);
    }
    return std::max(x + kItemInset, kPlatterHeight);
}

// Sets bounds and center, not frame, so the press lift transform does not resize the glass.
static void PlacePlatter(GLSGlassView *platter, CGFloat x, CGFloat width) {
    platter.bounds = CGRectMake(0, 0, width, kPlatterHeight);
    platter.center = CGPointMake(x + width / 2, kPlatterHeight / 2);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _group.frame = self.bounds;
    CGFloat left = kMargin, right = self.bounds.size.width - kMargin;
    if (_backPlatter) {
        PlacePlatter(_backPlatter, left, kPlatterHeight);
        GLSBarButton *b = (GLSBarButton *)_backPlatter.contentView.subviews.firstObject;
        b.frame = CGRectMake(0, 0, kPlatterHeight, kPlatterHeight);
        b.contentCenter = CGPointMake(kPlatterHeight / 2, kPlatterHeight / 2);
        [b setNeedsLayout];
        left += kPlatterHeight + kItemGap;
    }
    for (GLSGlassView *p in _leftPlatters) {
        const CGFloat w = LayoutPlatter(p);
        PlacePlatter(p, left, w);
        left += w + kItemGap;
    }
    for (GLSGlassView *p in _rightPlatters) {
        const CGFloat w = LayoutPlatter(p);
        PlacePlatter(p, right - w, w);
        right -= w + kItemGap;
    }
    if (UIView *v = _titleView) {
        CGSize s = v.bounds.size;
        if (s.width <= 0 || s.height <= 0) {
            s = v.intrinsicContentSize;
            if (s.width <= 0 || s.height <= 0) s = [v sizeThatFits:CGSizeMake(right - left, kPlatterHeight)];
        }
        s.width = std::min(s.width, std::max(right - left, CGFloat(0)));
        s.height = std::min(s.height, kPlatterHeight);
        CGFloat x = (self.bounds.size.width - s.width) / 2;
        x = std::min(std::max(x, left), std::max(right - s.width, left));
        v.bounds = CGRectMake(0, 0, s.width, s.height);
        v.center = CGPointMake(x + s.width / 2, kPlatterHeight / 2);
        return;
    }
    const CGSize t = [_titleLabel sizeThatFits:CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX)];
    const CGFloat tw = std::min(std::ceil(t.width * 3) / 3, std::max(right - left, CGFloat(0)));
    const CGFloat th = std::ceil(t.height * 3) / 3;
    _titleLabel.frame = CGRectMake(std::round((self.bounds.size.width - tw) / 2 * 3) / 3,
                                   std::round((kPlatterHeight - th) / 2 * 3) / 3, tw, th);
}

@end
