//
//  GLSGlassView.mm
//  Glassify
//
//  Copyright © 2026 Hung Phan.
//  See LICENSE file for license information.
//

#import "Glassify/GLSGlassView.h"
#import "Glassify/GLSGlassView+Testing.h"
#import "Glassify/GLSGlassContainerView.h"
#import "Glassify/GLSScrollEdgeEffectView.h"

#import "GLSContentMask.h"
#import "GLSGlassSurface.h"
#import "GLSGlassViewInternal.h"

#include <algorithm>
#include <cmath>

#include "glassify/press.h"

using namespace glassify;

static GlassStyle CoreStyle(GLSGlassStyle style) {
    return style == GLSGlassStyleClear ? GlassStyle::Clear : GlassStyle::Regular;
}

static Frost CoreFrost(GLSGlassFrost frost) {
    return frost == GLSGlassFrostNone ? Frost::None : frost == GLSGlassFrostReduced ? Frost::Reduced : Frost::Automatic;
}

static void FollowAnimation(id<GLSFrameClient> client, id<CAAction> action) {
    if (![(id)action isKindOfClass:[CAAnimation class]]) return;
    CAAnimation *animation = (CAAnimation *)action;
    const CFTimeInterval duration = animation.duration > 0 ? animation.duration : 0.5;
    [[GLSFrameDriver shared] addClient:client until:CACurrentMediaTime() + duration + 0.1];
}

@interface GLSGlassContainerView () <GLSFrameClient>
- (void)setNeedsGlassRender;
- (GLSGlassSurface *)gls_surface;
- (void)followAction:(id<CAAction>)action;
@end

@interface GLSGlassView () <GLSFrameClient>
- (void)gls_styleContentForDark:(BOOL)dark;
- (BOOL)gls_drawsVibrantContent;
- (NSArray<UIView *> *)gls_vibrantViews;
- (ShapeElement)elementInLayer:(CALayer *)layer;
- (GlowState)glowInLayer:(CALayer *)layer;
- (float)materializeProgress;
@end

#pragma mark - Glass view

@interface GLSGlassView (Render)
- (void)setNeedsGlassRender;
@end

@interface GLSGlassContentView : UIView
@property (nonatomic, weak) GLSGlassView *glass;
@end

@implementation GLSGlassContentView
- (void)layoutSubviews {
    [super layoutSubviews];
    [self.glass setNeedsGlassRender];
}
- (void)didAddSubview:(UIView *)subview {
    [super didAddSubview:subview];
    [self.glass setNeedsGlassRender];
}
- (void)willRemoveSubview:(UIView *)subview {
    [super willRemoveSubview:subview];
    [self.glass setNeedsGlassRender];
}
@end

UIView *GLSDefaultBackdropSource(UIView *view) {
    for (UIView *v = view.superview; v; v = v.superview) {
        UIColor *background = [v.backgroundColor resolvedColorWithTraitCollection:v.traitCollection];
        CGFloat alpha = 0;
        if (background && [background getWhite:nullptr alpha:&alpha] && alpha >= 1) return v;
    }
    return view.window ?: view.superview ?: view;
}

@interface GLSTrackingGestureRecognizer : UIPanGestureRecognizer <UIGestureRecognizerDelegate>
@end

@implementation GLSTrackingGestureRecognizer

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    return [self.view isKindOfClass:UIControl.class] && ((UIControl *)self.view).isTracking;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
    shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    return YES;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
    shouldBeRequiredToFailByGestureRecognizer:(UIGestureRecognizer *)other {
    return [other isKindOfClass:UIPanGestureRecognizer.class] && other.view != self.view && [self.view isDescendantOfView:other.view];
}

@end

void GLSInstallTrackingGesture(UIControl *control) {
    GLSTrackingGestureRecognizer *pan = [[GLSTrackingGestureRecognizer alloc] initWithTarget:nil action:nil];
    pan.delegate = pan;
    pan.cancelsTouchesInView = NO;
    pan.delaysTouchesEnded = NO;
    [control addGestureRecognizer:pan];
}

