//
//  GLSRenderer.mm
//  Glassify
//
//  Copyright © 2026 Hung Phan.
//  See LICENSE file for license information.
//

#import "GLSRenderer.h"

#if __has_include("resource_bundle_accessor.h")
#import "resource_bundle_accessor.h"
#endif

// The first bundle whose library has the glass functions wins, since an app may have its own default library.
static id<MTLLibrary> LoadShaderLibrary(id<MTLDevice> device) {
    NSBundle *code = [NSBundle bundleForClass:[GLSRenderer class]];
    NSMutableArray<NSBundle *> *bundles = [NSMutableArray array];
#ifdef SWIFTPM_MODULE_BUNDLE
    [bundles addObject:SWIFTPM_MODULE_BUNDLE];
#endif
    for (NSString *name in @[ @"Glassify_Glassify", @"GlassifyShaders" ]) {
        for (NSBundle *parent in @[ code, NSBundle.mainBundle ]) {
            NSURL *url = [parent URLForResource:name withExtension:@"bundle"];
            NSBundle *bundle = url ? [NSBundle bundleWithURL:url] : nil;
            if (bundle) [bundles addObject:bundle];
        }
    }
    [bundles addObject:code];
    for (NSBundle *bundle in bundles) {
        id<MTLLibrary> library = [device newDefaultLibraryWithBundle:bundle error:nil];
        if ([library newFunctionWithName:@"gls_glass_background"]) return library;
    }
    return nil;
}

@implementation GLSRenderer {
    id<MTLRenderPipelineState> _backgroundPipeline;
    // Reads the destination through framebuffer fetch, which only devices have.
    id<MTLRenderPipelineState> _highlightPipeline;
    // The simulator has no framebuffer fetch, so the highlight reads an offscreen copy.
    id<MTLRenderPipelineState> _highlightTexturePipeline;
    id<MTLComputePipelineState> _downsamplePipeline;
    id<MTLComputePipelineState> _underlayPipeline;
    id<MTLComputePipelineState> _veilPipeline;
    id<MTLTexture> _offscreen;
    id<MTLTexture> _emptyTexture;
}

+ (instancetype)shared {
    static GLSRenderer *renderer;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ renderer = [[GLSRenderer alloc] initPrivate]; });
    return renderer;
}

- (nullable instancetype)initPrivate {
    if (!(self = [super init])) return nil;
    _device = MTLCreateSystemDefaultDevice();
    if (!_device) return nil;
    _queue = [_device newCommandQueue];

    NSError *error = nil;
    id<MTLLibrary> library = LoadShaderLibrary(_device);
    if (!library) {
        NSLog(@"[glassify] no Metal library with Glassify's shaders");
        return nil;
    }

    MTLRenderPipelineDescriptor *desc = [MTLRenderPipelineDescriptor new];
    desc.vertexFunction = [library newFunctionWithName:@"gls_fullscreen_vertex"];
    desc.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;

    desc.fragmentFunction = [library newFunctionWithName:@"gls_glass_background"];
    desc.colorAttachments[0].blendingEnabled = YES;
    desc.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorOne;
    desc.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorOne;
    desc.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    desc.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    _backgroundPipeline = [_device newRenderPipelineStateWithDescriptor:desc error:&error];

    desc.fragmentFunction = [library newFunctionWithName:@"gls_glass_highlight"];
    desc.colorAttachments[0].blendingEnabled = NO;
    _highlightPipeline = [_device newRenderPipelineStateWithDescriptor:desc error:nil];
    if (!_highlightPipeline) {
        desc.fragmentFunction = [library newFunctionWithName:@"gls_glass_highlight_texture"];
        _highlightTexturePipeline = [_device newRenderPipelineStateWithDescriptor:desc error:&error];
    }

    _downsamplePipeline = [_device newComputePipelineStateWithFunction:[library newFunctionWithName:@"gls_downsample13"]
                                                                 error:&error];
    _underlayPipeline = [_device newComputePipelineStateWithFunction:[library newFunctionWithName:@"gls_composite_underlay"]
                                                               error:&error];
    _veilPipeline = [_device newComputePipelineStateWithFunction:[library newFunctionWithName:@"gls_composite_veil"]
                                                               error:&error];
    if (!_underlayPipeline || !_backgroundPipeline || !(_highlightPipeline || _highlightTexturePipeline) || !_downsamplePipeline) {
        NSLog(@"[glassify] pipeline creation failed (background %d, highlight %d, downsample %d): %@",
              _backgroundPipeline != nil, _highlightPipeline != nil, _downsamplePipeline != nil, error);
        return nil;
    }
    return self;
}

