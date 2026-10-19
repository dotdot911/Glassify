//
//  GLSBarButton.mm
//  Glassify
//
//  Copyright © 2026 Hung Phan.
//  See LICENSE file for license information.
//

#import "GLSBarButton.h"

#import "Glassify/GLSGlassView+Testing.h"
#import "Glassify/GLSGlassView.h"

#include <algorithm>
#include <cmath>

NSInteger GLSBarButtonSystemItem(UIBarButtonItem *item) {
    @try {
        if (![[item valueForKey:@"isSystemItem"] boolValue]) return -1;
        return [[item valueForKey:@"systemItem"] integerValue];
    } @catch (NSException *) {
        return -1;
    }
}

BOOL GLSBarButtonIsSpace(UIBarButtonItem *item) {
    const NSInteger s = GLSBarButtonSystemItem(item);
    return s == UIBarButtonSystemItemFlexibleSpace || s == UIBarButtonSystemItemFixedSpace;
}

static NSString *SymbolForSystemItem(NSInteger s) {
    switch (s) {
        case UIBarButtonSystemItemAdd: return @"plus";
        case UIBarButtonSystemItemCompose: return @"square.and.pencil";
        case UIBarButtonSystemItemReply: return @"arrowshape.turn.up.left";
        case UIBarButtonSystemItemAction: return @"square.and.arrow.up";
        case UIBarButtonSystemItemOrganize: return @"folder";
        case UIBarButtonSystemItemBookmarks: return @"book";
        case UIBarButtonSystemItemSearch: return @"magnifyingglass";
        case UIBarButtonSystemItemRefresh: return @"arrow.clockwise";
        case UIBarButtonSystemItemStop: return @"xmark";
        case UIBarButtonSystemItemCamera: return @"camera";
        case UIBarButtonSystemItemTrash: return @"trash";
        case UIBarButtonSystemItemPlay: return @"play.fill";
        case UIBarButtonSystemItemPause: return @"pause.fill";
        case UIBarButtonSystemItemRewind: return @"backward.fill";
        case UIBarButtonSystemItemFastForward: return @"forward.fill";
        case UIBarButtonSystemItemUndo: return @"arrow.uturn.backward";
        case UIBarButtonSystemItemRedo: return @"arrow.uturn.forward";
        default: return nil;
    }
}

static NSString *TitleForSystemItem(NSInteger s) {
    switch (s) {
        case UIBarButtonSystemItemDone: return @"Done";
        case UIBarButtonSystemItemCancel: return @"Cancel";
        case UIBarButtonSystemItemEdit: return @"Edit";
        case UIBarButtonSystemItemSave: return @"Save";
        default: return nil;
    }
}

static constexpr CGFloat kTrackingSlop = 15;

@implementation GLSBarButton {
    UIImageView *_imageView;
    UILabel *_label;
    BOOL _touchInside;
}

