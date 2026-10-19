//
//  GLSSlider.mm
//  Glassify
//
//  Copyright © 2026 Hung Phan.
//  See LICENSE file for license information.
//

#import "Glassify/GLSSlider.h"

#import "Glassify/GLSLiquidLensView.h"

#include <algorithm>
#include <cmath>

namespace {
constexpr CGFloat kKnobW = 37, kKnobH = 24, kPressedScale = 1.55, kTrackH = 6;
constexpr CGFloat kPanHysteresis = 10, kProjectionTime = 0.099, kProjectionThreshold = 10;
// The gap between a value image and the end of the track.
constexpr CGFloat kImageGap = 11;
constexpr float kAccessibilityStep = 0.1f;
}

@implementation GLSSlider {
    UIView *_maxTrack, *_minTrack;
    UIImageView *_minImageView, *_maxImageView;
    GLSLiquidLensView *_knob;
    BOOL _tracking, _dragging;
    CGFloat _touchStartX;
    // Pan driver state: the unclamped normalized value and the velocity samples in pt/s.
    CGFloat _panOriginX, _lastTranslation, _dragT;
    CGFloat _velPrev, _velLast, _lastMoveX;
    NSTimeInterval _lastMoveTime;
    int _velSamples;
    // The release spring.
    CADisplayLink *_settleLink;
    CGFloat _settleTarget, _settleT, _settleV;
    CFTimeInterval _settleLast;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    [self commonInit];
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    if (!(self = [super initWithCoder:coder])) return nil;
    [self commonInit];
    if ([coder containsValueForKey:@"GLSSliderMaximumValue"]) {
        _minimumValue = [coder decodeFloatForKey:@"GLSSliderMinimumValue"];
        _maximumValue = [coder decodeFloatForKey:@"GLSSliderMaximumValue"];
        _value = [coder decodeFloatForKey:@"GLSSliderValue"];
        _continuous = [coder decodeBoolForKey:@"GLSSliderContinuous"];
    }
    _minimumTrackTintColor = [coder decodeObjectOfClass:UIColor.class forKey:@"GLSSliderMinimumTrackTintColor"];
    _maximumTrackTintColor = [coder decodeObjectOfClass:UIColor.class forKey:@"GLSSliderMaximumTrackTintColor"];
    _thumbTintColor = [coder decodeObjectOfClass:UIColor.class forKey:@"GLSSliderThumbTintColor"];
    self.minimumValueImage = [coder decodeObjectOfClass:UIImage.class forKey:@"GLSSliderMinimumValueImage"];
    self.maximumValueImage = [coder decodeObjectOfClass:UIImage.class forKey:@"GLSSliderMaximumValueImage"];
    [self updateColors];
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [super encodeWithCoder:coder];
    [coder encodeFloat:_minimumValue forKey:@"GLSSliderMinimumValue"];
    [coder encodeFloat:_maximumValue forKey:@"GLSSliderMaximumValue"];
    [coder encodeFloat:_value forKey:@"GLSSliderValue"];
    [coder encodeBool:_continuous forKey:@"GLSSliderContinuous"];
    if (_minimumTrackTintColor) [coder encodeObject:_minimumTrackTintColor forKey:@"GLSSliderMinimumTrackTintColor"];
    if (_maximumTrackTintColor) [coder encodeObject:_maximumTrackTintColor forKey:@"GLSSliderMaximumTrackTintColor"];
    if (_thumbTintColor) [coder encodeObject:_thumbTintColor forKey:@"GLSSliderThumbTintColor"];
    if (_minimumValueImage) [coder encodeObject:_minimumValueImage forKey:@"GLSSliderMinimumValueImage"];
    if (_maximumValueImage) [coder encodeObject:_maximumValueImage forKey:@"GLSSliderMaximumValueImage"];
}

