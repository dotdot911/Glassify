//
//  GLSGlassButton.mm
//  Glassify
//
//  Copyright © 2026 Hung Phan.
//  See LICENSE file for license information.
//

#import "Glassify/GLSGlassButton.h"

#import "Glassify/GLSGlassView+Testing.h"
#import "Glassify/GLSGlassView.h"

#include <algorithm>
#include <cmath>

namespace {
// A UIButtonConfiguration button size: its text style and vertical and horizontal content insets.
struct Metrics {
    UIFontTextStyle textStyle;
    CGFloat vertical, horizontal;
};

Metrics MetricsFor(GLSGlassButtonSize size) {
    switch (size) {
        case GLSGlassButtonSizeSmall: return {UIFontTextStyleSubheadline, 5, 10};
        case GLSGlassButtonSizeLarge: return {UIFontTextStyleBody, 15, 20};
        default: return {UIFontTextStyleBody, 7, 12};
    }
}
}

@implementation GLSGlassButton {
    GLSGlassView *_glass;
    UILabel *_label;
    UIImageView *_imageView;
    __weak UIView *_backdropSourceView;
    NSMutableDictionary<NSNumber *, NSString *> *_titles;
    NSMutableDictionary<NSNumber *, UIImage *> *_images;
}

+ (instancetype)buttonWithStyle:(GLSGlassButtonStyle)style {
    GLSGlassButton *b = [[self alloc] initWithFrame:CGRectZero];
    b.style = style;
    return b;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    [self commonInit];
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    if (!(self = [super initWithCoder:coder])) return nil;
    [self commonInit];
    _style = GLSGlassButtonStyle([coder decodeIntegerForKey:@"GLSGlassButtonStyle"]);
    if ([coder containsValueForKey:@"GLSGlassButtonSize"]) _size = GLSGlassButtonSize([coder decodeIntegerForKey:@"GLSGlassButtonSize"]);
    NSDictionary *titles = [coder decodeObjectOfClasses:[NSSet setWithObjects:NSDictionary.class, NSNumber.class, NSString.class, nil]
                                                 forKey:@"GLSGlassButtonTitles"];
    NSDictionary *images = [coder decodeObjectOfClasses:[NSSet setWithObjects:NSDictionary.class, NSNumber.class, UIImage.class, nil]
                                                 forKey:@"GLSGlassButtonImages"];
    if (titles) [_titles addEntriesFromDictionary:titles];
    if (images) [_images addEntriesFromDictionary:images];
    [self updateAppearance];
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [super encodeWithCoder:coder];
    [coder encodeInteger:_style forKey:@"GLSGlassButtonStyle"];
    [coder encodeInteger:_size forKey:@"GLSGlassButtonSize"];
    [coder encodeObject:_titles forKey:@"GLSGlassButtonTitles"];
    [coder encodeObject:_images forKey:@"GLSGlassButtonImages"];
}

- (void)commonInit {
    _titles = [NSMutableDictionary dictionary];
    _images = [NSMutableDictionary dictionary];
    _size = GLSGlassButtonSizeMedium;
    _glass = [[GLSGlassView alloc] initWithFrame:self.bounds];
    _glass.userInteractionEnabled = NO;
    _glass.interactive = YES;
    _glass.adaptsColorScheme = NO;
    [self addSubview:_glass];
    _label = [UILabel new];
    _label.textAlignment = NSTextAlignmentCenter;
    [_glass.contentView addSubview:_label];
    _imageView = [UIImageView new];
    _imageView.contentMode = UIViewContentModeCenter;
    [_glass.contentView addSubview:_imageView];
    [self updateAppearance];
}

- (void)setStyle:(GLSGlassButtonStyle)style {
    _style = style;
    [self updateAppearance];
}

- (void)setSize:(GLSGlassButtonSize)size {
    _size = size;
    [self updateAppearance];
}

#pragma mark UIButton-style content

// As in UIButton, a state without its own value shows the normal one.
- (void)setTitle:(NSString *)title forState:(UIControlState)state {
    if (title) _titles[@(state)] = [title copy];
    else [_titles removeObjectForKey:@(state)];
    [self updateAppearance];
}

