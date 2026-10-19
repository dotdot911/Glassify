//
//  GLSSegmentedControl.h
//  Glassify
//
//  Copyright © 2026 Hung Phan.
//  See LICENSE file for license information.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// A drop-in replacement for `UISegmentedControl` with the iOS 26 look, whose selection lifts into clear glass that can be dragged between segments.
@interface GLSSegmentedControl : UIControl

/// Creates a segmented control with segments for the specified titles or images.
- (instancetype)initWithItems:(nullable NSArray *)items;

/// The titles or images of all segments, each an `NSString` or a `UIImage`.
@property (nonatomic, copy) NSArray *items;
/// The number of segments in the control.
@property (nonatomic, readonly) NSUInteger numberOfSegments;

/// The index of the selected segment, or `UISegmentedControlNoSegment` when none is selected.
/// The default is `UISegmentedControlNoSegment`; an index past the last segment is ignored.
@property (nonatomic) NSInteger selectedSegmentIndex;
/// Selects a segment, optionally animating the selection.
- (void)setSelectedSegmentIndex:(NSInteger)index animated:(BOOL)animated;

/// A Boolean value that determines whether segments show their selection only while touched.
@property (nonatomic, getter=isMomentary) BOOL momentary;
/// A Boolean value that determines whether segment widths follow the width of their content.
@property (nonatomic) BOOL apportionsSegmentWidthsByContent;
/// The colour of the selection at rest.
/// The default is `nil`, which draws white.
@property (nonatomic, strong, nullable) UIColor *selectedSegmentTintColor;

/// Inserts a segment with a title at an index.
- (void)insertSegmentWithTitle:(nullable NSString *)title atIndex:(NSUInteger)segment animated:(BOOL)animated;
/// Inserts a segment with an image at an index.
- (void)insertSegmentWithImage:(nullable UIImage *)image atIndex:(NSUInteger)segment animated:(BOOL)animated;
/// Removes the segment at an index.
- (void)removeSegmentAtIndex:(NSUInteger)segment animated:(BOOL)animated;
/// Removes all segments.
- (void)removeAllSegments;

/// Sets the title of a segment.
- (void)setTitle:(nullable NSString *)title forSegmentAtIndex:(NSUInteger)segment;
/// Returns the title of a segment.
- (nullable NSString *)titleForSegmentAtIndex:(NSUInteger)segment;
/// Sets the image of a segment.
- (void)setImage:(nullable UIImage *)image forSegmentAtIndex:(NSUInteger)segment;
/// Returns the image of a segment.
- (nullable UIImage *)imageForSegmentAtIndex:(NSUInteger)segment;
/// Enables or disables a segment.
- (void)setEnabled:(BOOL)enabled forSegmentAtIndex:(NSUInteger)segment;
/// Returns a Boolean value that indicates whether a segment is enabled.
- (BOOL)isEnabledForSegmentAtIndex:(NSUInteger)segment;
/// Sets the width of a segment, where 0 sizes it automatically.
- (void)setWidth:(CGFloat)width forSegmentAtIndex:(NSUInteger)segment;
/// Returns the width of a segment, or 0 when it is sized automatically.
- (CGFloat)widthForSegmentAtIndex:(NSUInteger)segment;
/// Sets the offset of a segment's content from its centre.
- (void)setContentOffset:(CGSize)offset forSegmentAtIndex:(NSUInteger)segment;
/// Returns the offset of a segment's content from its centre.
- (CGSize)contentOffsetForSegmentAtIndex:(NSUInteger)segment;

/// Sets the font and foreground colour attributes of the titles for the normal, selected or disabled state.
- (void)setTitleTextAttributes:(nullable NSDictionary<NSAttributedStringKey, id> *)attributes forState:(UIControlState)state;
/// Returns the title text attributes for a state.
- (nullable NSDictionary<NSAttributedStringKey, id> *)titleTextAttributesForState:(UIControlState)state;

/// The view whose rendering the lifted glass refracts.
/// The default is the superview.
@property (nonatomic, weak, nullable) UIView *backdropSourceView;

@end

NS_ASSUME_NONNULL_END