- (void)commonInit {
    _maximumValue = 1;
    _continuous = YES;
    _maxTrack = [UIView new];
    _maxTrack.userInteractionEnabled = NO;
    _maxTrack.layer.cornerRadius = kTrackH / 2;
    _maxTrack.clipsToBounds = YES;
    [self addSubview:_maxTrack];
    _minTrack = [UIView new];
    _minTrack.userInteractionEnabled = NO;
    _minTrack.layer.cornerRadius = kTrackH / 2;
    [_maxTrack addSubview:_minTrack];
    _knob = [[GLSLiquidLensView alloc] initWithFrame:CGRectMake(0, 0, kKnobW, kKnobH)];
    _knob.style = GLSLiquidLensStyleSmall;
    _knob.restingColor = UIColor.whiteColor;
    _knob.restingShadow = YES;
    [self addSubview:_knob];
    [self updateColors];
    self.isAccessibilityElement = YES;
}

- (CGSize)intrinsicContentSize { return CGSizeMake(UIViewNoIntrinsicMetric, 34); }
// UISlider reports the thumb's width.
- (CGSize)sizeThatFits:(CGSize)size { return CGSizeMake(kKnobW, 34); }

#pragma mark - Geometry

- (CGRect)minimumValueImageRectForBounds:(CGRect)bounds {
    if (!_minimumValueImage) return CGRectZero;
    const CGSize s = _minimumValueImage.size;
    const BOOL rtl = self.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
    return CGRectMake(rtl ? CGRectGetMaxX(bounds) - s.width : CGRectGetMinX(bounds), CGRectGetMidY(bounds) - s.height / 2,
                      s.width, s.height);
}

- (CGRect)maximumValueImageRectForBounds:(CGRect)bounds {
    if (!_maximumValueImage) return CGRectZero;
    const CGSize s = _maximumValueImage.size;
    const BOOL rtl = self.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
    return CGRectMake(rtl ? CGRectGetMinX(bounds) : CGRectGetMaxX(bounds) - s.width, CGRectGetMidY(bounds) - s.height / 2,
                      s.width, s.height);
}

- (CGRect)trackRectForBounds:(CGRect)bounds {
    CGFloat lead = _minimumValueImage ? _minimumValueImage.size.width + kImageGap : 0;
    CGFloat trail = _maximumValueImage ? _maximumValueImage.size.width + kImageGap : 0;
    if (self.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft) std::swap(lead, trail);
    return CGRectMake(CGRectGetMinX(bounds) + lead, CGRectGetMidY(bounds) - kTrackH / 2,
                      std::max(bounds.size.width - lead - trail, CGFloat(0)), kTrackH);
}

// Rounded to whole points, as UISlider does.
- (CGRect)thumbRectForBounds:(CGRect)bounds trackRect:(CGRect)rect value:(float)value {
    const CGFloat range = std::max(CGFloat(_maximumValue - _minimumValue), CGFloat(1e-6));
    CGFloat t = std::min(std::max((value - _minimumValue) / range, CGFloat(0)), CGFloat(1));
    if (self.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft) t = 1 - t;
    const CGFloat x = CGRectGetMinX(rect) + std::round(t * (rect.size.width - kKnobW));
    return CGRectMake(x, CGRectGetMidY(bounds) - kKnobH / 2, kKnobW, kKnobH);
}

#pragma mark Value images

- (UIImageView *)valueImageView:(UIImage *)image current:(UIImageView *)view {
    if (!image) {
        [view removeFromSuperview];
        return nil;
    }
    if (!view) {
        view = [UIImageView new];
        view.userInteractionEnabled = NO;
        view.tintColor = UIColor.secondaryLabelColor;
        [self addSubview:view];
    }
    view.image = image;
    return view;
}

- (void)setMinimumValueImage:(UIImage *)image {
    _minimumValueImage = image;
    _minImageView = [self valueImageView:image current:_minImageView];
    [self setNeedsLayout];
}

- (void)setMaximumValueImage:(UIImage *)image {
    _maximumValueImage = image;
    _maxImageView = [self valueImageView:image current:_maxImageView];
    [self setNeedsLayout];
}

