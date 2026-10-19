//
//  GLSSwitch.mm
//  Glassify
//
//  Copyright © 2026 Hung Phan.
//  See LICENSE file for license information.
//

#import "Glassify/GLSSwitch.h"

#import "Glassify/GLSLiquidLensView.h"

#include <algorithm>
#include <cmath>

namespace {

constexpr CGFloat kWidth = 63, kHeight = 28;
constexpr CGFloat kKnobOff = 20.5, kKnobOn = 42.5, kKnobY = 14;
constexpr CGFloat kImageWidth = 630, kSolid = 63, kClear = 567;

// A critically damped spring (damping 1) in closed form, stepped per frame.
struct CriticalSpring {
    double value = 0, velocity = 0;
    void step(double target, double response, double dt) {
        const double w = 2 * M_PI / response;
        const double x0 = value - target, v0 = velocity;
        const double e = std::exp(-w * dt);
        value = target + (x0 + (v0 + w * x0) * dt) * e;
        velocity = (v0 - (v0 + w * x0) * w * dt) * e;
    }
};

}

@interface GLSSwitchTicker : NSObject
@property (nonatomic, copy) void (^tick)(void);
- (void)fire;
@end
@implementation GLSSwitchTicker
- (void)fire { self.tick(); }
@end

@implementation GLSSwitch {
    UIView *_offWell, *_onWell;
    CAGradientLayer *_gradient;
    GLSLiquidLensView *_knob;
    BOOL _displayedOn, _pressed, _moved, _startOn, _static;
    CGFloat _startX, _currentX;
    CriticalSpring _track;
    double _trackTarget;
    CADisplayLink *_link;
    CFTimeInterval _lastTick;
}

- (instancetype)initWithFrame:(CGRect)frame {
    frame.size = CGSizeMake(kWidth, kHeight);
    if (!(self = [super initWithFrame:frame])) return nil;
    [self commonInit];
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    if (!(self = [super initWithCoder:coder])) return nil;
    [self commonInit];
    _onTintColor = [coder decodeObjectOfClass:UIColor.class forKey:@"GLSSwitchOnTintColor"];
    _thumbTintColor = [coder decodeObjectOfClass:UIColor.class forKey:@"GLSSwitchThumbTintColor"];
    [self updateColors];
    self.on = [coder decodeBoolForKey:@"GLSSwitchOn"];
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [super encodeWithCoder:coder];
    [coder encodeBool:_on forKey:@"GLSSwitchOn"];
    if (_onTintColor) [coder encodeObject:_onTintColor forKey:@"GLSSwitchOnTintColor"];
    if (_thumbTintColor) [coder encodeObject:_thumbTintColor forKey:@"GLSSwitchThumbTintColor"];
}

- (void)commonInit {
    _offWell = [[UIView alloc] initWithFrame:self.bounds];
    _offWell.userInteractionEnabled = NO;
    _offWell.layer.cornerRadius = kHeight / 2;
    _offWell.backgroundColor = UIColor.tertiaryLabelColor;
    [self addSubview:_offWell];
    _onWell = [[UIView alloc] initWithFrame:self.bounds];
    _onWell.userInteractionEnabled = NO;
    _onWell.layer.cornerRadius = kHeight / 2;
    [self addSubview:_onWell];
    _gradient = [CAGradientLayer layer];
    _gradient.startPoint = CGPointMake(0, 0.5);
    _gradient.endPoint = CGPointMake(1, 0.5);
    _gradient.locations = @[ @0, @(kSolid / kImageWidth), @(kClear / kImageWidth), @1 ];
    [_onWell.layer addSublayer:_gradient];
    _knob = [[GLSLiquidLensView alloc] initWithFrame:CGRectMake(0, 0, 37, 24)];
    _knob.style = GLSLiquidLensStyleSmall;
    _knob.restingColor = UIColor.whiteColor;
    _knob.warpsContentBelow = YES;
    [self addSubview:_knob];
    [self updateColors];
    [self setStatic:YES];
    [self layoutKnob];
}

// UISwitch keeps its size whatever frame it is given; its intrinsic size is the 2 pt narrower alignment rect.
- (void)setFrame:(CGRect)frame {
    frame.size = CGSizeMake(kWidth, kHeight);
    [super setFrame:frame];
}
- (CGSize)intrinsicContentSize { return CGSizeMake(kWidth - 2, kHeight); }
- (UIEdgeInsets)alignmentRectInsets { return UIEdgeInsetsMake(0, 0, 0, 2); }

