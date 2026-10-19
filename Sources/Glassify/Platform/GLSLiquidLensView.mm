//
//  GLSLiquidLensView.mm
//  Glassify
//
//  Copyright © 2026 Hung Phan.
//  See LICENSE file for license information.
//

#import "Glassify/GLSLiquidLensView.h"

#import "GLSGlassSurface.h"
#import "GLSGlassViewInternal.h"
#import "GLSRenderer.h"

#include <algorithm>
#include <cmath>

using namespace glassify;

namespace {
}

// iOS 17 takes the spring directly; earlier systems get the same one through the damping-ratio API.
void GLSAnimateWithSpring(CGFloat damping, CGFloat response, void (^animations)(void), void (^completion)(BOOL)) {
    if (@available(iOS 17.0, *)) {
        [UIView animateWithSpringDuration:response bounce:1 - damping initialSpringVelocity:0 delay:0
                                  options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                               animations:animations completion:completion];
        return;
    }
    CASpringAnimation *probe = [CASpringAnimation animation];
    probe.mass = 1;
    probe.stiffness = std::pow(2 * M_PI / response, 2);
    probe.damping = 4 * M_PI * damping / response;
    [UIView animateWithDuration:probe.settlingDuration delay:0 usingSpringWithDamping:damping initialSpringVelocity:0
                        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                     animations:animations completion:completion];
}

namespace {

// A damped spring component, integrated per frame for the flex stretch.
struct FrameSpring {
    float value = 0, velocity = 0;
    void step(float target, float damping, float response, float dt) {
        const float omega = 2.f * float(M_PI) / response;
        for (; dt > 0; dt -= 1.f / 240.f) {
            const float h = std::min(dt, 1.f / 240.f);
            velocity += (-omega * omega * (value - target) - 2.f * damping * omega * velocity) * h;
            value += velocity * h;
        }
    }
};

// Rolls off smoothly beyond [lo, hi] instead of clamping hard.
float SoftClamp(float x, float lo, float hi) {
    const float m = (hi - lo) / 3.f;
    if (m <= 0) return std::min(std::max(x, lo), hi);
    if (x < lo) {
        const float a = lo - m;
        return a + m * (1.f + std::tanh(0.55f * (x - a) / m - 0.55f));
    }
    if (x > hi) return hi + m * std::tanh(0.55f * (x - hi) / m);
    return x;
}

float Lerp(float a, float b, float t) { return a + (b - a) * t; }

void RedrawTree(UIView *view) {
    [view setNeedsDisplay];
    [view.layer displayIfNeeded];
    for (UIView *subview in view.subviews) RedrawTree(subview);
}

}

@interface GLSLiquidLensView () <GLSFrameClient>
@end

@implementation GLSLiquidLensView {
    GLSGlassSurface *_surface;
    // Its center.x is the lift progress, animated by the lift spring.
    UIView *_liftProbe;
    CFTimeInterval _liftTimestamp;
    id<MTLTexture> _content;
    BOOL _contentDirty;
    // Draws at most once per frame: a third draw in one run-loop turn blocks in -nextDrawable.
    BOOL _driven;
    BOOL _needsRender;
    // Flex stretch, driven by acceleration only.
    CGPoint _lastCenter;
    CGPoint _lastVelocity, _acceleration;
    CFTimeInterval _lastTick;
    FrameSpring _scaleX, _scaleY, _driftX, _driftY;
    // Small lens: the opaque knob shown at rest.
    UIView *_resting;
    // Small lens: the lens path needs a content texture even without lifted content.
    id<MTLTexture> _emptyContent;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.userInteractionEnabled = NO;
    self.backgroundColor = UIColor.clearColor;
    _surface = [[GLSGlassSurface alloc] initWithHost:self];
    _surface.backdropScale = 1.0;
    _surface.hidden = YES;
    _liftProbe = [[UIView alloc] initWithFrame:CGRectZero];
    _liftProbe.userInteractionEnabled = NO;
    [self addSubview:_liftProbe];
    _scaleX.value = _scaleY.value = 1;
    __weak GLSLiquidLensView *weakSelf = self;
    _surface.sourceDidMove = ^{ [weakSelf setNeedsRender]; };
    return self;
}

- (void)dealloc {
    [[GLSFrameDriver shared] removeClient:self];
}