@implementation GLSGlassView {
    GLSGlassSurface *_surface;
    NSArray<UIView *> *_tintedVibrantViews;
    float _tintedMatrix[2][3][4];
    CGRect _vibrantHole;
    CGFloat _tintedOpacity;
    // The scheme the content was last styled for: -1 none, 0 light, 1 dark.
    int _contentDark;
    BOOL _needsRender, _deallocating;
    PressModel _press;
    CFTimeInterval _lastTick;
    BOOL _resizing;
    CGSize _resizeFrom;
    // Holds the materialize progress in its center.x, so UIKit animates it with the caller's timing.
    UIView *_materializeProbe;
    BOOL _materializing;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    [self commonInit];
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    if (!(self = [super initWithCoder:coder])) return nil;
    [self commonInit];
    return self;
}

- (void)commonInit {
    _cornerRadius = -1;
    _glassEnabled = YES;
    _adaptsColorScheme = YES;
    _contentDark = -1;
    _vibrantHole = CGRectNull;
    _tintedOpacity = 1;
    _materializeProbe = [[UIView alloc] initWithFrame:CGRectMake(1, 0, 0, 0)];
    _materializeProbe.userInteractionEnabled = NO;
    [self addSubview:_materializeProbe];
    self.backgroundColor = UIColor.clearColor;
    _surface = [[GLSGlassSurface alloc] initWithHost:self];
    __weak GLSGlassView *weakSelf = self;
    _surface.sourceDidMove = ^{ [weakSelf setNeedsGlassRender]; };
    _surface.appearanceDidChange = ^(BOOL dark) { [weakSelf gls_styleContentForDark:dark]; };
    _contentVibrancy = YES;
    _surface.needsFrames = ^{
        GLSGlassView *view = weakSelf;
        if (view) [[GLSFrameDriver shared] addClient:view until:CACurrentMediaTime() + 1.5];
    };
    GLSGlassContentView *contentView = [[GLSGlassContentView alloc] initWithFrame:self.bounds];
    contentView.glass = self;
    _contentView = contentView;
    _contentView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self addSubview:_contentView];
}

- (void)dealloc {
    _deallocating = YES;
    [[GLSFrameDriver shared] removeClient:self];
}

- (void)gls_styleContentForDark:(BOOL)dark {
    _contentDark = dark ? 1 : 0;
    if (!_contentVibrancy) return;
    if (@available(iOS 13.0, *)) {
        _contentView.overrideUserInterfaceStyle = dark ? UIUserInterfaceStyleDark : UIUserInterfaceStyleLight;
    }
    _contentView.tintColor = dark ? UIColor.whiteColor : UIColor.blackColor;
    _contentView.alpha = dark ? 0.95 : 1;
}

- (void)setContentVibrancyStyle:(GLSContentVibrancyStyle)contentVibrancyStyle {
    _contentVibrancyStyle = contentVibrancyStyle;
    [self updateContentMask];
    [self setNeedsGlassRender];
}

- (BOOL)gls_drawsVibrantContent {
    return _contentVibrancy && _contentVibrancyStyle == GLSContentVibrancyStyleControls;
}

// The views stay to take touches but show nothing, through an empty mask layer; alpha 0 would stop hit testing.
- (void)updateContentMask {
    if ([self gls_drawsVibrantContent]) {
        if (!_contentView.layer.mask) {
            CALayer *hide = [CALayer layer];
            hide.name = GLSContentMaskHiddenName;
            _contentView.layer.mask = hide;
        }
    } else {
        _contentView.layer.mask = nil;
    }
}

