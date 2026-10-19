//
//  GLSScrollEdgeEffectView.h
//  Glassify
//
//  Copyright © 2026 Hung Phan.
//  See LICENSE file for license information.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Constants that indicate which edge of the scrolling content a scroll edge effect covers.
typedef NS_ENUM(NSInteger, GLSScrollEdge) {
    /// The top edge, under a navigation bar.
    GLSScrollEdgeTop = 0,
    /// The bottom edge, under a toolbar or tab bar.
    GLSScrollEdgeBottom = 1,
};

/// UIKit's soft scroll edge effect, which fades the scrolling content out under a bar.
/// Place it over the content, below the bar, inside the bar's `backdropSourceView`.
@interface GLSScrollEdgeEffectView : UIView

/// The edge the effect covers.
@property (nonatomic) GLSScrollEdge edge;

/// The position of the bar's edge in the superview's coordinates, from which the view sizes itself.
@property (nonatomic) CGFloat barEdge;

/// The height of the bar, used by the bottom edge only.
/// The default is 48, the height of the toolbar.
@property (nonatomic) CGFloat barHeight;
/// The band, in the superview's coordinates, that glass over the effect measures its brightness in.
@property (nonatomic, readonly) CGRect lumaRect;

@end

NS_ASSUME_NONNULL_END