- (void)setStyle:(GLSLiquidLensStyle)style {
    _style = style;
    if (style == GLSLiquidLensStyleSmall && !_resting) {
        _resting = [[UIView alloc] initWithFrame:self.bounds];
        _resting.userInteractionEnabled = NO;
        _resting.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _resting.layer.cornerCurve = kCACornerCurveContinuous;
        _resting.backgroundColor = _restingColor;
        [self insertSubview:_resting atIndex:0];
        [self updateRestingShadow];
    }
    [self setNeedsRender];
}

- (void)setRestingColor:(UIColor *)restingColor {
    _restingColor = restingColor;
    _resting.backgroundColor = restingColor;
}

- (void)setRestingShadow:(BOOL)restingShadow {
    _restingShadow = restingShadow;
    [self updateRestingShadow];
}

- (void)updateRestingShadow {
    CALayer *l = _resting.layer;
    l.shadowColor = UIColor.blackColor.CGColor;
    l.shadowOpacity = _restingShadow ? 0.14f : 0.f;
    l.shadowRadius = 5;
    l.shadowOffset = CGSizeMake(0, 1);
}

- (void)setLensTintColor:(UIColor *)lensTintColor {
    _lensTintColor = lensTintColor;
    [self setNeedsRender];
}

- (void)setLiftedContentView:(UIView *)liftedContentView {
    _liftedContentView = liftedContentView;
    _contentDirty = YES;
}

- (void)setNeedsContentUpdate {
    _contentDirty = YES;
}

- (void)setBackdropBaseColor:(UIColor *)backdropBaseColor {
    _backdropBaseColor = backdropBaseColor;
    _surface.backdropBaseColor = backdropBaseColor;
}

- (void)setNeedsBackdropUpdate {
    [_surface setNeedsBackdropUpdate];
}

- (void)setUnderlayGlassView:(GLSGlassView *)underlayGlassView {
    _underlayGlassView = underlayGlassView;
    [self bindUnderlay];
}

// The surface that draws the underlay glass changes when it joins or leaves a container.
- (void)bindUnderlay {
    GLSGlassSurface *surface = _underlayGlassView.gls_renderingSurface;
    if (_surface.underlaySurface == surface) return;
    _surface.underlaySurface.keepsOutput = NO;
    surface.keepsOutput = YES;
    _surface.underlaySurface = surface;
    [_surface setNeedsBackdropUpdate];
}

- (CGFloat)liftProgress {
    CALayer *probe = _liftProbe.layer.presentationLayer ?: _liftProbe.layer;
    return probe.position.x;
}

- (CGFloat)liftAlpha {
    return std::min(std::max(4 * self.liftProgress, 0.0), 1.0);
}

- (CFTimeInterval)liftedDuration {
    return _lifted ? CACurrentMediaTime() - _liftTimestamp : 0;
}

- (void)setLifted:(BOOL)lifted animated:(BOOL)animated alongsideAnimations:(void (^)(void))alongside {
    if (lifted == _lifted) {
        if (alongside) alongside();
        return;
    }
    _lifted = lifted;
    if (lifted) {
        _liftTimestamp = CACurrentMediaTime();
        _contentDirty = YES;
    }
    void (^body)(void) = ^{
        self->_liftProbe.center = CGPointMake(lifted ? 1 : 0, 0);
        self->_resting.alpha = lifted ? 0 : 1;
        if (alongside) alongside();
    };
    if (animated) {
        if (_style == GLSLiquidLensStyleSmall) {
            GLSAnimateWithSpring(lifted ? 0.625 : 0.7, lifted ? 0.27 : 0.5, body, nil);
        } else {
            GLSAnimateWithSpring(1.0, 0.25, body, nil);
        }
    } else {
        body();
    }
    _lastTick = 0;
    _driven = YES;
    [[GLSFrameDriver shared] addClient:self until:INFINITY];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
        _contentDirty = YES;
        [_surface setNeedsBackdropUpdate];
        [self setNeedsRender];
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _resting.layer.cornerRadius = std::min(self.bounds.size.width, self.bounds.size.height) / 2;
    if (_restingShadow) _resting.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:_resting.bounds
                                                                               cornerRadius:_resting.layer.cornerRadius].CGPath;
    [self setNeedsRender];
}

// Drawing inside the CA commit would repeat the driver's frame, so it waits for the next turn.
- (void)setNeedsRender {
    if (_driven || _needsRender) return;
    _needsRender = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_needsRender && !self->_driven) [self render];
        self->_needsRender = NO;
    });
}

#pragma mark Frames

