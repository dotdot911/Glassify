//
//  GLSGlassView+Testing.h
//  Glassify
//
//  Copyright © 2026 Hung Phan.
//  See LICENSE file for license information.
//

#import <Glassify/GLSGlassView.h>

NS_ASSUME_NONNULL_BEGIN

/// Methods that drive the press response of a glass view without touches, for tests, demos and screenshots.
@interface GLSGlassView (Testing)
/// Begins a press at a point in the view's bounds.
- (void)gls_beginPressAtPoint:(CGPoint)point;
/// Moves the current press to a point in the view's bounds.
- (void)gls_movePressToPoint:(CGPoint)point;
/// Ends the current press.
- (void)gls_endPress;
@end

NS_ASSUME_NONNULL_END
