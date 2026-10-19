//
//  GLSTabBarController.h
//  Glassify
//
//  Copyright © 2026 Hung Phan.
//  See LICENSE file for license information.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// A tab bar controller that shows the iOS 26 floating glass tab bar, with a liquid lens that marks the selected tab.
/// Each child's `tabBarItem` title and image fill the bar; the rest of the `UITabBarController` API works as usual.
@interface GLSTabBarController : UITabBarController
@end

NS_ASSUME_NONNULL_END