- (NSString *)titleForState:(UIControlState)state { return _titles[@(state)] ?: _titles[@(UIControlStateNormal)]; }

- (void)setImage:(UIImage *)image forState:(UIControlState)state {
    if (image) _images[@(state)] = image;
    else [_images removeObjectForKey:@(state)];
    [self updateAppearance];
}

- (UIImage *)imageForState:(UIControlState)state { return _images[@(state)] ?: _images[@(UIControlStateNormal)]; }

- (NSString *)currentTitle { return [self titleForState:self.state]; }
- (UIImage *)currentImage { return [self imageForState:self.state]; }

- (NSString *)title { return [self titleForState:UIControlStateNormal]; }
- (void)setTitle:(NSString *)title { [self setTitle:title forState:UIControlStateNormal]; }
- (UIImage *)image { return [self imageForState:UIControlStateNormal]; }
- (void)setImage:(UIImage *)image { [self setImage:image forState:UIControlStateNormal]; }

#pragma mark - Accessibility

- (BOOL)isAccessibilityElement { return YES; }

- (UIAccessibilityTraits)accessibilityTraits {
    return [super accessibilityTraits] | UIAccessibilityTraitButton | (self.enabled ? 0 : UIAccessibilityTraitNotEnabled);
}

- (NSString *)accessibilityLabel {
    return [super accessibilityLabel] ?: self.currentTitle ?: self.currentImage.accessibilityLabel;
}

- (BOOL)tracksBackdropMotion { return _glass.tracksBackdropMotion; }
- (void)setTracksBackdropMotion:(BOOL)tracks { _glass.tracksBackdropMotion = tracks; }

// The glass's default source would be this empty control, so the button passes its own source on.
- (UIView *)backdropSourceView { return _backdropSourceView; }
- (void)setBackdropSourceView:(UIView *)view {
    _backdropSourceView = view;
    _glass.backdropSourceView = view ?: self.superview;
}

- (void)didMoveToSuperview {
    [super didMoveToSuperview];
    _glass.backdropSourceView = _backdropSourceView ?: self.superview;
}

- (void)tintColorDidChange {
    [super tintColorDidChange];
    [self updateAppearance];
}

- (void)setHighlighted:(BOOL)highlighted {
    const BOOL changed = highlighted != self.highlighted;
    [super setHighlighted:highlighted];
    if (changed) [self updateAppearance];
}

- (void)setEnabled:(BOOL)enabled {
    [super setEnabled:enabled];
    [self updateAppearance];
}

- (void)updateAppearance {
    const BOOL clear = _style == GLSGlassButtonStyleClearGlass || _style == GLSGlassButtonStyleProminentClearGlass;
    _glass.style = clear ? GLSGlassStyleClear : GLSGlassStyleRegular;
    UIColor *tint = nil;
    if (_style == GLSGlassButtonStyleProminentGlass) {
        tint = self.tintColor;
        if (!self.enabled) tint = [tint colorWithAlphaComponent:0.5];
    } else if (_style == GLSGlassButtonStyleProminentClearGlass) {
        if (@available(iOS 13.0, *)) tint = UIColor.secondarySystemFillColor;
    }
    _glass.glassTintColor = tint;
    const BOOL prominent = _style == GLSGlassButtonStyleProminentGlass;
    _glass.contentVibrancy = !prominent;
    _glass.contentVibrancyStyle = GLSContentVibrancyStyleControls;
    UIColor *fg = prominent ? [self prominentForegroundOver:tint] : nil;
    if (!fg) {
        BOOL light = YES;
        if (@available(iOS 13.0, *)) light = self.traitCollection.userInterfaceStyle != UIUserInterfaceStyleDark;
        if (@available(iOS 13.0, *)) fg = self.enabled ? UIColor.labelColor : UIColor.tertiaryLabelColor;
        else fg = UIColor.blackColor;
        if (self.enabled && self.highlighted && light) fg = [fg colorWithAlphaComponent:0.75];
    }
    const Metrics m = MetricsFor(_size);
    UIFont *font = [UIFont preferredFontForTextStyle:m.textStyle];
    _label.font = font;
    _label.textColor = fg;
    _label.text = self.currentTitle;
    _label.hidden = self.currentTitle.length == 0;
    if (@available(iOS 13.0, *)) {
        _imageView.preferredSymbolConfiguration =
            [UIImageSymbolConfiguration configurationWithTextStyle:m.textStyle scale:UIImageSymbolScaleLarge];
    }
    _imageView.image = [self.currentImage imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    _imageView.tintColor = fg;
    _imageView.hidden = self.currentImage == nil;
    [self invalidateIntrinsicContentSize];
    [self setNeedsLayout];
}

// Applies the glass's content vibrancy matrix to the tint once instead of per pixel.
- (UIColor *)prominentForegroundOver:(UIColor *)tint {
    CGFloat c[4] = {0, 0, 0, 1};
    UIColor *resolved = tint;
    if (@available(iOS 13.0, *)) resolved = [tint resolvedColorWithTraitCollection:self.traitCollection];
    if (![resolved getRed:&c[0] green:&c[1] blue:&c[2] alpha:&c[3]]) return UIColor.whiteColor;
    const CGFloat y = 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2];
    CGFloat o[3];
    for (int i = 0; i < 3; ++i) o[i] = std::min(std::max(c[i] - 0.95 * y + 0.95, CGFloat(0)), CGFloat(1));
    return [UIColor colorWithRed:o[0] green:o[1] blue:o[2] alpha:1];
}

