//
//  GLSTabBarController.mm
//  Glassify
//
//  Copyright © 2026 Hung Phan.
//  See LICENSE file for license information.
//

#import "Glassify/GLSTabBarController.h"

#import "Glassify/GLSGlassContainerView.h"
#import "Glassify/GLSGlassView+Testing.h"
#import "Glassify/GLSGlassView.h"
#import "Glassify/GLSLiquidLensView.h"
#import "Glassify/GLSScrollEdgeEffectView.h"
#import "GLSGlassViewInternal.h"
#import "GLSScrollEdgeEffectViewInternal.h"

#include <algorithm>
#include <cmath>
#include <vector>

static constexpr CGFloat kBarHeight = 62, kBarMargin = 21, kButtonInset = 4, kMinItemWidth = 54, kContentGap = 8,
                         kLiftOutset = 8, kLiftedItemScale = 1.16;
static constexpr NSUInteger kMaxItems = 5;

struct ItemMetrics {
    bool fills;
    CGFloat margin, spacing, padding;
};

static ItemMetrics MetricsForCount(NSUInteger count) {
    const bool fills = count > 3;
    return {fills, count > 4 ? CGFloat(15) : CGFloat(24), fills ? CGFloat(0) : CGFloat(32), fills ? CGFloat(12) : CGFloat(0)};
}

static CGFloat PlatterWidth(const std::vector<CGFloat> &fits, CGFloat available) {
    const ItemMetrics m = MetricsForCount(fits.size());
    if (m.fills || fits.empty()) return available;
    CGFloat widest = kMinItemWidth;
    for (CGFloat fit : fits) widest = std::max(widest, fit + m.padding);
    const CGFloat n = fits.size();
    return std::min(2 * m.margin + (n - 1) * m.spacing + n * widest, available);
}

static std::vector<CGRect> ButtonFrames(const std::vector<CGFloat> &fits, CGSize platter) {
    const size_t count = fits.size();
    if (!count) return {};
    const ItemMetrics m = MetricsForCount(count);
    const CGFloat n = count;
    std::vector<CGFloat> desired;
    CGFloat widest = 0, sum = 0;
    for (CGFloat fit : fits) {
        desired.push_back(std::max(kMinItemWidth, fit + m.padding));
        widest = std::max(widest, desired.back());
        sum += desired.back();
    }
    CGFloat margin = m.margin;
    CGFloat contentWidth = platter.width - 2 * margin;
    widest = std::min(std::max(widest, CGFloat(0)), contentWidth);
    const CGFloat gapForUniform = m.fills ? 2 : m.spacing;
    const CGFloat uniform = (contentWidth - (n - 1) * gapForUniform) / n;
    CGFloat cell = std::min(widest, uniform);
    bool isUniform = true;
    if (m.fills) {
        if (count > 1 && (contentWidth - sum) / (n - 1) < 14) {
            margin = std::min(margin, CGFloat(14));
            isUniform = false;
        } else if (kMinItemWidth < widest) {
            isUniform = widest <= uniform;
            margin = std::min(margin, CGFloat(18));
        }
        contentWidth = platter.width - 2 * margin;
        if (isUniform && count > 1) cell = std::max(cell, contentWidth / n - (margin - kButtonInset));
    }
    std::vector<CGFloat> widths = isUniform ? std::vector<CGFloat>(count, cell) : desired;
    CGFloat total = 0;
    for (CGFloat w : widths) total += w;
    CGFloat overflow = total - contentWidth + (m.fills ? 0 : (n - 1) * m.spacing);
    while (overflow > 0) {
        size_t shrinkable = 0;
        CGFloat smallestExcess = 0;
        for (CGFloat w : widths) {
            if (w <= kMinItemWidth) continue;
            smallestExcess = shrinkable++ ? std::min(smallestExcess, w - kMinItemWidth) : w - kMinItemWidth;
        }
        if (!shrinkable) {
            for (CGFloat &w : widths) w -= overflow / n;
            total -= overflow;
            break;
        }
        const CGFloat step = std::min(smallestExcess, overflow / shrinkable);
        for (CGFloat &w : widths)
            if (w > kMinItemWidth) w -= step;
        total -= step * shrinkable;
        overflow -= step * shrinkable;
    }
    const CGFloat gap = count > 1 ? (m.fills ? (contentWidth - total) / (n - 1) : m.spacing) : 0;
    const CGFloat outset = margin - kButtonInset;
    std::vector<CGRect> frames;
    CGFloat x = margin;
    for (CGFloat w : widths) {
        frames.push_back(CGRectMake(x - outset, kButtonInset, w + 2 * outset, platter.height - 2 * kButtonInset));
        x += w + gap;
    }
    return frames;
}