- (void)setContentVibrancy:(BOOL)contentVibrancy {
    if (_contentVibrancy == contentVibrancy) return;
    _contentVibrancy = contentVibrancy;
    [self updateContentMask];
    if (contentVibrancy && _contentDark >= 0) {
        [self gls_styleContentForDark:_contentDark == 1];
    } else if (!contentVibrancy) {
        if (@available(iOS 13.0, *)) _contentView.overrideUserInterfaceStyle = UIUserInterfaceStyleUnspecified;
        _contentView.tintColor = nil;
        _contentView.alpha = 1;
    }
}

- (GLSGlassContainerView *)container {
    return [self.superview isKindOfClass:[GLSGlassContainerView class]] ? (GLSGlassContainerView *)self.superview : nil;
}

#pragma mark Properties

- (void)setStyle:(GLSGlassStyle)style {
    _style = style;
    [self setNeedsGlassRender];
}

- (void)setAdaptsColorScheme:(BOOL)adaptsColorScheme {
    _adaptsColorScheme = adaptsColorScheme;
    [self setNeedsGlassRender];
}

- (void)setGlassTintColor:(UIColor *)glassTintColor {
    _glassTintColor = [glassTintColor copy];
    [self setNeedsGlassRender];
}

- (void)setGlassEnabled:(BOOL)glassEnabled {
    if (_glassEnabled == glassEnabled) return;
    _glassEnabled = glassEnabled;
    _materializeProbe.center = CGPointMake(glassEnabled ? 1 : 0, 0);
    if (_materializeProbe.layer.animationKeys.count > 0) {
        _materializing = YES;
        [[GLSFrameDriver shared] addClient:self until:INFINITY];
    }
    [self setNeedsGlassRender];
}

// Follows the probe's presentation layer while animating.
- (float)materializeProgress {
    CALayer *probe = _materializeProbe.layer.presentationLayer ?: _materializeProbe.layer;
    return float(probe.position.x);
}

- (void)setCornerRadius:(CGFloat)cornerRadius {
    _cornerRadius = cornerRadius;
    [self setNeedsGlassRender];
}

- (void)setBackdropSourceView:(UIView *)backdropSourceView {
    _backdropSourceView = backdropSourceView;
    [self setNeedsGlassRender];
}

- (void)setTracksBackdropMotion:(BOOL)tracksBackdropMotion {
    _tracksBackdropMotion = tracksBackdropMotion;
    [self updateDriverRegistration];
}

- (void)setFrost:(GLSGlassFrost)frost {
    _frost = frost;
    [self setNeedsGlassRender];
}

- (void)setBlurLodBias:(CGFloat)blurLodBias {
    _blurLodBias = blurLodBias;
    [self setNeedsGlassRender];
}

- (void)setNeedsBackdropUpdate {
    [_surface setNeedsBackdropUpdate];
    [self setNeedsGlassRender];
}

- (void)setVibrantContentViews:(NSArray<UIView *> *)vibrantContentViews {
    _vibrantContentViews = [vibrantContentViews copy];
    [self setNeedsGlassRender];
}

- (void)gls_setTintedVibrantViews:(NSArray<UIView *> *)views matrix:(const float (*)[3][4])matrix {
    _tintedVibrantViews = [views copy];
    memcpy(_tintedMatrix, matrix, sizeof(_tintedMatrix));
    [self setNeedsVibrantContentUpdate];
}

- (void)gls_setVibrantHole:(CGRect)hole tintedOpacity:(CGFloat)opacity {
    _vibrantHole = hole;
    _tintedOpacity = opacity;
    [self setNeedsGlassRender];
}

- (void)gls_fillTintedVibrancy:(GLSSurfaceRequest &)request inLayer:(CALayer *)target {
    if (!_tintedVibrantViews.count) return;
    if (!CGRectIsNull(_vibrantHole) && !CGRectIsEmpty(_vibrantHole)) {
        CALayer *layer = self.layer.presentationLayer ?: self.layer;
        request.vibrantHole = target ? [layer convertRect:_vibrantHole toLayer:target] : _vibrantHole;
    }
    request.tintedOpacity = float(_tintedOpacity);
    request.tintedVibrantViews = request.tintedVibrantViews ? [request.tintedVibrantViews arrayByAddingObjectsFromArray:_tintedVibrantViews]
                                                            : _tintedVibrantViews;
    memcpy(request.tintedMatrix, _tintedMatrix, sizeof(_tintedMatrix));
}