- (void)setThumbTintColor:(UIColor *)thumbTintColor {
    _thumbTintColor = thumbTintColor;
    [self updateColors];
}

#pragma mark - Accessibility

- (UIAccessibilityTraits)accessibilityTraits {
    return [super accessibilityTraits] | UIAccessibilityTraitAdjustable |
           (self.enabled ? 0 : UIAccessibilityTraitNotEnabled);
}

- (NSString *)accessibilityValue {
    return [NSString stringWithFormat:@"%d%%", int(std::lround([self normalizedValue] * 100))];
}

- (void)accessibilityStep:(float)sign {
    const float old = _value;
    [self setValue:_value + sign * kAccessibilityStep * (_maximumValue - _minimumValue) animated:NO];
    if (_value != old) [self sendValueChanged];
}

- (void)accessibilityIncrement { [self accessibilityStep:1]; }
- (void)accessibilityDecrement { [self accessibilityStep:-1]; }

// The XCUIElementType UI tests see; an informal method of the accessibility runtime.
- (NSUInteger)_accessibilityAutomationType { return 33; }

// The ends of the track in screen coordinates, which XCUIElement adjustments use.
- (CGPoint)_accessibilityMinScrubberPosition {
    const CGRect t = [self trackRectForBounds:self.bounds];
    return UIAccessibilityConvertFrameToScreenCoordinates(CGRectMake(CGRectGetMinX(t), CGRectGetMidY(t), 1, 1), self).origin;
}

- (CGPoint)_accessibilityMaxScrubberPosition {
    const CGRect t = [self trackRectForBounds:self.bounds];
    return UIAccessibilityConvertFrameToScreenCoordinates(CGRectMake(CGRectGetMaxX(t), CGRectGetMidY(t), 1, 1), self).origin;
}

- (double)_accessibilityMinValue { return _minimumValue; }
- (double)_accessibilityMaxValue { return _maximumValue; }
- (double)_accessibilityNumberValue { return _value; }
- (NSNumber *)_accessibilityAbsoluteValue { return @(float((_value - _minimumValue) / (_maximumValue - _minimumValue))); }

- (void)didMoveToSuperview {
    [super didMoveToSuperview];
    _knob.backdropSourceView = self.superview ?: self;
}

- (void)tintColorDidChange {
    [super tintColorDidChange];
    [self updateColors];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    [self updateColors];
}

- (void)setMinimumTrackTintColor:(UIColor *)color {
    _minimumTrackTintColor = color;
    [self updateColors];
}

- (void)setMaximumTrackTintColor:(UIColor *)color {
    _maximumTrackTintColor = color;
    [self updateColors];
}

- (void)updateColors {
    _knob.restingColor = _thumbTintColor ?: UIColor.whiteColor;
    UIColor *fill = _minimumTrackTintColor ?: self.tintColor;
    _minTrack.backgroundColor = fill;
    _maxTrack.backgroundColor = _maximumTrackTintColor ?: [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *t) {
        return t.userInterfaceStyle == UIUserInterfaceStyleDark ? [UIColor colorWithWhite:1 alpha:0.1]
                                                                 : [UIColor colorWithWhite:0 alpha:0.1];
    }];
    _knob.lensTintColor = fill;
    [_knob setNeedsBackdropUpdate];
}

#pragma mark Value

- (void)setValue:(float)value { [self setValue:value animated:NO]; }

- (void)setValue:(float)value animated:(BOOL)animated {
    [_settleLink invalidate];
    _settleLink = nil;
    _value = std::min(std::max(value, _minimumValue), _maximumValue);
    if (animated) {
        GLSAnimateWithSpring(1.0, 0.3, ^{ [self layoutKnobAndFill]; }, nil);
    } else {
        [self setNeedsLayout];
    }
}

// A minimum above the maximum raises the maximum, as UISlider does.
- (void)setMinimumValue:(float)minimumValue {
    _minimumValue = minimumValue;
    if (_maximumValue < minimumValue) _maximumValue = minimumValue;
    [self setValue:_value];
}

