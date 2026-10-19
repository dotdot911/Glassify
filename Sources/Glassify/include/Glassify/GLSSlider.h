//
//  GLSSlider.h
//  Glassify
//
//  Copyright © 2026 Hung Phan.
//  See LICENSE file for license information.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// A drop-in replacement for `UISlider` with the iOS 26 look, whose thumb grows into a tinted liquid glass drop while dragged.
@interface GLSSlider : UIControl

/// The current value of the slider.
/// The default is 0.
@property (nonatomic) float value;
/// The value at the leading end of the track.
/// The default is 0.
@property (nonatomic) float minimumValue;
/// The value at the trailing end of the track.
/// The default is 1.
@property (nonatomic) float maximumValue;
/// Sets the value of the slider, optionally animating the transition.
- (void)setValue:(float)value animated:(BOOL)animated;
/// A Boolean value that determines whether value-changed events are sent while dragging or only when the drag ends.
/// The default is `YES`.
@property (nonatomic, getter=isContinuous) BOOL continuous;

/// The colour of the track up to the thumb.
/// The default is `nil`, which draws the tint colour.
@property (nonatomic, strong, nullable) UIColor *minimumTrackTintColor;
/// The colour of the track beyond the thumb.
/// The default is `nil`, which draws a faint black in light mode and a faint white in dark mode.
@property (nonatomic, strong, nullable) UIColor *maximumTrackTintColor;
/// The colour of the thumb at rest.
/// The default is `nil`, which draws white.
@property (nonatomic, strong, nullable) UIColor *thumbTintColor;

/// The image at the minimum end of the track.
/// The default is `nil`.
@property (nonatomic, strong, nullable) UIImage *minimumValueImage;
/// The image at the maximum end of the track.
/// The default is `nil`.
@property (nonatomic, strong, nullable) UIImage *maximumValueImage;

/// Returns the rectangle for the minimum value image; override it to customise the layout.
- (CGRect)minimumValueImageRectForBounds:(CGRect)bounds;
/// Returns the rectangle for the maximum value image; override it to customise the layout.
- (CGRect)maximumValueImageRectForBounds:(CGRect)bounds;
/// Returns the rectangle for the track; override it to customise the layout.
- (CGRect)trackRectForBounds:(CGRect)bounds;
/// Returns the rectangle for the thumb at a value; override it to customise the layout.
- (CGRect)thumbRectForBounds:(CGRect)bounds trackRect:(CGRect)rect value:(float)value;

@end

NS_ASSUME_NONNULL_END