- (void)setNeedsVibrantContentUpdate {
    [self setNeedsGlassRender];
}

- (NSArray<UIView *> *)gls_vibrantViews {
    NSArray<UIView *> *views = [self gls_drawsVibrantContent] ? @[ _contentView ] : @[];
    return _vibrantContentViews.count ? [views arrayByAddingObjectsFromArray:_vibrantContentViews] : views;
}

#pragma mark Lifecycle

- (void)didMoveToSuperview {
    [super didMoveToSuperview];
    _surface.hidden = [self container] != nil;
    [self setNeedsGlassRender];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    [self updateDriverRegistration];
    [self setNeedsGlassRender];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self setNeedsGlassRender];
}

- (void)setCenter:(CGPoint)center {
    [super setCenter:center];
    [[self container] setNeedsGlassRender];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
        [_surface setNeedsBackdropUpdate];
    }
    [self setNeedsGlassRender];
}

// Follows the presentation layer for the duration of UIKit animations on the glass itself.
- (id<CAAction>)actionForLayer:(CALayer *)layer forKey:(NSString *)event {
    id<CAAction> action = [super actionForLayer:layer forKey:event];
    if (layer == self.layer && action && action != (id)NSNull.null && [event isEqualToString:@"bounds"]) {
        CALayer *presentation = layer.presentationLayer ?: layer;
        _resizeFrom = presentation.bounds.size;
        _resizing = YES;
        if (![self container]) [[GLSFrameDriver shared] addClient:self until:INFINITY];
    }
    if (layer == self.layer) {
        GLSGlassContainerView *container = [self container];
        if (container) [container followAction:action];
        else FollowAnimation(self, action);
    }
    return action;
}

- (BOOL)wantsContinuousFrames {
    return (_tracksBackdropMotion && self.window != nil && ![self container]) || _lastTick != 0 ||
           _resizing || _materializing;
}

- (void)updateDriverRegistration {
    if ([self wantsContinuousFrames]) [[GLSFrameDriver shared] addClient:self until:INFINITY];
    else [[GLSFrameDriver shared] removeClient:self];
}

#pragma mark Press

- (void)setInteractive:(BOOL)interactive {
    _interactive = interactive;
    if (!interactive) [self endPress];
}

// Ignores the press transform, which UIKit's presentation-only lift never shows to locationInView:.
- (CGPoint)untransformedLocationOf:(UITouch *)touch {
    UIView *superview = self.superview;
    if (!superview) return [touch locationInView:self];
    const CGPoint p = [touch locationInView:superview];
    const CGRect b = self.bounds;
    const CGPoint a = self.layer.anchorPoint;
    return CGPointMake(p.x - self.center.x + b.origin.x + b.size.width * a.x,
                       p.y - self.center.y + b.origin.y + b.size.height * a.y);
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesBegan:touches withEvent:event];
    if (_interactive) [self gls_beginPressAtPoint:[self untransformedLocationOf:touches.anyObject]];
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesMoved:touches withEvent:event];
    if (_interactive) [self gls_movePressToPoint:[self untransformedLocationOf:touches.anyObject]];
}

- (void)gls_beginPressAtPoint:(CGPoint)point {
    _press.configure(float(self.bounds.size.width), float(self.bounds.size.height));
    _press.begin(float(point.x), float(point.y));
    [self startPressFrames];
}

- (void)gls_movePressToPoint:(CGPoint)point {
    _press.move(float(point.x), float(point.y));
}

- (void)gls_endPress {
    [self endPress];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesEnded:touches withEvent:event];
    [self endPress];
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesCancelled:touches withEvent:event];
    [self endPress];
}

- (void)endPress {
    _press.end();
    [self startPressFrames];
}