- (BOOL)wantsContinuousFrames {
    const float p = float(self.liftProgress);
    const BOOL settling = std::fabs(_scaleX.value - 1) > 1e-3f || std::fabs(_scaleY.value - 1) > 1e-3f ||
                          std::fabs(_scaleX.velocity) > 1e-3f || std::fabs(_driftX.value) > 0.01f;
    return _lifted || p > 0.f || settling;
}

- (void)driverTick {
    const CFTimeInterval now = CACurrentMediaTime();
    const float dt = _lastTick == 0 ? 1.f / 60.f : float(std::min(now - _lastTick, 1.0 / 20.0));
    [self stepFlex:dt first:_lastTick == 0];
    _lastTick = now;
    [self render];
    if (![self wantsContinuousFrames]) {
        _lastTick = 0;
        _driven = NO;
        [[GLSFrameDriver shared] removeClient:self];
    }
}

// Stretches the lens along its acceleration and squashes it across.
- (void)stepFlex:(float)dt first:(BOOL)first {
    CALayer *layer = self.layer.presentationLayer ?: self.layer;
    const CGPoint c = layer.position;
    if (first) {
        _lastCenter = c;
        _lastVelocity = CGPointZero;
        _acceleration = CGPointZero;
    }
    const CGPoint v = CGPointMake((c.x - _lastCenter.x) / dt, (c.y - _lastCenter.y) / dt);
    const CGPoint a = CGPointMake((v.x - _lastVelocity.x) / dt, (v.y - _lastVelocity.y) / dt);
    _acceleration = CGPointMake(_acceleration.x + (a.x - _acceleration.x) * 0.5, _acceleration.y + (a.y - _acceleration.y) * 0.5);
    _lastCenter = c;
    _lastVelocity = v;

    const CGSize size = self.bounds.size;
    const float t = std::min(std::max((float(std::min(size.width, size.height)) - 37.f) / (70.f - 37.f), 0.f), 1.f);
    const float pts = Lerp(10, 100, t), minS = Lerp(0.9f, 0.75f, t), maxS = Lerp(1.1f, 1.15f, t);
    const float norm = Lerp(2000, 2500, t), damping = Lerp(0.56f, 1.0f, t), response = Lerp(0.444f, 0.5f, t);
    const float w = std::max(float(size.width), 1.f), h = std::max(float(size.height), 1.f);
    const float loX = std::max(minS, (w - pts) / w), hiX = std::min(maxS, (w + pts) / w);
    const float loY = std::max(minS, (h - pts) / h), hiY = std::min(maxS, (h + pts) / h);
    float sx = 1, sy = 1, dx = 0, dy = 0;
    const float nx = _lifted ? float(_acceleration.x) / norm : 0.f;
    const float ny = _lifted ? float(_acceleration.y) / norm : 0.f;
    if (nx != 0) {
        const float ax = SoftClamp(1 + nx * (hiX - 1), loX, hiX);
        sx += ax - 1;
        dx = (1 - ax) * 0.2f * w;
        sy += SoftClamp(1 + nx * (loY - 1), loY, hiY) - 1;
    }
    if (ny != 0) {
        const float ay = SoftClamp(1 + ny * (hiY - 1), loY, hiY);
        sy += ay - 1;
        dy = (1 - ay) * 0.2f * h;
        sx += SoftClamp(1 + ny * (loX - 1), loX, hiX) - 1;
    }
    _scaleX.step(sx, damping, response, dt);
    _scaleY.step(sy, damping, response, dt);
    _driftX.step(dx, damping, response, dt);
    _driftY.step(dy, damping, response, dt);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    CATransform3D tr = CATransform3DMakeTranslation(_driftX.value, _driftY.value, 0);
    tr = CATransform3DScale(tr, _scaleX.value, _scaleY.value, 1);
    self.layer.transform = tr;
    [CATransaction commit];
}

#pragma mark Rendering