#pragma mark - Accessibility

- (BOOL)isAccessibilityElement { return YES; }

- (UIAccessibilityTraits)accessibilityTraits {
    UIAccessibilityTraits t = [super accessibilityTraits] | UIAccessibilityTraitButton;
    if (@available(iOS 17.0, *)) t |= UIAccessibilityTraitToggleButton;
    if (!self.enabled) t |= UIAccessibilityTraitNotEnabled;
    return t;
}

- (NSString *)accessibilityValue { return _on ? @"1" : @"0"; }

// The XCUIElementType UI tests see; an informal method of the accessibility runtime.
- (NSUInteger)_accessibilityAutomationType { return 40; }
- (CGSize)sizeThatFits:(CGSize)size { return CGSizeMake(kWidth, kHeight); }

- (void)didMoveToSuperview {
    [super didMoveToSuperview];
    _knob.backdropSourceView = self.superview ?: self;
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    [self updateColors];
}

- (void)setOnTintColor:(UIColor *)onTintColor {
    _onTintColor = onTintColor;
    [self updateColors];
}

- (void)setThumbTintColor:(UIColor *)thumbTintColor {
    _thumbTintColor = thumbTintColor;
    [self updateColors];
}

- (void)updateColors {
    _knob.restingColor = _thumbTintColor ?: UIColor.whiteColor;
    UIColor *on = [(_onTintColor ?: UIColor.systemGreenColor) resolvedColorWithTraitCollection:self.traitCollection];
    _gradient.colors = @[ (id)on.CGColor, (id)on.CGColor, (id)[on colorWithAlphaComponent:0].CGColor,
                          (id)[on colorWithAlphaComponent:0].CGColor ];
    [self setStatic:_static];
}

- (void)setOn:(BOOL)on { [self setOn:on animated:NO]; }

- (void)setOn:(BOOL)on animated:(BOOL)animated {
    _on = on;
    if (_pressed) return;
    [self showOn:on animated:animated];
    [self moveKnobAnimated:animated];
}

#pragma mark Track

// At rest the on well is filled; while moving, the gradient image slides instead.
- (void)setStatic:(BOOL)isStatic {
    _static = isStatic;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _gradient.hidden = isStatic;
    _onWell.clipsToBounds = !isStatic;
    _onWell.backgroundColor = isStatic && _displayedOn ? (_onTintColor ?: UIColor.systemGreenColor) : nil;
    [self placeGradient];
    [CATransaction commit];
}

- (void)placeGradient {
    const BOOL rtl = self.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
    const CGFloat s = CGFloat(_track.value);
    const CGFloat offX = kSolid - kImageWidth, x = offX * (1 - s);
    _gradient.frame = CGRectMake(rtl ? kWidth - kImageWidth - x : x, 0, kImageWidth, kHeight);
    _gradient.transform = rtl ? CATransform3DMakeScale(-1, 1, 1) : CATransform3DIdentity;
}

- (void)showOn:(BOOL)on animated:(BOOL)animated {
    _displayedOn = on;
    _trackTarget = on ? 1 : 0;
    if (!animated) {
        _track.value = _trackTarget;
        _track.velocity = 0;
        [self setStatic:!_pressed];
        return;
    }
    [self setStatic:NO];
    [self startTicking];
}