static UIColor *Dynamic(UIColor *light, UIColor *dark) {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        return traits.userInterfaceStyle == UIUserInterfaceStyleDark ? dark : light;
    }];
}

// The tab items' vibrant colours applied to the resting platter colour.
static UIColor *ItemColor() {
    return Dynamic([UIColor colorWithWhite:0.1 * 0.992 alpha:1], [UIColor colorWithWhite:0.05 * 0.118 + 0.95 alpha:1]);
}

static const float kTintedItemMatrix[2][3][4] = {
    {{0.5f, 0, 0, -0.5f}, {0, 0.5f, 0, 0.0333f}, {0, 0, 0.5f, 0.5f}},
    {{0.5f, 0, 0, 0}, {0, 0.5f, 0, 0.5686f}, {0, 0, 0.5f, 1}},
};

static UIColor *TintedItemColor() {
    return Dynamic([UIColor colorWithRed:0 green:0.5 * 0.992 + 0.0333 blue:0.5 * 0.992 + 0.5 alpha:1],
                   [UIColor colorWithRed:0.5 * 0.118 green:0.5 * 0.118 + 0.5686 blue:1 alpha:1]);
}

// The page's content scroll view, else its first visible scroll view, breadth first.
static UIScrollView *ContentScrollView(UIViewController *vc) {
    if ([vc isKindOfClass:UINavigationController.class]) vc = ((UINavigationController *)vc).topViewController;
    if (!vc.isViewLoaded) return nil;
    if (@available(iOS 15.0, *)) {
        if (UIScrollView *s = [vc contentScrollViewForEdge:NSDirectionalRectEdgeBottom]) return s;
    }
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:vc.view];
    while (queue.count) {
        UIView *v = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if ([v isKindOfClass:UIScrollView.class] && !v.hidden) return (UIScrollView *)v;
        [queue addObjectsFromArray:v.subviews];
    }
    return nil;
}

@interface GLSTabBarBlockTarget : NSObject
@property (nonatomic, copy) void (^block)(void);
- (void)fire;
@end

@implementation GLSTabBarBlockTarget
- (void)fire { _block(); }
@end

#pragma mark - Tab bar view

// The floating platter, its items, and the liquid lens that follows the finger and settles on a tab.
@interface GLSTabBarView : UIView
- (instancetype)initWithContainer:(GLSGlassContainerView *)container;
@property (nonatomic, copy) NSArray<UITabBarItem *> *tabItems;
@property (nonatomic, readonly) NSInteger selectedIndex;
@property (nonatomic, copy) BOOL (^shouldSelect)(NSInteger index);
@property (nonatomic, copy) void (^didSelect)(NSInteger index);
- (void)setSelectedIndex:(NSInteger)index animated:(BOOL)animated;
- (void)setNeedsBackdropUpdate;
- (CGFloat)platterWidthForAvailableWidth:(CGFloat)available;
@end