- (void)setMaximumValue:(float)maximumValue {
    _maximumValue = maximumValue;
    if (_minimumValue > maximumValue) _minimumValue = maximumValue;
    [self setValue:_value];
}

- (CGFloat)normalizedValue {
    const CGFloat range = std::max(CGFloat(_maximumValue - _minimumValue), CGFloat(1e-6));
    return (_value - _minimumValue) / range;
}

- (void)setNormalizedValue:(CGFloat)t {
    _value = _minimumValue + float(std::min(std::max(t, CGFloat(0)), CGFloat(1))) * (_maximumValue - _minimumValue);
}

// Unrounded, so the thumb follows the finger during drags; thumbRectForBounds: rounds.
- (CGFloat)knobCenterForValue:(float)value {
    const CGRect track = [self trackRectForBounds:self.bounds];
    const CGFloat range = std::max(CGFloat(_maximumValue - _minimumValue), CGFloat(1e-6));
    CGFloat t = std::min(std::max((value - _minimumValue) / range, CGFloat(0)), CGFloat(1));
    if (self.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft) t = 1 - t;
    return CGRectGetMinX(track) + kKnobW / 2 + t * (track.size.width - kKnobW);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [UIView performWithoutAnimation:^{ [self layoutKnobAndFill]; }];
}

- (void)layoutKnobAndFill {
    const CGFloat s = _tracking && !UIAccessibilityIsReduceMotionEnabled() ? kPressedScale : 1;
    _knob.bounds = CGRectMake(0, 0, kKnobW * s, kKnobH * s);
    [self layoutKnobPosition];
}

// The touch-up spring animates only the thumb's centre and the fill.
- (void)layoutKnobPosition {
    const CGSize size = self.bounds.size;
    const CGRect track = [self trackRectForBounds:self.bounds];
    _maxTrack.frame = track;
    _minImageView.frame = [self minimumValueImageRectForBounds:self.bounds];
    _maxImageView.frame = [self maximumValueImageRectForBounds:self.bounds];
    const CGFloat x = [self knobCenterForValue:_value];
    const CGFloat fx = x - CGRectGetMinX(track);
    const BOOL rtl = self.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
    _minTrack.frame = rtl ? CGRectMake(fx, 0, track.size.width - fx, kTrackH) : CGRectMake(0, 0, fx, kTrackH);
    _knob.center = CGPointMake(x, size.height / 2);
    [_knob setNeedsBackdropUpdate];
}

#pragma mark Touches

- (BOOL)beginTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    [_settleLink invalidate];
    _settleLink = nil;
    const CGPoint p = [touch locationInView:self];
    const CGFloat x = [self knobCenterForValue:_value];
    if (std::fabs(p.x - x) > kKnobW * kPressedScale / 2 + 8) return NO;
    _tracking = YES;
    _dragging = NO;
    _touchStartX = p.x;
    const CGSize pressed = CGSizeMake(kKnobW * kPressedScale, kKnobH * kPressedScale);
    [_knob setLifted:!UIAccessibilityIsReduceMotionEnabled() animated:YES alongsideAnimations:^{
        self->_knob.bounds = CGRectMake(0, 0, pressed.width, pressed.height);
        [self->_knob layoutIfNeeded];
    }];
    return YES;
}

- (BOOL)continueTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    const CGFloat touchX = [touch locationInView:self].x;
    const NSTimeInterval time = touch.timestamp;
    if (!_dragging) {
        if (std::fabs(touchX - _touchStartX) < kPanHysteresis) return YES;
        _dragging = YES;
        _panOriginX = _touchStartX + std::copysign(kPanHysteresis, touchX - _touchStartX);
        _lastTranslation = 0;
        _dragT = [self normalizedValue];
        _velSamples = 0;
        _velPrev = _velLast = 0;
        _lastMoveX = touchX;
        _lastMoveTime = time;
        return YES;
    } else if (touchX == _lastMoveX) {
        return YES;
    } else if (time > _lastMoveTime) {
        _velPrev = _velLast;
        _velLast = (touchX - _lastMoveX) / (time - _lastMoveTime);
        _velSamples = std::min(_velSamples + 1, 2);
    }
    _lastMoveX = touchX;
    _lastMoveTime = time;
    const CGFloat dir = self.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft ? -1 : 1;
    const CGFloat translation = touchX - _panOriginX;
    _dragT += dir * (translation - _lastTranslation) / [self trackLength];
    _lastTranslation = translation;
    const float old = _value;
    [self setNormalizedValue:_dragT];
    if (_value != old) {
        [UIView performWithoutAnimation:^{ [self layoutKnobPosition]; }];
        if (_continuous) [self sendValueChanged];
    }
    return YES;
}

