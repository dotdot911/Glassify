//
//  GLSNavigationBar.h
//  Glassify
//
//  Copyright © 2026 Hung Phan.
//  See LICENSE file for license information.
//

#import <UIKit/UIKit.h>

@class GLSScrollEdgeEffectView;

NS_ASSUME_NONNULL_BEGIN

/// The iOS 26 navigation bar, with bar button items on glass platters, a back button and a centred title.
/// Lay it out under the status bar, 54 pt high.
@interface GLSNavigationBar : UIView

/// The title centred in the bar.
@property (nonatomic, copy, nullable) NSString *title;

/// A custom view shown in place of the title, the counterpart of `UINavigationItem.titleView`.
@property (nonatomic, strong, nullable) UIView *titleView;

/// A Boolean value that determines whether the bar shows a glass back button at its leading edge.
/// The default is `NO`.
@property (nonatomic) BOOL showsBackButton;
/// The block the bar calls when the user taps the back button.
@property (nonatomic, copy, nullable) void (^backHandler)(void);

/// The items at the leading edge, after the back button, in `UINavigationItem` order.
@property (nonatomic, copy, nullable) NSArray<UIBarButtonItem *> *leftItems;
/// The items at the trailing edge, in `UINavigationItem` order, so the first item is the rightmost.
@property (nonatomic, copy, nullable) NSArray<UIBarButtonItem *> *rightItems;

/// The scrolling content under the bar, whose position sets the frost of the platters.
/// The default is `nil`, which uses the reduced frost.
@property (nonatomic, weak, nullable) UIScrollView *scrollView;

/// The scroll edge effect under the bar, from which the glass takes its light or dark appearance.
@property (nonatomic, weak, nullable) GLSScrollEdgeEffectView *scrollEdgeEffect;

/// The view whose rendering appears through the platters, usually the scroll view.
/// The default is the superview; keep the bar outside this view.
@property (nonatomic, weak, nullable) UIView *backdropSourceView;

@end

NS_ASSUME_NONNULL_END
