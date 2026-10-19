//
//  GLSLiquidLensView.h
//  Glassify
//
//  Copyright © 2026 Hung Phan.
//  See LICENSE file for license information.
//

#import <UIKit/UIKit.h>

@class GLSGlassView;

NS_ASSUME_NONNULL_BEGIN

/// Animates changes to views with a spring defined by a damping ratio and a response in seconds.
UIKIT_EXTERN void GLSAnimateWithSpring(CGFloat dampingRatio, CGFloat response, void (^animations)(void),
                                       void (^_Nullable completion)(BOOL finished));

/// Constants that indicate the size and role of a liquid lens.
typedef NS_ENUM(NSInteger, GLSLiquidLensStyle) {
    /// The lens of the tab bar selection and the segmented control, the default.
    GLSLiquidLensStyleLarge = 0,
    /// The lens of the switch knob and the slider thumb.
    GLSLiquidLensStyleSmall = 1,
};

/// The liquid glass drop that the iOS 26 tab bar selection, sliders and switches lift into.
@interface GLSLiquidLensView : UIView

/// The size and role of the lens.
@property (nonatomic) GLSLiquidLensStyle style;
/// The colour of a small lens at rest, which fades out while it is lifted.
@property (nonatomic, strong, nullable) UIColor *restingColor;
/// A Boolean value that determines whether a small lens casts a drop shadow at rest.
@property (nonatomic) BOOL restingShadow;
/// The glass tint of a small lens.
/// The default is `nil`, which uses the material of the switch knob.
@property (nonatomic, strong, nullable) UIColor *lensTintColor;
/// A Boolean value that determines whether a small lens warps the content below it while it forms.
@property (nonatomic) BOOL warpsContentBelow;

/// The view whose rendering appears through the lens.
/// The default is the superview.
@property (nonatomic, weak, nullable) UIView *backdropSourceView;
/// The opaque colour drawn behind the backdrop source where it is transparent.
@property (nonatomic, strong, nullable) UIColor *backdropBaseColor;
/// The glass view the lens sits on, whose rendering is composited under the backdrop source.
@property (nonatomic, weak, nullable) GLSGlassView *underlayGlassView;
/// Snapshots the backdrop source view again after its content changes.
- (void)setNeedsBackdropUpdate;

/// The view drawn in place inside the lifted lens, usually tinted copies of the items under it.
/// Call `setNeedsContentUpdate` after it changes.
@property (nonatomic, strong, nullable) UIView *liftedContentView;
/// The frame of the lifted content view, in the coordinates of the lens's superview.
@property (nonatomic) CGRect liftedContentFrame;
/// Redraws the lifted content view after it changes.
- (void)setNeedsContentUpdate;

/// A Boolean value that indicates whether the lens is lifted.
@property (nonatomic, readonly, getter=isLifted) BOOL lifted;
/// Lifts or rests the lens, running the given animations inside the same spring.
- (void)setLifted:(BOOL)lifted animated:(BOOL)animated alongsideAnimations:(nullable void (^)(void))alongside;

/// The on-screen progress of the lift, from 0 at rest to 1 when lifted, which may overshoot slightly.
@property (nonatomic, readonly) CGFloat liftProgress;
/// The opacity of the parts of the lens that fade in as it lifts.
@property (nonatomic, readonly) CGFloat liftAlpha;

/// The time, in seconds, since the lens was last lifted.
@property (nonatomic, readonly) CFTimeInterval liftedDuration;

@end

NS_ASSUME_NONNULL_END
