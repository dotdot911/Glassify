//
//  GLSGlassView.h
//  Glassify
//
//  Copyright © 2026 Hung Phan.
//  See LICENSE file for license information.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Constants that indicate the material of a glass view.
typedef NS_ENUM(NSInteger, GLSGlassStyle) {
    /// The standard glass, the counterpart of `UIGlassEffectStyleRegular`.
    GLSGlassStyleRegular = 0,
    /// The more transparent glass, the counterpart of `UIGlassEffectStyleClear`.
    GLSGlassStyleClear = 1,
};

/// Constants that indicate how strongly glass frosts the content behind it.
typedef NS_ENUM(NSInteger, GLSGlassFrost) {
    /// The frost the scroll edge effect under the glass calls for.
    GLSGlassFrostAutomatic = 0,
    /// A lighter frost, as glass shows over content resting at its scroll edge.
    GLSGlassFrostReduced = 1,
    /// No blur, so the content under the glass stays sharp.
    GLSGlassFrostNone = 2,
};

/// Constants that indicate how content on a glass view is coloured.
typedef NS_ENUM(NSInteger, GLSContentVibrancyStyle) {
    /// The vibrancy of `UIGlassEffect`, which draws content black in light mode and white in dark mode.
    GLSContentVibrancyStyleGlass = 0,
    /// The vibrancy of UIKit's bar items and glass buttons, which colours content per pixel from the glass under it.
    GLSContentVibrancyStyleControls = 1,
};

/// A view that renders Liquid Glass, the counterpart of a `UIVisualEffectView` with a `UIGlassEffect`.
@interface GLSGlassView : UIView

/// The material of the glass.
@property (nonatomic) GLSGlassStyle style;
/// How strongly the glass frosts the content behind it.
/// The default is `GLSGlassFrostAutomatic`.
@property (nonatomic) GLSGlassFrost frost;

/// The tint colour of the glass, whose alpha sets the tint strength; the counterpart of `UIGlassEffect.tintColor`.
/// The default is `nil`, which leaves the glass untinted.
@property (nonatomic, copy, nullable) UIColor *glassTintColor;

/// A Boolean value that determines whether the glass lifts and lights up under touches, the counterpart of `UIGlassEffect.isInteractive`.
/// The default is `NO`.
@property (nonatomic, getter=isInteractive) BOOL interactive;

/// A Boolean value that determines whether the glass is drawn, which materializes or dematerializes it when set inside an animation block.
/// The default is `YES`.
@property (nonatomic, getter=isGlassEnabled) BOOL glassEnabled;

/// A Boolean value that determines whether small glass switches between light and dark with the content behind it.
/// The default is `YES`.
@property (nonatomic) BOOL adaptsColorScheme;

/// The continuous corner radius of the glass, in points.
/// The default is a negative value, which draws a capsule.
@property (nonatomic) CGFloat cornerRadius;

/// The view whose rendering appears through the glass.
/// The default is the superview.
@property (nonatomic, weak, nullable) UIView *backdropSourceView;

/// The view to which you add labels and icons drawn on top of the glass.
@property (nonatomic, readonly) UIView *contentView;

/// A Boolean value that determines whether the content view is coloured to stand out on the glass, as UIKit does.
/// The default is `YES`.
@property (nonatomic) BOOL contentVibrancy;
/// How content is coloured when `contentVibrancy` is on.
/// The default is `GLSContentVibrancyStyleGlass`.
@property (nonatomic) GLSContentVibrancyStyle contentVibrancyStyle;

/// Additional views outside the content view whose sublayers the glass draws with the controls vibrancy.
/// Hide these views on screen, for example with an alpha of 0.
@property (nonatomic, copy) NSArray<UIView *> *vibrantContentViews;
/// Redraws the vibrant content views after they or their masks change outside UIKit animations.
- (void)setNeedsVibrantContentUpdate;

/// A Boolean value that determines whether the glass re-renders every frame to follow a backdrop source moving under it.
/// The default is `NO`.
@property (nonatomic) BOOL tracksBackdropMotion;

/// An offset added to the blur level the glass samples, where 0 keeps the standard blur.
@property (nonatomic) CGFloat blurLodBias;

/// Snapshots the backdrop source view again after its content changes.
- (void)setNeedsBackdropUpdate;

@end

NS_ASSUME_NONNULL_END