- (instancetype)initWithItem:(UIBarButtonItem *)item {
    if (!(self = [super initWithFrame:CGRectZero])) return nil;
    _item = item;
    _highlightedAlpha = 0.2;
    _touchInside = YES;
    const NSInteger system = GLSBarButtonSystemItem(item);
    UIImage *image = item.image;
    NSString *title = item.title;
    if (system >= 0) {
        if (NSString *name = SymbolForSystemItem(system)) image = [UIImage systemImageNamed:name];
        if (NSString *t = TitleForSystemItem(system)) title = t;
    }
    if (image) {
        _imageView = [[UIImageView alloc] initWithImage:[image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
        _imageView.preferredSymbolConfiguration =
            [[UIImageSymbolConfiguration configurationWithTextStyle:UIFontTextStyleBody scale:UIImageSymbolScaleLarge]
                configurationByApplyingConfiguration:[UIImageSymbolConfiguration
                                                         configurationWithWeight:UIImageSymbolWeightMedium]];
        [self addSubview:_imageView];
    } else {
        _label = [UILabel new];
        _label.text = title;
        _label.font = [UIFont fontWithDescriptor:[[UIFontDescriptor preferredFontDescriptorWithTextStyle:UIFontTextStyleBody]
                                                     fontDescriptorByAddingAttributes:@{
                                                         UIFontDescriptorTraitsAttribute : @{UIFontWeightTrait : @(UIFontWeightMedium)}
                                                     }]
                                            size:0];
        _label.textColor = UIColor.labelColor;
        [self addSubview:_label];
    }
    self.accessibilityLabel = title ?: item.accessibilityLabel;
    self.accessibilityTraits = UIAccessibilityTraitButton;
    self.isAccessibilityElement = YES;
    return self;
}

- (instancetype)initBackButton {
    if (!(self = [super initWithFrame:CGRectZero])) return nil;
    _highlightedAlpha = 0.2;
    _touchInside = YES;
    _imageView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.backward"]];
    UIFontDescriptor *emphasized = [[UIFontDescriptor preferredFontDescriptorWithTextStyle:UIFontTextStyleBody]
        fontDescriptorWithSymbolicTraits:UIFontDescriptorTraitBold];
    _imageView.preferredSymbolConfiguration =
        [[UIImageSymbolConfiguration configurationWithFont:[UIFont fontWithDescriptor:emphasized size:0]
                                                     scale:UIImageSymbolScaleLarge]
            configurationByApplyingConfiguration:[UIImageSymbolConfiguration
                                                     configurationWithWeight:UIImageSymbolWeightSemibold]];
    [self addSubview:_imageView];
    self.accessibilityLabel = @"Back";
    self.accessibilityTraits = UIAccessibilityTraitButton;
    self.isAccessibilityElement = YES;
    return self;
}

- (BOOL)isTitle { return _label != nil; }

// Dims the glyph at once on touch down and fades it back on release, like UIKit's bar buttons.
- (void)setHighlighted:(BOOL)highlighted {
    highlighted = highlighted && (!self.tracking || _touchInside);
    if (highlighted == self.highlighted) return;
    [super setHighlighted:highlighted];
    UIView *content = _imageView ?: _label;
    if (highlighted) {
        [content.layer removeAllAnimations];
        content.alpha = _highlightedAlpha;
    } else {
        [UIView animateWithDuration:0.3 delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseOut
                         animations:^{ content.alpha = 1; } completion:nil];
    }
}

- (CGSize)contentSize {
    if (_label) {
        const CGSize s = [_label sizeThatFits:CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX)];
        return CGSizeMake(std::ceil(s.width * 3) / 3, std::ceil(s.height * 3) / 3);
    }
    const CGSize s = [_imageView sizeThatFits:CGSizeZero];
    return s;
}

// Centres the symbol's alignment rect, not its frame, snapping x down and y up to the pixel grid.
- (void)layoutSubviews {
    [super layoutSubviews];
    const CGSize s = [self contentSize];
    if (_label) {
        _label.frame = CGRectMake(_contentCenter.x - s.width / 2, _contentCenter.y - s.height / 2, s.width, s.height);
        return;
    }
    _imageView.frame = CGRectMake(0, 0, s.width, s.height);
    const CGRect a = [_imageView alignmentRectForFrame:_imageView.frame];
    _imageView.frame = CGRectOffset(_imageView.frame, std::floor((_contentCenter.x - CGRectGetMidX(a)) * 3 + 0.01) / 3,
                                    std::ceil((_contentCenter.y - CGRectGetMidY(a)) * 3 - 0.01) / 3);
}

#pragma mark Touches

- (BOOL)isTrackingTouchInside:(UITouch *)touch {
    return CGRectContainsPoint(CGRectInset(self.bounds, -kTrackingSlop, -kTrackingSlop), [touch locationInView:self]);
}

- (BOOL)beginTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    _touchInside = YES;
    if (GLSGlassView *p = _platter) [p gls_beginPressAtPoint:[touch locationInView:p]];
    return YES;
}

- (BOOL)continueTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    if (GLSGlassView *p = _platter) [p gls_movePressToPoint:[touch locationInView:p]];
    _touchInside = [self isTrackingTouchInside:touch];
    self.highlighted = _touchInside;
    return YES;
}

- (void)endTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    [_platter gls_endPress];
    const BOOL inside = touch && [self isTrackingTouchInside:touch];
    _touchInside = YES;
    if (!inside) return;
    if (_handler) _handler();
    if (_item.action) [UIApplication.sharedApplication sendAction:_item.action to:_item.target from:_item forEvent:event];
}

- (void)cancelTrackingWithEvent:(UIEvent *)event {
    _touchInside = YES;
    [_platter gls_endPress];
}

@end