- (void)startPressFrames {
    if (_lastTick == 0) _lastTick = CACurrentMediaTime();
    [[GLSFrameDriver shared] addClient:self until:INFINITY];
}

// Returns YES while the press is still animating.
- (BOOL)stepPress {
    if (_lastTick == 0) return NO;
    const CFTimeInterval now = CACurrentMediaTime();
    _press.step(float(std::min(now - _lastTick, 1.0 / 20.0)));
    _lastTick = now;

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.layer.transform = CATransform3DTranslate(CATransform3DMakeScale(_press.scaleX(), _press.scaleY(), 1),
                                                  _press.driftX(), _press.driftY(), 0);
    [CATransaction commit];

    if (_press.active()) return YES;
    _lastTick = 0;
    self.layer.transform = CATransform3DIdentity;
    return NO;
}

- (GlowState)glowInLayer:(CALayer *)target {
    GlowState glow;
    if (_lastTick == 0) return glow;
    glow.bigAlpha = _press.bigGlowAlpha();
    glow.littleAlpha = _press.littleGlowAlpha();
    glow.littleDiameter = _press.spec().littleGlowDiameter;
    glow.littleScale = _press.littleGlowScale();
    CGPoint c = CGPointMake(_press.glowX(), _press.glowY());
    if (target) {
        CALayer *layer = self.layer.presentationLayer ?: self.layer;
        c = [layer convertPoint:c toLayer:target];
        glow.littleDiameter *= float(_press.scale());
    }
    glow.centerX = float(c.x);
    glow.centerY = float(c.y);
    return glow;
}

#pragma mark Rendering

- (GLSGlassSurface *)gls_surface {
    return _surface;
}

- (GLSGlassSurface *)gls_renderingSurface {
    GLSGlassContainerView *container = [self container];
    return container ? [container gls_surface] : _surface;
}

- (ShapeElement)elementInLayer:(CALayer *)target {
    CALayer *layer = self.layer.presentationLayer ?: self.layer;
    const CGRect r = target ? [layer convertRect:layer.bounds toLayer:target] : layer.bounds;
    const CGFloat side = std::min(r.size.width, r.size.height);
    const CGSize finalSize = self.bounds.size;
    const CGFloat finalRadius = std::min<CGFloat>(_cornerRadius < 0 ? CGFLOAT_MAX : _cornerRadius,
                                                  std::min(finalSize.width, finalSize.height) * 0.5);
    const CGSize own = layer.bounds.size;
    const CGFloat magnification = own.width > 0 && own.height > 0
        ? std::min(r.size.width / own.width, r.size.height / own.height) : 1;
    const CGFloat radius = _resizing ? finalRadius * magnification
                                     : std::min<CGFloat>(finalRadius * magnification, side * 0.5);
    return ShapeElement{float(CGRectGetMidX(r)), float(CGRectGetMidY(r)), float(r.size.width),
                        float(r.size.height), float(radius), self.style == GLSGlassStyleClear ? 0.f : 0.5f};
}

- (void)setNeedsGlassRender {
    GLSGlassContainerView *container = [self container];
    if (container) {
        [container setNeedsGlassRender];
        return;
    }
    if (_needsRender || _deallocating) return;
    _needsRender = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_needsRender) [self renderNow];
    });
}

- (void)driverTick {
    const BOOL wasActive = _lastTick != 0 || _resizing || _materializing;
    const BOOL pressing = [self stepPress];
    const BOOL morphing = _resizing || _materializing;
    if (_resizing && self.layer.animationKeys.count == 0) _resizing = NO;
    if (_materializing && _materializeProbe.layer.animationKeys.count == 0) _materializing = NO;
    if (wasActive && ![self wantsContinuousFrames]) [[GLSFrameDriver shared] removeClient:self];
    GLSGlassContainerView *container = [self container];
    if (container) {
        if (pressing || wasActive) [container setNeedsGlassRender];
        return;
    }
    if (pressing || morphing || _needsRender || [_surface isStale]) [self renderNow];
}

