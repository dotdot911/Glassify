//
//  GLSGlassContainerView.h
//  Glassify
//
//  Copyright © 2026 Hung Phan.
//  See LICENSE file for license information.
//

#import <UIKit/UIKit.h>
#import <Glassify/GLSGlassView.h>

@class GLSScrollEdgeEffectView;

NS_ASSUME_NONNULL_BEGIN

/// A view that merges the glass views placed directly inside it into one liquid shape, the counterpart of `UIGlassContainerEffect`.
@interface GLSGlassContainerView : UIView

/// The distance, in points, within which the shapes of the glass views blend together; the counterpart of `UIGlassContainerEffect.spacing`.
/// The default is 0, which merges shapes only when they touch.
@property (nonatomic) CGFloat spacing;

/// The view whose rendering appears through the glass.
/// The default is the superview.
@property (nonatomic, weak, nullable) UIView *backdropSourceView;
/// A Boolean value that determines whether the glass re-renders every frame to follow a backdrop source moving under it.
@property (nonatomic) BOOL tracksBackdropMotion;
/// How strongly the merged glass frosts the content behind it.
/// The default is `GLSGlassFrostAutomatic`.
@property (nonatomic) GLSGlassFrost frost;
/// The scroll edge effect under the group, from which the glass takes its light or dark appearance.
@property (nonatomic, weak, nullable) GLSScrollEdgeEffectView *scrollEdgeEffect;
/// Snapshots the backdrop source view again after its content changes.
- (void)setNeedsBackdropUpdate;

@end

NS_ASSUME_NONNULL_END
