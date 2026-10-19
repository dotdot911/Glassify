//
//  GLSGlassButton.h
//  Glassify
//
//  Copyright © 2026 Hung Phan.
//  See LICENSE file for license information.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Constants that indicate the look of a glass button, matching UIKit's glass button configurations.
typedef NS_ENUM(NSInteger, GLSGlassButtonStyle) {
    /// Regular glass with label-coloured content, the counterpart of `UIButton.Configuration.glass()`.
    GLSGlassButtonStyleGlass = 0,
    /// Regular glass tinted with the tint colour and white content, the counterpart of `UIButton.Configuration.prominentGlass()`.
    GLSGlassButtonStyleProminentGlass = 1,
    /// Clear glass with label-coloured content, the counterpart of `UIButton.Configuration.clearGlass()`.
    GLSGlassButtonStyleClearGlass = 2,
    /// Clear glass tinted with the secondary system fill, the counterpart of `UIButton.Configuration.prominentClearGlass()`.
    GLSGlassButtonStyleProminentClearGlass = 3,
};

/// Constants that indicate the size of a glass button.
typedef NS_ENUM(NSInteger, GLSGlassButtonSize) {
    /// A small button with 15 pt text.
    GLSGlassButtonSizeSmall = 0,
    /// A medium button with 17 pt text, the default size.
    GLSGlassButtonSizeMedium = 1,
    /// A large button with 17 pt text and generous insets.
    GLSGlassButtonSizeLarge = 2,
};

/// A button on a glass capsule, the counterpart of a `UIButton` with a glass configuration.
@interface GLSGlassButton : UIControl

/// Creates a button with the specified style.
+ (instancetype)buttonWithStyle:(GLSGlassButtonStyle)style;

/// The look of the button.
@property (nonatomic) GLSGlassButtonStyle style;
/// The size of the button.
/// The default is `GLSGlassButtonSizeMedium`.
@property (nonatomic) GLSGlassButtonSize size;
/// The title for the normal state.
@property (nonatomic, copy, nullable) NSString *title;
/// The image for the normal state; a button with only an image is a circle.
@property (nonatomic, strong, nullable) UIImage *image;

/// Sets the title to use for the specified state.
- (void)setTitle:(nullable NSString *)title forState:(UIControlState)state;
/// Returns the title for the specified state, falling back to the normal state's title.
- (nullable NSString *)titleForState:(UIControlState)state;
/// Sets the image to use for the specified state.
- (void)setImage:(nullable UIImage *)image forState:(UIControlState)state;
/// Returns the image for the specified state, falling back to the normal state's image.
- (nullable UIImage *)imageForState:(UIControlState)state;
/// The title the button currently shows.
@property (nonatomic, readonly, nullable) NSString *currentTitle;
/// The image the button currently shows.
@property (nonatomic, readonly, nullable) UIImage *currentImage;

/// The view whose rendering appears through the glass.
/// The default is the nearest ancestor with an opaque background, or the window.
@property (nonatomic, weak, nullable) UIView *backdropSourceView;
/// A Boolean value that determines whether the glass re-renders every frame to follow a backdrop source moving under it.
/// The default is `NO`.
@property (nonatomic) BOOL tracksBackdropMotion;

@end

NS_ASSUME_NONNULL_END