- (void)renderNow {
    _needsRender = NO;
    if ([self container]) return;

    GLSSurfaceRequest request;
    ShapeElement element = [self elementInLayer:nil];
    CALayer *layer = self.layer.presentationLayer ?: self.layer;
    const CGSize size = layer.bounds.size;
    element.centerX = float(size.width * 0.5);
    element.centerY = float(size.height * 0.5);
    request.elements.push_back(element);
    request.style = CoreStyle(_style);
    request.frost = CoreFrost(_frost);
    request.adaptsColorScheme = _adaptsColorScheme;
    request.lawSize = self.bounds.size;
    if (_resizing) {
        const CGSize to = self.bounds.size;
        const CGFloat dw = to.width - _resizeFrom.width, dh = to.height - _resizeFrom.height;
        if (std::max(std::fabs(dw), std::fabs(dh)) > 0.01) {
            request.lawFromSize = _resizeFrom;
            request.lawProgress = float(std::fabs(dw) >= std::fabs(dh) ? (size.width - _resizeFrom.width) / dw
                                                                      : (size.height - _resizeFrom.height) / dh);
        }
    }
    request.materialize = [self materializeProgress];
    request.lodBias = float(_blurLodBias);
    request.tint = _glassTintColor;
    request.glow = [self glowInLayer:nil];
    request.vibrantViews = [self gls_vibrantViews];
    request.vibrantReference = self;
    [self gls_fillTintedVibrancy:request inLayer:nil];

    _surface.source = _backdropSourceView ?: self.superview;
    _surface.backdropScale = _style == GLSGlassStyleClear || _frost == GLSGlassFrostReduced ? 0.5 : 0.25;
    [_surface render:request];
}

@end

#pragma mark - Container

@implementation GLSGlassContainerView {
    GLSGlassSurface *_surface;
    BOOL _needsRender, _deallocating;
    // The group's last scheme: -1 none, 0 light, 1 dark.
    int _groupDark;
}

- (GLSGlassSurface *)gls_surface {
    return _surface;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.backgroundColor = UIColor.clearColor;
    _surface = [[GLSGlassSurface alloc] initWithHost:self];
    __weak GLSGlassContainerView *weakSelf = self;
    _surface.sourceDidMove = ^{ [weakSelf setNeedsGlassRender]; };
    _surface.appearanceDidChange = ^(BOOL dark) {
        GLSGlassContainerView *view = weakSelf;
        if (!view) return;
        view->_groupDark = dark ? 1 : 0;
        for (UIView *subview in view.subviews) {
            if ([subview isKindOfClass:[GLSGlassView class]]) [(GLSGlassView *)subview gls_styleContentForDark:dark];
        }
    };
    _groupDark = -1;
    _surface.needsFrames = ^{
        GLSGlassContainerView *view = weakSelf;
        if (view) [[GLSFrameDriver shared] addClient:view until:CACurrentMediaTime() + 1.5];
    };
    return self;
}

- (void)dealloc {
    _deallocating = YES;
    [[GLSFrameDriver shared] removeClient:self];
}

- (void)setSpacing:(CGFloat)spacing {
    _spacing = spacing;
    [self setNeedsGlassRender];
}

- (void)setBackdropSourceView:(UIView *)backdropSourceView {
    _backdropSourceView = backdropSourceView;
    [self setNeedsGlassRender];
}

- (void)setFrost:(GLSGlassFrost)frost {
    _frost = frost;
    [self setNeedsGlassRender];
}

- (void)setScrollEdgeEffect:(GLSScrollEdgeEffectView *)scrollEdgeEffect {
    _scrollEdgeEffect = scrollEdgeEffect;
    [self setNeedsGlassRender];
}

- (void)setTracksBackdropMotion:(BOOL)tracksBackdropMotion {
    _tracksBackdropMotion = tracksBackdropMotion;
    if ([self wantsContinuousFrames]) [[GLSFrameDriver shared] addClient:self until:INFINITY];
    else [[GLSFrameDriver shared] removeClient:self];
}