@implementation GLSTabBarView {
    __weak GLSGlassContainerView *_container;
    GLSGlassView *_platter;
    UIView *_overlay;
    UIView *_pill;
    UIView *_itemsView;
    UIView *_tinted;
    UIView *_restTinted;
    GLSLiquidLensView *_lens;
    // -1 when no finger is down.
    NSInteger _highlighted;
    // Where the finger touched the button, 0 to 1 across its width.
    CGFloat _anchorX;
    CGFloat _touchX;
    BOOL _dragging;
    CGRect _lensFrame;
    CGFloat _targetX;
    CGSize _builtSize;
    std::vector<CGFloat> _fits;
    std::vector<CGRect> _buttonFrames;
    CGFloat _itemScale;
    CADisplayLink *_link;
}

- (instancetype)initWithContainer:(GLSGlassContainerView *)container {
    if (!(self = [super initWithFrame:CGRectZero])) return nil;
    _container = container;
    _highlighted = -1;
    _platter = [GLSGlassView new];
    _platter.userInteractionEnabled = NO;
    _platter.contentVibrancy = NO;
    [container addSubview:_platter];

    _overlay = [UIView new];
    _overlay.userInteractionEnabled = NO;
    [_platter.contentView addSubview:_overlay];
    _pill = [UIView new];
    _pill.backgroundColor = Dynamic([UIColor colorWithWhite:0 alpha:0.08], [UIColor colorWithWhite:1 alpha:0.14]);
    _pill.layer.cornerCurve = kCACornerCurveContinuous;
    [_overlay addSubview:_pill];


    _lens = [GLSLiquidLensView new];
    _lens.backdropSourceView = _overlay;
    _lens.backdropBaseColor = UIColor.systemBackgroundColor;
    _lens.underlayGlassView = _platter;
    _lens.layer.zPosition = 10;
    [_platter.contentView addSubview:_lens];

    UILongPressGestureRecognizer *press = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(press:)];
    press.minimumPressDuration = 0;
    [self addGestureRecognizer:press];
    return self;
}

- (void)dealloc {
    [_link invalidate];
}

- (void)setTabItems:(NSArray<UITabBarItem *> *)tabItems {
    _tabItems = [tabItems subarrayWithRange:NSMakeRange(0, std::min(tabItems.count, kMaxItems))];
    _selectedIndex = std::min(std::max(_selectedIndex, NSInteger(0)), std::max(NSInteger(_tabItems.count) - 1, NSInteger(0)));
    _builtSize = CGSizeZero;
    [self measureItems];
    [self setNeedsLayout];
}

- (void)measureItems {
    _fits.clear();
    const CGFloat scale = UIScreen.mainScreen.scale;
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:18
                                                                                         weight:UIImageSymbolWeightMedium
                                                                                          scale:UIImageSymbolScaleLarge];
    UIFont *font = [UIFont systemFontOfSize:10 weight:UIFontWeightMedium];
    for (UITabBarItem *tab in _tabItems) {
        UIImage *image = tab.image.isSymbolImage ? [tab.image imageByApplyingSymbolConfiguration:config] : tab.image;
        const CGFloat label = tab.title.length ? [tab.title sizeWithAttributes:@{NSFontAttributeName : font}].width : 0;
        _fits.push_back(std::ceil(std::max(image.size.width, label) * scale) / scale);
    }
}

- (CGFloat)platterWidthForAvailableWidth:(CGFloat)available {
    return PlatterWidth(_fits, available);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    GLSGlassContainerView *container = _container;
    if (!container || !self.superview) return;
    const CGRect frame = [container convertRect:self.frame fromView:self.superview];
    _platter.bounds = CGRectMake(0, 0, frame.size.width, frame.size.height);
    _platter.center = CGPointMake(CGRectGetMidX(frame), CGRectGetMidY(frame));
    _overlay.frame = _platter.contentView.bounds;
    if (CGSizeEqualToSize(_builtSize, self.bounds.size)) return;
    _builtSize = self.bounds.size;
    _buttonFrames = ButtonFrames(_fits, self.bounds.size);
    [self rebuildItems];
}

