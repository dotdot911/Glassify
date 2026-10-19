//
//  GLSNavigationController.h
//  Glassify
//
//  Copyright © 2026 Hung Phan.
//  See LICENSE file for license information.
//

#import <UIKit/UIKit.h>

@class GLSNavigationBar, GLSToolbar;

NS_ASSUME_NONNULL_BEGIN

/// A navigation controller that shows the iOS 26 glass navigation bar and toolbar while app code keeps using the standard `UINavigationController` API.
@interface GLSNavigationController : UINavigationController

/// The glass navigation bar the controller shows in place of the system navigation bar.
@property (nonatomic, readonly) GLSNavigationBar *glassNavigationBar;
/// The glass toolbar the controller shows in place of the system toolbar.
@property (nonatomic, readonly) GLSToolbar *glassToolbar;

@end

NS_ASSUME_NONNULL_END