- (void)captureContentIfNeeded {
    UIView *view = _liftedContentView;
    if (!_contentDirty || !view) return;
    _contentDirty = NO;
    GLSRenderer *renderer = [GLSRenderer shared];
    const CGFloat scale = self.window ? self.window.screen.scale : UIScreen.mainScreen.scale;
    const size_t w = std::max<size_t>(1, size_t(std::ceil(view.bounds.size.width * scale)));
    const size_t h = std::max<size_t>(1, size_t(std::ceil(view.bounds.size.height * scale)));
    if (!_content || _content.width != w || _content.height != h) {
        MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                                                                      width:w
                                                                                     height:h
                                                                                  mipmapped:NO];
        td.usage = MTLTextureUsageShaderRead;
        _content = [renderer.device newTextureWithDescriptor:td];
    }
    if (!view.window && view.overrideUserInterfaceStyle != self.traitCollection.userInterfaceStyle) {
        view.overrideUserInterfaceStyle = self.traitCollection.userInterfaceStyle;
        [view layoutIfNeeded];
        RedrawTree(view);
    }
    NSMutableData *bitmap = [NSMutableData dataWithLength:w * h * 4];
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef ctx = CGBitmapContextCreate(bitmap.mutableBytes, w, h, 8, w * 4, space,
                                             kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
    CGColorSpaceRelease(space);
    if (!ctx) return;
    CGContextTranslateCTM(ctx, 0, h);
    CGContextScaleCTM(ctx, scale, -scale);
    [view.layer renderInContext:ctx];
    CGContextRelease(ctx);
    [_content replaceRegion:MTLRegionMake2D(0, 0, w, h) mipmapLevel:0 withBytes:bitmap.bytes bytesPerRow:w * 4];
}

- (void)render {
    _needsRender = NO;
    [self bindUnderlay];
    const float p = std::min(std::max(float(self.liftProgress), 0.f), 1.f);
    UIView *source = _backdropSourceView ?: self.superview;
    const BOOL visible = p > 0.f && source && self.window;
    _surface.hidden = !visible;
    _resting.layer.hidden = visible;
    if (!visible) return;
    [self captureContentIfNeeded];

    CALayer *layer = self.layer.presentationLayer ?: self.layer;
    const CGSize size = layer.bounds.size;
    GLSSurfaceRequest request;
    request.elements.push_back(ShapeElement{float(size.width / 2), float(size.height / 2), float(size.width),
                                            float(size.height), float(std::min(size.width, size.height) / 2), 0.5f});
    request.style = GlassStyle::Clear;
    request.lawSize = size;
    GlassInputs inputs;
    if (_style == GLSLiquidLensStyleSmall) {
        const Appearance appearance = GLSTraitAppearance(self.traitCollection);
        SmallLensMaterial material = switchLensMaterial(appearance);
        CGFloat r = 0, g = 0, b = 0, a = 0;
        if (_lensTintColor && [[_lensTintColor resolvedColorWithTraitCollection:self.traitCollection] getRed:&r green:&g blue:&b alpha:&a]) {
            const float tint[3] = {float(r), float(g), float(b)};
            material = tintedLensMaterial(tint);
        }
        const float h = float(_lifted ? self.bounds.size.height : size.height);
        inputs = smallLiquidLensInputs(p, true, h, appearance, material, _warpsContentBelow ? 9.f : 0.f,
                                       _warpsContentBelow ? 50.f : 0.f);
        CALayer *resting = _resting.layer.presentationLayer ?: _resting.layer;
        if ([[UIColor colorWithCGColor:_resting.backgroundColor.CGColor ?: UIColor.clearColor.CGColor]
                getRed:&r green:&g blue:&b alpha:&a]) {
            inputs.restingColor[0] = float(r); inputs.restingColor[1] = float(g); inputs.restingColor[2] = float(b);
            inputs.restingColor[3] = float(a * resting.opacity);
        }
    } else {
        inputs = liquidLensInputs(p, _lifted);
    }
    request.inputs = &inputs;
    request.opacity = _lifted || _style == GLSLiquidLensStyleSmall ? 1.f : std::min(4.f * p, 1.f);
    if (_style == GLSLiquidLensStyleSmall) {
        if (!_emptyContent) {
            MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                                                                          width:1 height:1 mipmapped:NO];
            td.usage = MTLTextureUsageShaderRead;
            _emptyContent = [[GLSRenderer shared].device newTextureWithDescriptor:td];
            const uint32_t clear = 0;
            [_emptyContent replaceRegion:MTLRegionMake2D(0, 0, 1, 1) mipmapLevel:0 withBytes:&clear bytesPerRow:4];
        }
        request.content = _emptyContent;
        request.contentRect = CGRectMake(0, 0, size.width, size.height);
    } else if (_content && _liftedContentView && self.superview) {
        request.content = _content;
        CALayer *superLayer = self.superview.layer.presentationLayer ?: self.superview.layer;
        request.contentRect = [superLayer convertRect:_liftedContentFrame toLayer:layer];
    }
    _surface.source = source;
    [_surface render:request];
}

@end