// UIKit's pan driver divides by the full track length, not the thumb's travel.
- (CGFloat)trackLength { return std::max([self trackRectForBounds:self.bounds].size.width, CGFloat(1)); }

- (void)endTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    if (_dragging) {
        const CGFloat dir = self.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft ? -1 : 1;
        const CGFloat velocity = _velSamples >= 2 ? 0.2 * _velLast + 0.8 * _velPrev : _velLast;
        CGFloat target = _dragT + dir * velocity / [self trackLength] * kProjectionTime;
        if (std::fabs(target - _dragT) < kProjectionThreshold / [self trackLength]) target = _dragT;
        target = std::min(std::max(target, CGFloat(0)), CGFloat(1));
        if (std::fabs(target - [self normalizedValue]) > 1e-6)
            [self settleToNormalizedValue:target velocity:dir * velocity / [self trackLength]];
    }
    [self finishTracking];
    [self sendValueChanged];
}

// UIKit 26 sends ValueChanged and PrimaryActionTriggered together.
- (void)sendValueChanged {
    [self sendActionsForControlEvents:UIControlEventValueChanged | UIControlEventPrimaryActionTriggered];
}

// The release spring moves the value itself, so UIKit reports a ValueChanged on every frame.
- (void)settleToNormalizedValue:(CGFloat)target velocity:(CGFloat)velocity {
    [_settleLink invalidate];
    _settleTarget = target;
    _settleT = [self normalizedValue];
    _settleV = velocity;
    _settleLast = CACurrentMediaTime();
    _settleLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(settleTick)];
    [_settleLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
}

- (void)settleTick {
    const CFTimeInterval now = CACurrentMediaTime();
    const double dt = std::min(now - _settleLast, 1.0 / 30), w = 2 * M_PI / 0.4;
    _settleLast = now;
    const double x0 = _settleT - _settleTarget, v0 = _settleV, e = std::exp(-w * dt);
    _settleT = _settleTarget + (x0 + (v0 + w * x0) * dt) * e;
    _settleV = (v0 - (v0 + w * x0) * w * dt) * e;
    const CGFloat length = [self trackLength];
    const BOOL done = std::fabs(_settleT - _settleTarget) * length < 0.1 && std::fabs(_settleV) * length < 2;
    if (done) _settleT = _settleTarget;
    const float old = _value;
    [self setNormalizedValue:_settleT];
    [UIView performWithoutAnimation:^{ [self layoutKnobPosition]; }];
    if (_value != old && _continuous) [self sendValueChanged];
    if (done) {
        [_settleLink invalidate];
        _settleLink = nil;
    }
}

- (void)cancelTrackingWithEvent:(UIEvent *)event {
    [self finishTracking];
}

- (void)dealloc { [_settleLink invalidate]; }

- (void)willMoveToWindow:(UIWindow *)window {
    [super willMoveToWindow:window];
    if (!window) {
        [_settleLink invalidate];
        _settleLink = nil;
    }
}

- (void)finishTracking {
    _tracking = NO;
    _dragging = NO;
    [_knob setLifted:NO animated:YES alongsideAnimations:^{
        self->_knob.bounds = CGRectMake(0, 0, kKnobW, kKnobH);
        [self->_knob layoutIfNeeded];
    }];
}

@end
