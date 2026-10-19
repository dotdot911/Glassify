//
//  GLSToolbar.h
//  Glassify
//
//  Copyright © 2026 Hung Phan.
//  See LICENSE file for license information.
//

#import <UIKit/UIKit.h>

@class GLSScrollEdgeEffectView;

NS_ASSUME_NONNULL_BEGIN

/// The iOS 26 toolbar, a floating row of glass platters split by flexible spaces.
/// Lay it out 48 pt high, 28 pt in from the left, right and bottom of the screen.
@interface GLSToolbar : UIView

/// The items in the toolbar, split into platters by flexible spaces.
@property (nonatomic, copy, nullable) NSArray<UIBarButtonItem *> *items;

/// The scrolling content under the toolbar, whose position sets the frost of the platters.
/// The default is `nil`, which uses no frost.
@property (nonatomic, weak, nullable) UIScrollView *scrollView;

/// The scroll edge effect under the toolbar, from which the glass takes its light or dark appearance.
@property (nonatomic, weak, nullable) GLSScrollEdgeEffectView *scrollEdgeEffect;

/// The view whose rendering appears through the platters.
/// The default is the superview; keep the toolbar outside this view.
@property (nonatomic, weak, nullable) UIView *backdropSourceView;

@end

NS_ASSUME_NONNULL_END