- (void)startTicking {
    if (_link) return;
    GLSSwitchTicker *ticker = [GLSSwitchTicker new];
    __weak GLSSwitch *weakSelf = self;
    ticker.tick = ^{ [weakSelf tick]; };
    _link = [CADisplayLink displayLinkWithTarget:ticker selector:@selector(fire)];
    [_link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    _lastTick = 0;
}

- (void)tick {
    const CFTimeInterval now = CACurrentMediaTime();
    const double dt = _lastTick == 0 ? 1.0 / 60 : std::min(now - _lastTick, 1.0 / 20);
    _lastTick = now;
    _track.step(_trackTarget, _trackTarget > 0.5 ? 0.4 : 0.68, dt);
    const BOOL settled = std::fabs(_track.value - _trackTarget) < 1e-3 && std::fabs(_track.velocity) < 1e-2;
    if (settled) {
        _track.value = _trackTarget;
        _track.velocity = 0;
    }
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [self placeGradient];
    [CATransaction commit];
    [_knob setNeedsBackdropUpdate];
    if (settled && !_pressed && !_knob.lifted && _knob.liftProgress <= 0) {
        [_link invalidate];
        _link = nil;
        [self setStatic:YES];
        [_knob setNeedsBackdropUpdate];
    }
}

#pragma mark Knob

- (CGFloat)knobXForOn:(BOOL)on offset:(CGFloat)offset adjusted:(BOOL)adjusted {
    const BOOL rtl = self.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
    const CGFloat lo = rtl ? kWidth - kKnobOn : kKnobOff, hi = rtl ? kWidth - kKnobOff : kKnobOn;
    const CGFloat rest = (on != rtl) ? hi : lo;
    if (!adjusted) return rest;
    const CGFloat x = rest + offset;
    CGFloat c = std::min(std::max(x, lo), hi);
    if (!UIAccessibilityIsReduceMotionEnabled() && x != c) {
        const CGFloat k = x < lo ? -12 : 12;
        c += k * (1 - 1 / (1 + 0.55 * (x - c) / k));
    }
    return c;
}

- (CGSize)knobSizePressed:(BOOL)pressed {
    if (pressed && !UIAccessibilityIsReduceMotionEnabled()) return CGSizeMake(58, 38.333333);
    return CGSizeMake(37, 24);
}

- (void)layoutKnob {
    const CGSize size = [self knobSizePressed:_pressed];
    _knob.bounds = CGRectMake(0, 0, size.width, size.height);
    _knob.center = CGPointMake([self knobXForOn:_displayedOn offset:0 adjusted:NO], kKnobY);
}

- (void)moveKnobAnimated:(BOOL)animated {
    const CGFloat x = [self knobXForOn:_pressed ? _startOn : _displayedOn offset:_pressed ? [self panOffset] : 0
                              adjusted:_pressed];
    void (^move)(void) = ^{ self->_knob.center = CGPointMake(x, kKnobY); };
    if (animated) {
        GLSAnimateWithSpring(1.0, 0.3, move, nil);
    } else {
        [UIView performWithoutAnimation:move];
    }
}

- (CGFloat)panOffset { return _currentX - _startX; }

#pragma mark Touches

- (BOOL)beginTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    _pressed = YES;
    _moved = NO;
    _startOn = _displayedOn;
    _startX = _currentX = [touch locationInView:self].x;
    [self setStatic:NO];
    [self startTicking];
    [self moveKnobAnimated:YES];
    const CGSize size = [self knobSizePressed:YES];
    [_knob setLifted:!UIAccessibilityIsReduceMotionEnabled() animated:YES alongsideAnimations:^{
        self->_knob.bounds = CGRectMake(0, 0, size.width, size.height);
        [self->_knob layoutIfNeeded];
    }];
    return YES;
}

- (BOOL)continueTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    _currentX = [touch locationInView:self].x;
    if (std::fabs(_currentX - _startX) > 2) _moved = YES;
    [self moveKnobAnimated:YES];
    if (_moved) {
        const CGFloat x = [self knobXForOn:_startOn offset:[self panOffset] adjusted:YES];
        const BOOL rtl = self.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
        const BOOL on = rtl ? x < kWidth / 2 : x > kWidth / 2;
        if (on != _displayedOn) [self showOn:on animated:YES];
    }
    return YES;
}

- (void)endTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    [self finishTracking:YES];
}

- (void)cancelTrackingWithEvent:(UIEvent *)event {
    [self finishTracking:NO];
}

- (void)finishTracking:(BOOL)commit {
    const BOOL on = !commit ? _startOn : (_moved ? _displayedOn : !_startOn);
    _pressed = NO;
    const BOOL changed = on != _on;
    _on = on;
    if (on != _displayedOn) [self showOn:on animated:YES];
    [self startTicking];
    [self moveKnobAnimated:YES];
    const CGSize size = [self knobSizePressed:NO];
    [_knob setLifted:NO animated:YES alongsideAnimations:^{
        self->_knob.bounds = CGRectMake(0, 0, size.width, size.height);
        [self->_knob layoutIfNeeded];
    }];
    if (changed) {
        [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
        [self sendActionsForControlEvents:UIControlEventValueChanged | UIControlEventPrimaryActionTriggered];
    }
}

@end