- (void)setNeedsBackdropUpdate {
    [_surface setNeedsBackdropUpdate];
    [self setNeedsGlassRender];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    [self setTracksBackdropMotion:_tracksBackdropMotion];
    [self setNeedsGlassRender];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self setNeedsGlassRender];
}

- (void)didAddSubview:(UIView *)subview {
    [super didAddSubview:subview];
    if (_groupDark >= 0 && [subview isKindOfClass:[GLSGlassView class]]) {
        [(GLSGlassView *)subview gls_styleContentForDark:_groupDark == 1];
    }
    [self setNeedsGlassRender];
}

- (void)willRemoveSubview:(UIView *)subview {
    [super willRemoveSubview:subview];
    [self setNeedsGlassRender];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
        [_surface setNeedsBackdropUpdate];
    }
    [self setNeedsGlassRender];
}

- (id<CAAction>)actionForLayer:(CALayer *)layer forKey:(NSString *)event {
    id<CAAction> action = [super actionForLayer:layer forKey:event];
    if (layer == self.layer) FollowAnimation(self, action);
    return action;
}

- (void)followAction:(id<CAAction>)action {
    FollowAnimation(self, action);
}

- (BOOL)wantsContinuousFrames {
    return _tracksBackdropMotion && self.window != nil;
}

- (void)setNeedsGlassRender {
    if (_needsRender || _deallocating) return;
    _needsRender = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_needsRender) [self renderNow];
    });
}

- (void)driverTick {
    [self renderNow];
}

- (void)renderNow {
    _needsRender = NO;
    _surface.source = _backdropSourceView ?: self.superview;

    GLSSurfaceRequest request;
    CALayer *selfLayer = self.layer.presentationLayer ?: self.layer;
    CGFloat lawSide = CGFLOAT_MAX;
    BOOL first = YES;
    NSMutableArray<UIView *> *vibrant = [NSMutableArray array];
    GLSGlassView *vibrantGlass = nil;
    for (UIView *subview in self.subviews) {
        if (![subview isKindOfClass:[GLSGlassView class]] || subview.hidden || subview.alpha <= 0) continue;
        GLSGlassView *glass = (GLSGlassView *)subview;
        if ([glass materializeProgress] <= 0.5f) continue;
        if (first) {
            request.style = CoreStyle(glass.style);
            request.lodBias = float(glass.blurLodBias);
            request.tint = glass.glassTintColor;
            _surface.backdropScale = glass.style == GLSGlassStyleClear || _frost == GLSGlassFrostReduced ? 0.5 : 0.25;
            first = NO;
        }
        GlowState glow = [glass glowInLayer:selfLayer];
        glow.element = int(request.elements.size());
        if (glow.bigAlpha > request.glow.bigAlpha || glow.littleAlpha > request.glow.littleAlpha) request.glow = glow;
        NSArray<UIView *> *glassVibrant = [glass gls_vibrantViews];
        if (glassVibrant.count) {
            vibrantGlass = vibrant.count ? nil : glass;
            [vibrant addObjectsFromArray:glassVibrant];
        }
        [glass gls_fillTintedVibrancy:request inLayer:selfLayer];
        ShapeElement e = [glass elementInLayer:selfLayer];
        e.ovalization = 0.f;
        request.elements.push_back(e);
        if (std::min(e.width, e.height) < lawSide) {
            lawSide = std::min(e.width, e.height);
            request.lawSize = CGSizeMake(e.width, e.height);
        }
        if (request.elements.size() == GLS_MAX_ELEMENTS) break;
    }
    request.smoothness = float(_spacing);
    request.frost = CoreFrost(_frost);
    request.lumaEdge = _scrollEdgeEffect;
    request.vibrantViews = vibrant;
    request.vibrantReference = vibrantGlass;
    [_surface render:request];
}

@end