- (void)rebuildItems {
    [_itemsView removeFromSuperview];
    [_restTinted removeFromSuperview];
    _itemsView = [self itemsViewTinted:NO];
    _itemsView.alpha = 0;
    [_overlay addSubview:_itemsView];
    _platter.vibrantContentViews = @[ _itemsView ];
    _tinted = [self itemsViewTinted:YES];
    _itemScale = 1;
    _restTinted = [self itemsViewTinted:YES];
    _restTinted.alpha = 0;
    [_overlay addSubview:_restTinted];
    [_platter gls_setTintedVibrantViews:@[ _restTinted ] matrix:kTintedItemMatrix];
    _lens.liftedContentView = _tinted;
    _lens.liftedContentFrame = self.bounds;
    [self placeLens];
}

- (UIView *)itemsViewTinted:(BOOL)tinted {
    UIView *view = [[UIView alloc] initWithFrame:self.bounds];
    view.userInteractionEnabled = NO;
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:18
                                                                                         weight:UIImageSymbolWeightMedium
                                                                                          scale:UIImageSymbolScaleLarge];
    UIColor *color = tinted ? TintedItemColor() : ItemColor();
    for (NSUInteger i = 0; i < _tabItems.count; ++i) {
        UITabBarItem *tab = _tabItems[i];
        UIView *item = [[UIView alloc] initWithFrame:[self buttonFrame:i]];
        UIImage *image = tinted && tab.selectedImage ? tab.selectedImage : tab.image;
        if (image.isSymbolImage) image = [image imageByApplyingSymbolConfiguration:config];
        UIImageView *icon = [[UIImageView alloc] initWithImage:[image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
        icon.tintColor = color;
        icon.contentMode = UIViewContentModeCenter;
        [icon sizeToFit];
        icon.center = CGPointMake(item.bounds.size.width / 2, 20);
        UILabel *label = [UILabel new];
        label.text = tab.title;
        label.textColor = color;
        label.font = [UIFont systemFontOfSize:10 weight:tinted ? UIFontWeightSemibold : UIFontWeightMedium];
        const CGFloat width = std::ceil([label sizeThatFits:CGSizeZero].width * 3) / 3;
        label.frame = CGRectMake(std::round((item.bounds.size.width - width) / 2), 35, width, 12);
        [item addSubview:icon];
        [item addSubview:label];
        [view addSubview:item];
    }
    return view;
}

- (CGRect)buttonFrame:(NSInteger)slot {
    if (slot < 0 || size_t(slot) >= _buttonFrames.size()) return CGRectZero;
    return _buttonFrames[slot];
}

- (NSInteger)slotAtX:(CGFloat)x {
    NSInteger best = 0;
    for (NSInteger i = 1; i < NSInteger(_tabItems.count); ++i) {
        if (std::fabs(x - CGRectGetMidX([self buttonFrame:i])) < std::fabs(x - CGRectGetMidX([self buttonFrame:best]))) best = i;
    }
    return best;
}

- (void)setNeedsBackdropUpdate {
    [_lens setNeedsBackdropUpdate];
    [_platter setNeedsVibrantContentUpdate];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    [self setNeedsBackdropUpdate];
}

#pragma mark Selection

- (void)setSelectedIndex:(NSInteger)index animated:(BOOL)animated {
    if (index < 0 || index >= NSInteger(_tabItems.count) || index == _selectedIndex) return;
    _selectedIndex = index;
    if (animated && _highlighted < 0) {
        [self startFrames];
        [self updateLens];
    } else {
        [self placeLens];
    }
}

- (void)placeLens {
    if (!_tabItems.count) return;
    _lensFrame = [self buttonFrame:_selectedIndex];
    _targetX = CGRectGetMidX(_lensFrame);
    [UIView performWithoutAnimation:^{
        self->_lens.bounds = CGRectMake(0, 0, self->_lensFrame.size.width, self->_lensFrame.size.height);
        self->_lens.center = CGPointMake(CGRectGetMidX(self->_lensFrame), CGRectGetMidY(self->_lensFrame));
    }];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [self followLens:_lens.layer];
    [CATransaction commit];
    [self setNeedsBackdropUpdate];
}

#pragma mark Gesture

// Read in the platter's untransformed space, so the press scale moves the lens away from the finger as in UIKit.
- (void)press:(UILongPressGestureRecognizer *)g {
    if (!_tabItems.count) return;
    const CGPoint p = [g locationInView:self];
    switch (g.state) {
        case UIGestureRecognizerStateBegan: [self touchDownAt:p]; break;
        case UIGestureRecognizerStateChanged: [self touchMovedTo:p]; break;
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled: [self touchUpAt:p]; break;
        default: break;
    }
}

- (void)touchDownAt:(CGPoint)p {
    _highlighted = [self slotAtX:p.x];
    const CGRect button = [self buttonFrame:_highlighted];
    _anchorX = (p.x - button.origin.x) / button.size.width;
    _touchX = p.x;
    _dragging = NO;
    [_platter gls_beginPressAtPoint:p];
    [self startFrames];
    [self updateLens];
}

- (void)touchMovedTo:(CGPoint)p {
    _highlighted = [self slotAtX:p.x];
    _touchX = p.x;
    _dragging = YES;
    [_platter gls_movePressToPoint:p];
    [self updateLens];
}

- (void)touchUpAt:(CGPoint)p {
    const NSInteger chosen = _highlighted;
    _highlighted = -1;
    _dragging = NO;
    if (chosen >= 0 && chosen != _selectedIndex && (!_shouldSelect || _shouldSelect(chosen))) {
        _selectedIndex = chosen;
        if (_didSelect) _didSelect(chosen);
    }
    [_platter gls_endPress];
    [self updateLens];
}

#pragma mark Lens

- (void)updateLens {
    const BOOL highlighted = _highlighted >= 0;
    CGRect frame = [self buttonFrame:highlighted ? _highlighted : _selectedIndex];
    if (highlighted) {
        const CGFloat w = frame.size.width, ax = _anchorX;
        const CGFloat x = std::min(std::max(_touchX, ax * w), self.bounds.size.width - (1 - ax) * w);
        frame.origin.x = x - ax * w;
    }
    const CGFloat positionResponse = _dragging ? 0.2 : 0.4, sizeResponse = _dragging ? 0.3 : 0.6;
    const CGPoint center = CGPointMake(CGRectGetMidX(frame), CGRectGetMidY(frame));
    _targetX = center.x;
    GLSAnimateWithSpring(0.85, positionResponse, ^{ self->_lens.center = center; }, nil);
    GLSAnimateWithSpring(0.85, sizeResponse, ^{
        self->_lensFrame = frame;
        CGRect b = self->_lens.bounds;
        b.size = self->_lens.isLifted ? CGRectInset(frame, -kLiftOutset, -kLiftOutset).size : frame.size;
        self->_lens.bounds = b;
    }, nil);
    if (highlighted) [self setLensLifted:YES];
}

- (void)setLensLifted:(BOOL)lifted {
    if (lifted == _lens.isLifted) return;
    [_lens setLifted:lifted animated:YES alongsideAnimations:^{
        CGRect b = self->_lens.bounds;
        b.size = lifted ? CGRectInset(self->_lensFrame, -kLiftOutset, -kLiftOutset).size : self->_lensFrame.size;
        self->_lens.bounds = b;
    }];
}

// Runs every frame while the lens moves: it unlifts once it has settled near its tab.
- (void)frameTick {
    CALayer *lens = _lens.layer.presentationLayer ?: _lens.layer;
    if (_lens.isLifted && _highlighted < 0 && std::fabs(_targetX - lens.position.x) < 8 && _lens.liftedDuration >= 0.22) {
        [self setLensLifted:NO];
    }
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [self followLens:lens];
    [CATransaction commit];
    [self scaleLiftedItems];
    [self setNeedsBackdropUpdate];
    if (!_lens.isLifted && _highlighted < 0 && !_lens.layer.animationKeys.count && _lens.liftProgress <= 0) {
        [self stopFrames];
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        [self followLens:_lens.layer];
        [CATransaction commit];
    }
}

// Keeps the resting pill on the lens's drawn frame, fading out as the glass appears, and moves the item masks with it.
- (void)followLens:(CALayer *)lens {
    const CGRect drawn = [lens convertRect:lens.bounds toLayer:_overlay.layer];
    _pill.frame = drawn;
    _pill.layer.cornerRadius = std::min(drawn.size.width, drawn.size.height) / 2;
    _pill.alpha = 1 - _lens.liftAlpha;
    [_platter gls_setVibrantHole:[lens convertRect:lens.bounds toLayer:_platter.layer] tintedOpacity:1 - _lens.liftAlpha];
}

- (void)scaleLiftedItems {
    const CGFloat scale = 1 + (kLiftedItemScale - 1) * std::min(std::max(_lens.liftProgress, CGFloat(0)), CGFloat(1));
    if (std::fabs(scale - _itemScale) < 0.001) return;
    _itemScale = scale;
    for (UIView *item in _tinted.subviews) item.transform = CGAffineTransformMakeScale(scale, scale);
    [_lens setNeedsContentUpdate];
}

- (void)startFrames {
    if (_link) return;
    GLSTabBarBlockTarget *target = [GLSTabBarBlockTarget new];
    __weak GLSTabBarView *weakSelf = self;
    target.block = ^{ [weakSelf frameTick]; };
    _link = [CADisplayLink displayLinkWithTarget:target selector:@selector(fire)];
    [_link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
}

- (void)stopFrames {
    [_link invalidate];
    _link = nil;
}

@end

#pragma mark - Controller

@implementation GLSTabBarController {
    GLSScrollEdgeEffectView *_edge;
    GLSGlassContainerView *_group;
    GLSTabBarView *_bar;
    UIEdgeInsets _userAdditional, _barInsets;
    __weak UIScrollView *_observed;
}

static void *kScrollContext = &kScrollContext;

- (void)dealloc {
    [self stopObservingScrollView];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tabBar.hidden = YES;
    _edge = [GLSScrollEdgeEffectView new];
    _edge.edge = GLSScrollEdgeBottom;
    _edge.barHeight = kBarHeight;
    [self.view addSubview:_edge];
    _group = [GLSGlassContainerView new];
    _group.spacing = 6;
    _group.tracksBackdropMotion = YES;
    _group.scrollEdgeEffect = _edge;
    [self.view addSubview:_group];
    _bar = [[GLSTabBarView alloc] initWithContainer:_group];
    __weak GLSTabBarController *weakSelf = self;
    _bar.shouldSelect = ^BOOL(NSInteger index) { return [weakSelf shouldSelectIndex:index]; };
    _bar.didSelect = ^(NSInteger index) { [weakSelf didSelectIndex:index]; };
    [self.view addSubview:_bar];
    [self reloadItems];
}

- (BOOL)shouldSelectIndex:(NSInteger)index {
    UIViewController *vc = self.viewControllers[index];
    id<UITabBarControllerDelegate> delegate = self.delegate;
    if ([delegate respondsToSelector:@selector(tabBarController:shouldSelectViewController:)])
        return [delegate tabBarController:self shouldSelectViewController:vc];
    return YES;
}

- (void)didSelectIndex:(NSInteger)index {
    [super setSelectedIndex:index];
    id<UITabBarControllerDelegate> delegate = self.delegate;
    if ([delegate respondsToSelector:@selector(tabBarController:didSelectViewController:)])
        [delegate tabBarController:self didSelectViewController:self.selectedViewController];
    [self.viewIfLoaded setNeedsLayout];
}

- (void)reloadItems {
    if (!_bar) return;
    NSMutableArray<UITabBarItem *> *items = [NSMutableArray array];
    for (UIViewController *vc in self.viewControllers) [items addObject:vc.tabBarItem];
    _bar.tabItems = items;
    [_bar setSelectedIndex:self.selectedIndex animated:NO];
    [self.viewIfLoaded setNeedsLayout];
}

- (void)setViewControllers:(NSArray<__kindof UIViewController *> *)viewControllers animated:(BOOL)animated {
    [super setViewControllers:viewControllers animated:animated];
    [self reloadItems];
}

- (void)setSelectedIndex:(NSUInteger)selectedIndex {
    [super setSelectedIndex:selectedIndex];
    [_bar setSelectedIndex:self.selectedIndex animated:self.viewIfLoaded.window != nil];
    [self.viewIfLoaded setNeedsLayout];
}

- (void)setSelectedViewController:(__kindof UIViewController *)selectedViewController {
    [super setSelectedViewController:selectedViewController];
    [_bar setSelectedIndex:self.selectedIndex animated:self.viewIfLoaded.window != nil];
    [self.viewIfLoaded setNeedsLayout];
}

#pragma mark Layout

- (void)setAdditionalSafeAreaInsets:(UIEdgeInsets)insets {
    _userAdditional = insets;
    [self applyAdditionalInsets];
}

- (void)applyAdditionalInsets {
    const UIEdgeInsets u = _userAdditional, b = _barInsets;
    [super setAdditionalSafeAreaInsets:UIEdgeInsetsMake(u.top + b.top, u.left + b.left, u.bottom + b.bottom, u.right + b.right)];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.tabBar.hidden = YES;
    UIView *view = self.view;
    const CGSize size = view.bounds.size;
    const CGFloat width = [_bar platterWidthForAvailableWidth:size.width - 2 * kBarMargin];
    const CGFloat top = size.height - kBarMargin - kBarHeight;
    _group.frame = CGRectMake(0, top - 30, size.width, kBarHeight + 51);
    _bar.frame = CGRectMake(std::round((size.width - width) / 2), top, width, kBarHeight);
    [_bar setNeedsLayout];
    [_bar layoutIfNeeded];
    _edge.barEdge = top;

    const CGFloat baseBottom = view.safeAreaInsets.bottom - _barInsets.bottom;
    const UIEdgeInsets bars = UIEdgeInsetsMake(0, 0, std::max(size.height - top + kContentGap - baseBottom, CGFloat(0)), 0);
    if (!UIEdgeInsetsEqualToEdgeInsets(bars, _barInsets)) {
        _barInsets = bars;
        [self applyAdditionalInsets];
    }
    [view bringSubviewToFront:_edge];
    [view bringSubviewToFront:_group];
    [view bringSubviewToFront:_bar];
    [self updateBackdrop];
}

#pragma mark Backdrop

- (void)updateBackdrop {
    UIViewController *vc = self.selectedViewController;
    UIScrollView *scroll = ContentScrollView(vc);
    _group.backdropSourceView = scroll ?: vc.view;
    _edge.hidden = scroll == nil;
    [_edge gls_matchBackgroundOf:scroll ?: vc.view];
    if (scroll != _observed) {
        [self stopObservingScrollView];
        _observed = scroll;
        [scroll addObserver:self forKeyPath:@"contentOffset" options:0 context:kScrollContext];
        [scroll addObserver:self forKeyPath:@"contentSize" options:0 context:kScrollContext];
    }
    [self updateFrost];
    [_group setNeedsBackdropUpdate];
    [_bar setNeedsBackdropUpdate];
}

- (void)stopObservingScrollView {
    [_observed removeObserver:self forKeyPath:@"contentOffset" context:kScrollContext];
    [_observed removeObserver:self forKeyPath:@"contentSize" context:kScrollContext];
    _observed = nil;
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (context == kScrollContext) [self updateFrost];
    else [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

// Glass over scrolling content shows no frost; once nothing is left under the bar it frosts lightly.
- (void)updateFrost {
    UIScrollView *s = _observed;
    if (!s) {
        _group.frost = GLSGlassFrostAutomatic;
        return;
    }
    const BOOL under = s.contentOffset.y + s.bounds.size.height - s.adjustedContentInset.bottom < s.contentSize.height;
    _group.frost = under ? GLSGlassFrostNone : GLSGlassFrostReduced;
}

@end