- (CGSize)contentSize {
    const Metrics m = MetricsFor(_size);
    const CGFloat lineHeight = std::ceil(_label.font.lineHeight * 3) / 3;
    const CGFloat height = lineHeight + 2 * m.vertical;
    if (self.currentTitle.length == 0) return CGSizeMake(height, height);
    CGSize text = [_label sizeThatFits:CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX)];
    CGFloat width = std::ceil(text.width * 3) / 3 + 2 * m.horizontal;
    if (self.currentImage) width += [_imageView sizeThatFits:CGSizeZero].width + 4;
    return CGSizeMake(std::max(width, height), height);
}

- (CGSize)intrinsicContentSize { return [self contentSize]; }
- (CGSize)sizeThatFits:(CGSize)size { return [self contentSize]; }

// Sets the glass's bounds and center, not its frame, which the press transform would distort.
- (void)layoutSubviews {
    [super layoutSubviews];
    _glass.bounds = CGRectMake(0, 0, self.bounds.size.width, self.bounds.size.height);
    _glass.center = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
    const CGRect b = _glass.contentView.bounds;
    if (self.currentTitle.length && self.currentImage) {
        const CGFloat iw = [_imageView sizeThatFits:CGSizeZero].width;
        const CGSize t = [_label sizeThatFits:CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX)];
        const CGFloat x0 = (b.size.width - iw - 4 - t.width) / 2;
        _imageView.frame = CGRectMake(x0, 0, iw, b.size.height);
        _label.frame = CGRectMake(x0 + iw + 4, 0, t.width, b.size.height);
    } else {
        const Metrics m = MetricsFor(_size);
        const CGFloat lineHeight = std::ceil(_label.font.lineHeight * 3) / 3;
        _label.textAlignment = NSTextAlignmentLeft;
        _label.frame = CGRectMake(m.horizontal, (b.size.height - lineHeight) / 2,
                                  std::max(b.size.width - 2 * m.horizontal, CGFloat(0)), lineHeight);
        _imageView.frame = b;
    }
}

#pragma mark Touches

- (BOOL)beginTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    [_glass gls_beginPressAtPoint:[touch locationInView:_glass]];
    return YES;
}

- (BOOL)continueTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    [_glass gls_movePressToPoint:[touch locationInView:_glass]];
    return YES;
}

- (void)endTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    [_glass gls_endPress];
    if (touch && [self pointInside:[touch locationInView:self] withEvent:event])
        [self sendActionsForControlEvents:UIControlEventPrimaryActionTriggered];
}

- (void)cancelTrackingWithEvent:(UIEvent *)event {
    [_glass gls_endPress];
}

@end