- (void)encodePyramid:(id<MTLTexture>)pyramid
           fromLinear:(id<MTLTexture>)linear
        commandBuffer:(id<MTLCommandBuffer>)commandBuffer {
    [self encodePyramid:pyramid fromLinear:linear underlay:nil underlayRect:CGRectZero pxPerPt:1 base:nullptr
          commandBuffer:commandBuffer];
}

- (void)encodePyramid:(id<MTLTexture>)pyramid
           fromLinear:(id<MTLTexture>)linear
                 veil:(const float *)veil
        commandBuffer:(id<MTLCommandBuffer>)commandBuffer {
    [self encodePyramid:pyramid fromLinear:linear underlay:nil underlayRect:CGRectZero pxPerPt:1 base:nullptr veil:veil
          commandBuffer:commandBuffer];
}

- (void)encodePyramid:(id<MTLTexture>)pyramid
           fromLinear:(id<MTLTexture>)linear
             underlay:(id<MTLTexture>)underlay
         underlayRect:(CGRect)underlayRect
              pxPerPt:(CGFloat)pxPerPt
                 base:(const float *)baseRGBA
        commandBuffer:(id<MTLCommandBuffer>)commandBuffer {
    [self encodePyramid:pyramid fromLinear:linear underlay:underlay underlayRect:underlayRect pxPerPt:pxPerPt
                   base:baseRGBA veil:nullptr commandBuffer:commandBuffer];
}

