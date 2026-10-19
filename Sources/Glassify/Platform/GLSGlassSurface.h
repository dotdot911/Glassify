//
//  GLSGlassSurface.h
//  Glassify
//
//  Copyright © 2026 Hung Phan.
//  See LICENSE file for license information.
//

#pragma once

#import <Metal/Metal.h>
#import <UIKit/UIKit.h>

#include <vector>

#include "glassify/glass_inputs.h"
#include "glassify/pack.h"

NS_ASSUME_NONNULL_BEGIN

@protocol GLSFrameClient <NSObject>
- (void)driverTick;
- (BOOL)wantsContinuousFrames;
@end

// Drives redraws for glass that follows presentation layers, and pauses when nobody needs it.
@interface GLSFrameDriver : NSObject
+ (instancetype)shared;
- (void)addClient:(id<GLSFrameClient>)client until:(CFTimeInterval)deadline;
- (void)removeClient:(id<GLSFrameClient>)client;
@end

struct GLSSurfaceRequest {
    // Host-view bounds space, in points.
    std::vector<glassify::ShapeElement> elements;
    glassify::GlassStyle style = glassify::GlassStyle::Regular;
    CGSize lawSize = CGSizeZero;
    // When nonzero, the inputs interpolate the size laws from this size to `lawSize` by `lawProgress`.
    CGSize lawFromSize = CGSizeZero;
    float lawProgress = 1.f;
    // 0 is identity (invisible) glass, 1 is full glass.
    float materialize = 1.f;
    // The merge radius, from the container's spacing.
    float smoothness = 0.f;
    glassify::Frost frost = glassify::Frost::Automatic;
    // NO for UIButton's glass: the face still follows the luma, but the scheme stays the trait collection's.
    bool adaptsColorScheme = true;
    // User tuning on top of the calibrated bias.
    float lodBias = 0.f;
    UIColor *_Nullable tint = nil;
    // Host-view bounds space.
    glassify::GlowState glow;
    // Liquid lens only: fixed inputs instead of the size laws.
    const glassify::GlassInputs *inputs = nullptr;
    float opacity = 1.f;
    id<MTLTexture> _Nullable content = nil;
    CGRect contentRect = CGRectZero;
    // The scroll edge effect whose underlying content gives the luma.
    UIView *_Nullable __weak lumaEdge = nil;
    // Views whose sublayers become the glass's content mask instead of being shown as they are.
    NSArray<UIView *> *_Nullable vibrantViews = nil;
};

// A negative `backdropLuma` means unknown.
glassify::GlassInputs GLSResolveInputs(const GLSSurfaceRequest &request, UITraitCollection *traits,
                                       glassify::Appearance appearance, float backdropLuma);
glassify::Appearance GLSTraitAppearance(UITraitCollection *traits);

@interface GLSGlassSurface : NSObject

- (instancetype)initWithHost:(UIView *)host;

@property (nonatomic) BOOL hidden;
@property (nonatomic, weak, nullable) UIView *source;
// 0.25 for regular glass, 0.5 for clear.
@property (nonatomic) CGFloat backdropScale;
@property (nonatomic, strong, nullable) UIColor *backdropBaseColor;
@property (nonatomic, copy, nullable) void (^sourceDidMove)(void);
// Called when the surface animates on its own; the host ticks until `isStale` turns NO.
@property (nonatomic, copy, nullable) void (^needsFrames)(void);
// Called on the main thread when the effective scheme changes, including small glass's luma-adaptive one.
@property (nonatomic, copy, nullable) void (^appearanceDidChange)(BOOL dark);

- (void)setNeedsBackdropUpdate;

// Keeps every finished frame, so glass drawn above this one can see it as CABackdropLayer would.
@property (nonatomic) BOOL keepsOutput;
@property (nonatomic, readonly, nullable) id<MTLTexture> outputTexture;
@property (nonatomic, readonly) CGRect outputRect;
@property (nonatomic, readonly, nullable) UIView *host;
// Glass under this one, composited under the source snapshot in this surface's backdrop.
@property (nonatomic, weak, nullable) GLSGlassSurface *underlaySurface;
// YES if the host moved relative to the source, or the backdrop changed, since the last render.
- (BOOL)isStale;
- (void)render:(const GLSSurfaceRequest &)request;

@end

NS_ASSUME_NONNULL_END
