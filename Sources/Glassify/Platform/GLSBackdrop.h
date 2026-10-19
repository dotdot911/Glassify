//
//  GLSBackdrop.h
//  Glassify
//
//  Copyright © 2026 Hung Phan.
//  See LICENSE file for license information.
//

#pragma once

#import <Metal/Metal.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// A scroll edge effect outside the source, composited over the snapshot on the GPU, in source bounds space.
typedef struct {
    BOOL on;
    CGFloat top, bottom;
    // The mask is the shadow of the rect `y0` … `y1`.
    CGFloat y0, y1, sigma;
    // Straight RGBA.
    float color[4];
} GLSBackdropVeil;

@interface GLSBackdrop : NSObject

@property (class, nonatomic) BOOL logsStats;

// Registered glass views are hidden while a source is snapshotted.
+ (void)registerGlassView:(UIView *)view;
+ (void)unregisterGlassView:(UIView *)view;

- (instancetype)initWithSource:(UIView *)source backdropScale:(CGFloat)backdropScale;

// nil means the nearest opaque background of the source or its superviews, else the window's, else black.
@property (nonatomic, strong, nullable) UIColor *baseColor;
// Another surface's last frame, drawn between the base colour and the source.
@property (nonatomic, strong, nullable) id<MTLTexture> underlayTexture;
@property (nonatomic) CGRect underlayRect;
// A change re-encodes the pyramid from the last snapshot without capturing again.
@property (nonatomic) GLSBackdropVeil veil;

@property (nonatomic, weak, readonly) UIView *source;
@property (nonatomic, readonly, nullable) id<MTLTexture> texture;
@property (nonatomic, readonly) CGFloat pixelsPerPoint;
// Source bounds space in points; texel (0, 0) is at its origin.
@property (nonatomic, readonly) CGRect capturedRect;
// Bumps on every snapshot.
@property (nonatomic, readonly) NSUInteger generation;

// Mean BT.709 luma (sRGB-encoded, 0 … 1) of the snapshot inside `rect`, or −1.
- (float)meanLumaInRect:(CGRect)rect;
// Mean luma of the source rendered without `hidden`, as a scroll edge effect sees the content under it, or −1.
- (float)lumaInRect:(CGRect)rect hiding:(UIView *)hidden;

- (void)invalidate;
@property (nonatomic, readonly, getter=isInvalidated) BOOL invalidated;
// Snapshots again when invalidated or when `neededRect` leaves the captured rect; returns YES if it did.
- (BOOL)updateForRect:(CGRect)neededRect wantedRect:(CGRect)wantedRect;

@end

NS_ASSUME_NONNULL_END