- (void)encodePyramid:(id<MTLTexture>)pyramid
           fromLinear:(id<MTLTexture>)linear
             underlay:(id<MTLTexture>)underlay
         underlayRect:(CGRect)underlayRect
              pxPerPt:(CGFloat)pxPerPt
                 base:(const float *)baseRGBA
                 veil:(const float *)veil
        commandBuffer:(id<MTLCommandBuffer>)commandBuffer {
    if (veil && !underlay && _veilPipeline) {
        id<MTLTexture> level0 = [pyramid newTextureViewWithPixelFormat:pyramid.pixelFormat
                                                            textureType:MTLTextureType2D
                                                                 levels:NSMakeRange(0, 1)
                                                                 slices:NSMakeRange(0, 1)];
        id<MTLComputeCommandEncoder> compute = [commandBuffer computeCommandEncoder];
        [compute setComputePipelineState:_veilPipeline];
        [compute setTexture:linear atIndex:0];
        [compute setTexture:level0 atIndex:1];
        [compute setBytes:veil length:12 * sizeof(float) atIndex:0];
        const NSUInteger w = _veilPipeline.threadExecutionWidth;
        const NSUInteger h = _veilPipeline.maxTotalThreadsPerThreadgroup / w;
        [compute dispatchThreadgroups:MTLSizeMake((linear.width + w - 1) / w, (linear.height + h - 1) / h, 1)
                threadsPerThreadgroup:MTLSizeMake(w, h, 1)];
        [compute endEncoding];
    } else if (underlay) {
        id<MTLTexture> level0 = [pyramid newTextureViewWithPixelFormat:pyramid.pixelFormat
                                                            textureType:MTLTextureType2D
                                                                 levels:NSMakeRange(0, 1)
                                                                 slices:NSMakeRange(0, 1)];
        const float params[8] = {float(underlayRect.origin.x * pxPerPt), float(underlayRect.origin.y * pxPerPt),
                                 float(underlayRect.size.width * pxPerPt), float(underlayRect.size.height * pxPerPt),
                                 baseRGBA[0], baseRGBA[1], baseRGBA[2], baseRGBA[3]};
        id<MTLComputeCommandEncoder> compute = [commandBuffer computeCommandEncoder];
        [compute setComputePipelineState:_underlayPipeline];
        [compute setTexture:linear atIndex:0];
        [compute setTexture:underlay atIndex:1];
        [compute setTexture:level0 atIndex:2];
        [compute setBytes:params length:sizeof(params) atIndex:0];
        const NSUInteger w = _underlayPipeline.threadExecutionWidth;
        const NSUInteger h = _underlayPipeline.maxTotalThreadsPerThreadgroup / w;
        [compute dispatchThreadgroups:MTLSizeMake((linear.width + w - 1) / w, (linear.height + h - 1) / h, 1)
                threadsPerThreadgroup:MTLSizeMake(w, h, 1)];
        [compute endEncoding];
    } else {
        id<MTLBlitCommandEncoder> blit = [commandBuffer blitCommandEncoder];
        [blit copyFromTexture:linear sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0, 0, 0)
                   sourceSize:MTLSizeMake(linear.width, linear.height, 1)
                    toTexture:pyramid destinationSlice:0 destinationLevel:0 destinationOrigin:MTLOriginMake(0, 0, 0)];
        [blit endEncoding];
    }

    if (pyramid.mipmapLevelCount < 2) return;
    id<MTLComputeCommandEncoder> compute = [commandBuffer computeCommandEncoder];
    [compute setComputePipelineState:_downsamplePipeline];
    for (NSUInteger level = 1; level < pyramid.mipmapLevelCount; ++level) {
        id<MTLTexture> src = [pyramid newTextureViewWithPixelFormat:pyramid.pixelFormat
                                                        textureType:MTLTextureType2D
                                                             levels:NSMakeRange(level - 1, 1)
                                                             slices:NSMakeRange(0, 1)];
        id<MTLTexture> dst = [pyramid newTextureViewWithPixelFormat:pyramid.pixelFormat
                                                        textureType:MTLTextureType2D
                                                             levels:NSMakeRange(level, 1)
                                                             slices:NSMakeRange(0, 1)];
        [compute setTexture:src atIndex:0];
        [compute setTexture:dst atIndex:1];
        const NSUInteger w = _downsamplePipeline.threadExecutionWidth;
        const NSUInteger h = _downsamplePipeline.maxTotalThreadsPerThreadgroup / w;
        const MTLSize group = MTLSizeMake(w, h, 1);
        const MTLSize grid = MTLSizeMake((dst.width + w - 1) / w, (dst.height + h - 1) / h, 1);
        [compute dispatchThreadgroups:grid threadsPerThreadgroup:group];
    }
    [compute endEncoding];
}

// Bound when a draw has no lens content.
- (id<MTLTexture>)emptyTexture {
    if (!_emptyTexture) {
        MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                                                                      width:1
                                                                                     height:1
                                                                                  mipmapped:NO];
        _emptyTexture = [_device newTextureWithDescriptor:td];
        const uint32_t zero = 0;
        [_emptyTexture replaceRegion:MTLRegionMake2D(0, 0, 1, 1) mipmapLevel:0 withBytes:&zero bytesPerRow:4];
    }
    return _emptyTexture;
}

