//
//  GLSSwitch.h
//  Glassify
//
//  Copyright © 2026 Hung Phan.
//  See LICENSE file for license information.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// A drop-in replacement for `UISwitch` with the iOS 26 look, whose knob turns into a liquid glass drop while touched.
@interface GLSSwitch : UIControl

/// A Boolean value that determines the on or off state of the switch.
@property (nonatomic, getter=isOn) BOOL on;
/// Sets the state of the switch, optionally animating the transition.
- (void)setOn:(BOOL)on animated:(BOOL)animated;

/// The colour of the track when the switch is on.
/// The default is `nil`, which draws `systemGreenColor`.
@property (nonatomic, strong, nullable) UIColor *onTintColor;
/// The colour of the knob at rest.
/// The default is `nil`, which draws white.
@property (nonatomic, strong, nullable) UIColor *thumbTintColor;

@end

NS_ASSUME_NONNULL_END
