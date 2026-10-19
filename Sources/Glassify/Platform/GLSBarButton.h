//
//  GLSBarButton.h
//  Glassify
//
//  Copyright © 2026 Hung Phan.
//  See LICENSE file for license information.
//

#import <UIKit/UIKit.h>

@class GLSGlassView;

NS_ASSUME_NONNULL_BEGIN

// The item's private `systemItem`, or -1 for a custom item.
NSInteger GLSBarButtonSystemItem(UIBarButtonItem *item);
BOOL GLSBarButtonIsSpace(UIBarButtonItem *item);

@interface GLSBarButton : UIControl

- (instancetype)initWithItem:(UIBarButtonItem *)item;
- (instancetype)initBackButton;

// Nil for the back button.
@property (nonatomic, readonly) UIBarButtonItem *item;
@property (nonatomic, copy, nullable) void (^handler)(void);
@property (nonatomic, weak, nullable) GLSGlassView *platter;
// The point the glyph's alignment rect or the text is centred on.
@property (nonatomic) CGPoint contentCenter;
@property (nonatomic) CGFloat highlightedAlpha;
- (CGSize)contentSize;
- (BOOL)isTitle;

@end

NS_ASSUME_NONNULL_END