// Presents with the CA transaction, or the glass's content and geometry land on different frames.
- (void)drawInLayer:(CAMetalLayer *)layer
        surfaceSize:(CGSize)surfaceSizePt
           uniforms:(const GLSGlassUniforms *)uniforms
           elements:(const GLSElement *)elements
           backdrop:(id<MTLTexture>)backdrop
            content:(id<MTLTexture>)content
        vibrantMask:(id<MTLTexture>)vibrantMask
             output:(id<MTLTexture>)output {
    if (!content) content = [self emptyTexture];
    if (!vibrantMask) vibrantMask = [self emptyTexture];
    const CFTimeInterval t0 = CACurrentMediaTime();
    id<CAMetalDrawable> drawable = [layer nextDrawable];
    const CFTimeInterval tDrawable = CACurrentMediaTime() - t0;
    if (!drawable) return;

    id<MTLCommandBuffer> commandBuffer = [_queue commandBuffer];
    const float surface[4] = {float(surfaceSizePt.width), float(surfaceSizePt.height), 0, 0};
    auto bind = [&](id<MTLRenderCommandEncoder> encoder) {
        [encoder setVertexBytes:surface length:sizeof(surface) atIndex:0];
        [encoder setFragmentBytes:uniforms length:sizeof(GLSGlassUniforms) atIndex:0];
        [encoder setFragmentBytes:elements length:sizeof(GLSElement) * GLS_MAX_ELEMENTS atIndex:1];
        [encoder setFragmentTexture:backdrop atIndex:0];
        [encoder setFragmentTexture:content atIndex:2];
        [encoder setFragmentTexture:vibrantMask atIndex:3];
    };

    MTLRenderPassDescriptor *pass = [MTLRenderPassDescriptor renderPassDescriptor];
    pass.colorAttachments[0].loadAction = MTLLoadActionClear;
    pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0);
    pass.colorAttachments[0].storeAction = MTLStoreActionStore;

    if (_highlightPipeline) {
        pass.colorAttachments[0].texture = drawable.texture;
        id<MTLRenderCommandEncoder> encoder = [commandBuffer renderCommandEncoderWithDescriptor:pass];
        bind(encoder);
        [encoder setRenderPipelineState:_backgroundPipeline];
        [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
        [encoder setRenderPipelineState:_highlightPipeline];
        [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
        [encoder endEncoding];
    } else {
        id<MTLTexture> target = drawable.texture;
        if (!_offscreen || _offscreen.width != target.width || _offscreen.height != target.height) {
            MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:target.pixelFormat
                                                                                          width:target.width
                                                                                         height:target.height
                                                                                      mipmapped:NO];
            td.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
            td.storageMode = MTLStorageModePrivate;
            _offscreen = [_device newTextureWithDescriptor:td];
        }
        pass.colorAttachments[0].texture = _offscreen;
        id<MTLRenderCommandEncoder> encoder = [commandBuffer renderCommandEncoderWithDescriptor:pass];
        bind(encoder);
        [encoder setRenderPipelineState:_backgroundPipeline];
        [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
        [encoder endEncoding];

        pass.colorAttachments[0].texture = target;
        pass.colorAttachments[0].loadAction = MTLLoadActionDontCare;
        encoder = [commandBuffer renderCommandEncoderWithDescriptor:pass];
        bind(encoder);
        [encoder setFragmentTexture:_offscreen atIndex:1];
        [encoder setRenderPipelineState:_highlightTexturePipeline];
        [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
        [encoder endEncoding];
    }

    if (output && output.width == drawable.texture.width && output.height == drawable.texture.height) {
        id<MTLBlitCommandEncoder> blit = [commandBuffer blitCommandEncoder];
        [blit copyFromTexture:drawable.texture toTexture:output];
        [blit endEncoding];
    }

    static const BOOL slowLog = [NSUserDefaults.standardUserDefaults boolForKey:@"slowlog"];
    if (slowLog) {
        const CGSize ds = layer.drawableSize;
        [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> cb) {
            const double gpu = (cb.GPUEndTime - cb.GPUStartTime) * 1000;
            if (gpu > 4 || tDrawable > 0.004)
                NSLog(@"GLSSLOW %.0fx%.0f drawable %.1f ms gpu %.1f ms", ds.width, ds.height, tDrawable * 1000, gpu);
        }];
    }
    [commandBuffer commit];
    [commandBuffer waitUntilScheduled];
    [drawable present];
}

@end
