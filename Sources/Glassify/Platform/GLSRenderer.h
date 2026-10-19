//
//  GLSRenderer.h
//  Glassify
//
//  Copyright © 2026 Hung Phan.
//  See LICENSE file for license information.
//

#pragma once

#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>

#include "../Shaders/glass_shared.h"

NS_ASSUME_NONNULL_BEGIN

@interface GLSRenderer : NSObject

+ (nullable instancetype)shared;

@property (nonatomic, readonly) id<MTLDevice> device;
@property (nonatomic, readonly) id<MTLCommandQueue> queue;

- (void)encodePyramid:(id<MTLTexture>)pyramid
           fromLinear:(id<MTLTexture>)linear
        commandBuffer:(id<MTLCommandBuffer>)commandBuffer;

// `veil` holds (origin y, px per pt, top, bottom), (y0, y1, σ, 0) and the straight RGBA colour.
- (void)encodePyramid:(id<MTLTexture>)pyramid
           fromLinear:(id<MTLTexture>)linear
                 veil:(const float *)veil
        commandBuffer:(id<MTLCommandBuffer>)commandBuffer;

// Level 0 is `linear` over `underlay`, placed at `underlayRect` in capture points, over the opaque `base` colour.
- (void)encodePyramid:(id<MTLTexture>)pyramid
           fromLinear:(id<MTLTexture>)linear
             underlay:(id<MTLTexture>)underlay
         underlayRect:(CGRect)underlayRect
              pxPerPt:(CGFloat)pxPerPt
                 base:(const float *)baseRGBA
        commandBuffer:(id<MTLCommandBuffer>)commandBuffer;

// With `output`, the drawable is also copied there, so the layer must not be framebufferOnly.
- (void)drawInLayer:(CAMetalLayer *)layer
        surfaceSize:(CGSize)surfaceSizePt
           uniforms:(const GLSGlassUniforms *)uniforms
           elements:(const GLSElement *)elements
           backdrop:(id<MTLTexture>)backdrop
            content:(nullable id<MTLTexture>)content
        vibrantMask:(nullable id<MTLTexture>)vibrantMask
             output:(nullable id<MTLTexture>)output;

@end

NS_ASSUME_NONNULL_END
