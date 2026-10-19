//
//  GLSContentMask.h
//  Glassify
//
//  Copyright © 2026 Hung Phan.
//  See LICENSE file for license information.
//

#import <Metal/Metal.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// The name of the empty mask layer that hides a glass's content views on screen.
static NSString *const GLSContentMaskHiddenName = @"GLSContentHidden";

@interface GLSContentMask : NSObject

// Rendered again only when a layer's geometry, opacity or contents, or a mask's path, change; nil when nothing is drawn.
- (nullable id<MTLTexture>)maskForViews:(NSArray<UIView *> *)views
                              hostLayer:(CALayer *)hostLayer
                                   rect:(CGRect)rect
                                  scale:(CGFloat)scale
                                 device:(id<MTLDevice>)device;

@end

NS_ASSUME_NONNULL_END
