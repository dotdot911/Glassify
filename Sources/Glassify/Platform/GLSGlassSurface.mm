//
//  GLSGlassSurface.mm
//  Glassify
//
//  Copyright © 2026 Hung Phan.
//  See LICENSE file for license information.
//

#import "GLSGlassSurface.h"

#import "GLSScrollEdgeEffectViewInternal.h"

#import "GLSBackdrop.h"
#import "GLSContentMask.h"
#import "GLSRenderer.h"

#include <algorithm>
#include <cmath>

using namespace glassify;

Appearance GLSTraitAppearance(UITraitCollection *traits) {
    return traits.userInterfaceStyle == UIUserInterfaceStyleDark ? Appearance::Dark : Appearance::Light;
}

GlassInputs GLSResolveInputs(const GLSSurfaceRequest &request, UITraitCollection *traits, Appearance appearance,
                             float backdropLuma) {
    GlassInputs inputs = glassInputsFor(request.style, appearance, float(request.lawSize.width),
                                        float(request.lawSize.height), backdropLuma, request.frost);
    if (request.lawFromSize.width > 0 && request.lawFromSize.height > 0 && request.lawProgress != 1.f) {
        const GlassInputs from = glassInputsFor(request.style, appearance, float(request.lawFromSize.width),
                                                float(request.lawFromSize.height), backdropLuma, request.frost);
        inputs = lerp(from, inputs, request.lawProgress);
    }
    if (request.tint) {
        CGFloat r = 0, g = 0, b = 0, a = 0;
        UIColor *resolved = [request.tint resolvedColorWithTraitCollection:traits];
        if ([resolved getRed:&r green:&g blue:&b alpha:&a]) {
            const float rgba[4] = {float(r), float(g), float(b), float(a)};
            setTint(inputs, appearance, rgba);
        }
    }
    const float materialize = std::min(std::max(request.materialize, 0.f), 1.f);
    if (materialize < 1.f) inputs = lerp(identityGlassLike(inputs), inputs, materialize);
    static const BOOL lensOnly = [NSUserDefaults.standardUserDefaults boolForKey:@"debugLensOnly"];
    if (lensOnly) {
        inputs.face = ColorMatrixParams{};
        inputs.faceOpacity = 0;
        inputs.shadowOpacity = inputs.sdrShadowOpacity = 0;
        inputs.bleedOpacity = 0;
        inputs.highlightOpacity = 0;
        inputs.blurRadius = 0;
        inputs.clamp = 0;
        inputs.sdrHoldingToneEnabled = false;
        inputs.tint[3] = 0;
    }
    return inputs;
}

static constexpr CGFloat kSurfaceSlack = 16, kSurfaceSlackMax = 48;

@implementation GLSGlassSurface {
    CGSize _surfaceSize;
    GLSContentMask *_tintedMask;
    __weak UIView *_host;
    id<MTLTexture> _output;
    CGRect _outputRect;
    CAMetalLayer *_metalLayer;
    GLSBackdrop *_backdrop;
    CGRect _lastHostRectInSource;
    NSUInteger _lastBackdropGeneration;
    // Strong, because KVO must be removed before the layer goes away.
    CALayer *_observedLayer;
    BOOL _hasAppearance;
    Appearance _traitAppearance, _appearance;
    int _reportedAppearance;
    // A critically damped spring towards the quantized luma measurement.
    float _luma, _lumaVelocity;
    float _edgeLuma;
    GLSContentMask *_contentMask;
    CFTimeInterval _edgeLumaTime;
    CFTimeInterval _lumaTime;
    BOOL _lumaAnimating;
}

static void *kSourceBoundsContext = &kSourceBoundsContext;

- (instancetype)initWithHost:(UIView *)host {
    if (!(self = [super init])) return nil;
    _reportedAppearance = -1;
    _host = host;
    _backdropScale = 0.25;
    _edgeLuma = -1;
    _metalLayer = [CAMetalLayer layer];
    _metalLayer.device = [GLSRenderer shared].device;
    _metalLayer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    _metalLayer.opaque = NO;
    _metalLayer.framebufferOnly = YES;
    _metalLayer.presentsWithTransaction = YES;
    _metalLayer.actions = @{@"bounds": [NSNull null], @"position": [NSNull null],
                            @"contents": [NSNull null], @"hidden": [NSNull null]};
    [host.layer insertSublayer:_metalLayer atIndex:0];
    [GLSBackdrop registerGlassView:host];
    return self;
}

- (void)dealloc {
    [self observeSourceLayer:nil];
}

- (void)observeSourceLayer:(CALayer *)layer {
    if (_observedLayer == layer) return;
    [_observedLayer removeObserver:self forKeyPath:@"bounds" context:kSourceBoundsContext];
    _observedLayer = layer;
    [_observedLayer addObserver:self forKeyPath:@"bounds" options:0 context:kSourceBoundsContext];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change
                       context:(void *)context {
    if (context != kSourceBoundsContext) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }
    if (_sourceDidMove) _sourceDidMove();
}

- (void)setHidden:(BOOL)hidden {
    _hidden = hidden;
    _metalLayer.hidden = hidden;
}

- (void)setSource:(UIView *)source {
    if (_source == source) return;
    _source = source;
    [self rebind];
}

- (void)setBackdropScale:(CGFloat)backdropScale {
    if (_backdropScale == backdropScale) return;
    _backdropScale = backdropScale;
    [self rebind];
}

- (void)rebind {
    _backdrop = nil;
    UIView *source = _source;
    [self observeSourceLayer:source.layer];
    if (!source || !_host) return;
    _backdrop = [[GLSBackdrop alloc] initWithSource:source backdropScale:_backdropScale];
    _backdrop.baseColor = _backdropBaseColor;
}

- (void)setNeedsBackdropUpdate {
    [_backdrop invalidate];
}

- (UIView *)host { return _host; }
- (id<MTLTexture>)outputTexture { return _output; }
- (CGRect)outputRect { return _outputRect; }

- (void)setKeepsOutput:(BOOL)keepsOutput {
    _keepsOutput = keepsOutput;
    _metalLayer.framebufferOnly = !keepsOutput;
    if (!keepsOutput) _output = nil;
}

- (void)setBackdropBaseColor:(UIColor *)backdropBaseColor {
    _backdropBaseColor = backdropBaseColor;
    _backdrop.baseColor = backdropBaseColor;
    [_backdrop invalidate];
}

- (CGRect)hostRectInSource {
    CALayer *layer = _host.layer.presentationLayer ?: _host.layer;
    CALayer *sourceLayer = _source.layer.presentationLayer ?: _source.layer;
    return [layer convertRect:layer.bounds toLayer:sourceLayer];
}

// Response 0.5 s, damping fraction 1; the first measurement is taken as is, so the glass does not fade in from the default luma.
- (void)stepLumaTowards:(float)target {
    const CFTimeInterval now = CACurrentMediaTime();
    if (_lumaTime == 0) {
        _luma = target;
        _lumaVelocity = 0;
    } else {
        const float omega = 2.f * float(M_PI) / 0.5f;
        float dt = float(std::min(now - _lumaTime, 1.0 / 20.0));
        for (; dt > 0; dt -= 1.f / 240.f) {
            const float h = std::min(dt, 1.f / 240.f);
            const float a = -omega * omega * (_luma - target) - 2.f * omega * _lumaVelocity;
            _lumaVelocity += a * h;
            _luma += _lumaVelocity * h;
        }
    }
    _lumaTime = now;
    const BOOL animating = std::fabs(_luma - target) > 1e-3f || std::fabs(_lumaVelocity) > 1e-2f;
    if (!animating) {
        _luma = target;
        _lumaVelocity = 0;
    }
    if (animating && !_lumaAnimating && _needsFrames) _needsFrames();
    _lumaAnimating = animating;
}

- (BOOL)isStale {
    if (!_backdrop || !_source) return NO;
    return _lumaAnimating || _backdrop.invalidated || _backdrop.generation != _lastBackdropGeneration ||
           !CGRectEqualToRect([self hostRectInSource], _lastHostRectInSource);
}

- (void)render:(const GLSSurfaceRequest &)request {
    GLSRenderer *renderer = [GLSRenderer shared];
    UIView *host = _host;
    UIView *source = _source;
    if (_hidden || !renderer || !host || !source || !host.window || request.elements.empty()) return;
    if (!_backdrop) [self rebind];
    CALayer *hostLayer = host.layer.presentationLayer ?: host.layer;
    CALayer *sourceLayer = source.layer.presentationLayer ?: source.layer;
    const CGSize hostSize = hostLayer.bounds.size;
    if (hostSize.width <= 0 || hostSize.height <= 0) return;

    CGRect shapes = CGRectNull;
    for (const ShapeElement &e : request.elements) {
        shapes = CGRectUnion(shapes, CGRectMake(e.centerX - e.width / 2, e.centerY - e.height / 2, e.width, e.height));
    }
    const Appearance traitAppearance = GLSTraitAppearance(host.traitCollection);
    if (!_hasAppearance || traitAppearance != _traitAppearance) {
        _traitAppearance = _appearance = traitAppearance;
        _hasAppearance = YES;
    }
    GlassInputs inputs = request.inputs ? *request.inputs : GLSResolveInputs(request, host.traitCollection, _appearance, -1.f);
    const CGFloat margin = std::ceil(std::max<CGFloat>({inputs.marginWidth, 2.f * inputs.shadowRadius + 8.f,
                                                        inputs.tint[3] > 0 ? inputs.tintFadeDistance + 2.f : 0.f}));
    const CGRect neededRect = CGRectIntegral(CGRectInset(shapes, -margin, -margin));
    const CGSize need = neededRect.size;
    if (_surfaceSize.width < need.width || _surfaceSize.height < need.height ||
        _surfaceSize.width > need.width + 2 * kSurfaceSlackMax || _surfaceSize.height > need.height + 2 * kSurfaceSlackMax) {
        _surfaceSize = CGSizeMake(need.width + 2 * kSurfaceSlack, need.height + 2 * kSurfaceSlack);
    }
    const CGRect surfaceRect = CGRectMake(std::floor(CGRectGetMidX(neededRect) - _surfaceSize.width / 2),
                                          std::floor(CGRectGetMidY(neededRect) - _surfaceSize.height / 2),
                                          _surfaceSize.width, _surfaceSize.height);

    const CGRect surfaceInSource = [hostLayer convertRect:surfaceRect toLayer:sourceLayer];
    const CGSize surfaceScale = CGSizeMake(surfaceInSource.size.width / surfaceRect.size.width,
                                           surfaceInSource.size.height / surfaceRect.size.height);

    const float lodScale = std::exp2(std::max(0.f, inputs.blurLodBias + request.lodBias));
    const float faceLens = std::max({0.f, inputs.innerRefractionAmount, inputs.outerRefractionAmount});
    const float faceReach = faceLens + 2.f * inputs.blurRadius * lodScale;
    const float fullReach = std::max({faceReach, std::max(0.f, inputs.bleedAmount) + 2.f * inputs.bleedBlurRadius * lodScale,
                                      float(margin) + std::fabs(inputs.shadowAmount) + inputs.shadowBlurRadius * lodScale});
    const CGRect shapesInSource = [hostLayer convertRect:shapes toLayer:sourceLayer];
    const CGFloat k = surfaceScale.width;
    GLSGlassSurface *underlay = _underlaySurface;
    UIView *underlayHost = underlay.host;
    if (underlay.outputTexture && underlayHost) {
        CALayer *underLayer = underlayHost.layer.presentationLayer ?: underlayHost.layer;
        _backdrop.underlayTexture = underlay.outputTexture;
        _backdrop.underlayRect = [underLayer convertRect:underlay.outputRect toLayer:sourceLayer];
        GLSBackdrop *page = underlay.backdrop;
        UIView *pageSource = page.source;
        if (page.texture && pageSource && pageSource != source) {
            CALayer *pageLayer = pageSource.layer.presentationLayer ?: pageSource.layer;
            _backdrop.pageTexture = page.texture;
            _backdrop.pageRect = [pageLayer convertRect:page.capturedRect toLayer:sourceLayer];
        } else {
            _backdrop.pageTexture = nil;
        }
    } else {
        _backdrop.underlayTexture = nil;
        _backdrop.pageTexture = nil;
    }
    UIView *edge = request.lumaEdge;
    _backdrop.veil = edge && ![edge isDescendantOfView:source] ? [(GLSScrollEdgeEffectView *)edge gls_veilInView:source]
                                                              : GLSBackdropVeil{};
    [_backdrop updateForRect:CGRectInset(shapesInSource, -faceReach * k, -faceReach * k)
                  wantedRect:CGRectInset(shapesInSource, -fullReach * k, -fullReach * k)];
    id<MTLTexture> backdropTexture = _backdrop.texture;
    if (!backdropTexture) return;

    const CGRect hostInSource = [self hostRectInSource];
    const CGSize scaleInSource = CGSizeMake(hostInSource.size.width / hostSize.width,
                                            hostInSource.size.height / hostSize.height);

    if (!request.inputs && request.style == GlassStyle::Regular &&
        std::min(request.lawSize.width, request.lawSize.height) <= 64) {
        const CGRect inSource = CGRectMake(hostInSource.origin.x + shapes.origin.x * scaleInSource.width,
                                           hostInSource.origin.y + shapes.origin.y * scaleInSource.height,
                                           shapes.size.width * scaleInSource.width, shapes.size.height * scaleInSource.height);
        float measured = [_backdrop meanLumaInRect:CGRectInset(inSource, -10, -10)];
        if (UIView *edge = request.lumaEdge) {
            const CFTimeInterval now = CACurrentMediaTime();
            if (_edgeLuma < 0 || now - _edgeLumaTime >= 0.25) {
                const CGRect band = [edge.superview convertRect:[(GLSScrollEdgeEffectView *)edge lumaRect] toView:source];
                _edgeLuma = [_backdrop lumaInRect:band hiding:edge];
                _edgeLumaTime = now;
                if (_needsFrames) _needsFrames();
            }
            if (_edgeLuma >= 0) measured = _edgeLuma;
        }
#if DEBUG
        static const NSInteger forced = [NSUserDefaults.standardUserDefaults objectForKey:@"forceluma"]
            ? [NSUserDefaults.standardUserDefaults integerForKey:@"forceluma"] : -1;
        if (forced >= 0) measured = (float(forced) + 0.5f) / 32.f;
        static const BOOL lumaLog = [NSUserDefaults.standardUserDefaults boolForKey:@"lumalog"];
        if (lumaLog) NSLog(@"GLSLUMA %.4f (%d/31) rect %@ source %@", measured, int(std::min(measured * 32.f, 31.f)),
                           NSStringFromCGRect(CGRectInset(inSource, -10, -10)), NSStringFromClass(_backdrop.source.class));
#endif
        if (measured >= 0) {
            const float target = quantizeLuma(measured);
            if (request.adaptsColorScheme) _appearance = adaptAppearance(_appearance, target);
            [self stepLumaTowards:target];
            inputs = GLSResolveInputs(request, host.traitCollection, _appearance, _luma);
        }
    }

    const float materialize = std::min(std::max(request.materialize, 0.f), 1.f);
    const Appearance appearance = _appearance;
    if (_appearanceDidChange && _reportedAppearance != int(appearance)) {
        _reportedAppearance = int(appearance);
        _appearanceDidChange(appearance == Appearance::Dark);
    }

    CGFloat magnification = 1;
    if (CALayer *windowLayer = host.window.layer.presentationLayer ?: host.window.layer) {
        const CGRect onScreen = [hostLayer convertRect:hostLayer.bounds toLayer:windowLayer];
        magnification = std::max(onScreen.size.width / hostSize.width, onScreen.size.height / hostSize.height);
        magnification = std::min(std::max(std::ceil(magnification * 8) / 8, CGFloat(1)), CGFloat(4));
    }
    const CGFloat screenScale = host.window.screen.scale * magnification;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _metalLayer.frame = surfaceRect;
    _metalLayer.opacity = std::min(2.f * materialize, 1.f) * request.opacity;
    _metalLayer.contentsScale = screenScale;
    const CGSize drawableSize = CGSizeMake(std::ceil(surfaceRect.size.width * screenScale),
                                           std::ceil(surfaceRect.size.height * screenScale));
    if (!CGSizeEqualToSize(_metalLayer.drawableSize, drawableSize)) _metalLayer.drawableSize = drawableSize;
    [CATransaction commit];

    std::vector<ShapeElement> elements = request.elements;
    for (ShapeElement &e : elements) {
        e.centerX -= float(surfaceRect.origin.x);
        e.centerY -= float(surfaceRect.origin.y);
    }

    const CGRect captured = _backdrop.capturedRect;
    PackContext ctx;
    ctx.ptToPx = float(screenScale);
    ctx.smoothness = request.smoothness;
    ctx.elements = elements.data();
    ctx.elementCount = int(elements.size());
    ctx.backdropOriginX = float((captured.origin.x - surfaceInSource.origin.x) / surfaceScale.width);
    ctx.backdropOriginY = float((captured.origin.y - surfaceInSource.origin.y) / surfaceScale.height);
    ctx.backdropWidth = float(captured.size.width / surfaceScale.width);
    ctx.backdropHeight = float(captured.size.height / surfaceScale.height);
    ctx.backdropPxPerPt = float(_backdrop.pixelsPerPoint * surfaceScale.width);
    ctx.backdropMaxLod = float(backdropTexture.mipmapLevelCount - 1);
    ctx.lodBias = request.lodBias;
    if (request.content) {
        ctx.hasContent = true;
        ctx.contentOriginX = float(request.contentRect.origin.x - surfaceRect.origin.x);
        ctx.contentOriginY = float(request.contentRect.origin.y - surfaceRect.origin.y);
        ctx.contentWidth = float(request.contentRect.size.width);
        ctx.contentHeight = float(request.contentRect.size.height);
    }

    GLSGlassUniforms uniforms;
    packUniforms(inputs, ctx, uniforms);
    GlowState glow = request.glow;
    glow.centerX -= float(surfaceRect.origin.x);
    glow.centerY -= float(surfaceRect.origin.y);
    glow.dark = appearance == Appearance::Dark;
    if (request.frost != Frost::Automatic && _lumaTime != 0) glow.luma = _luma;
    static const int edr = [] {
        int mode = 0;
        if (@available(iOS 16.0, *)) mode = UIScreen.mainScreen.potentialEDRHeadroom > 1 ? 3 : 0;
#if DEBUG
        if ([NSUserDefaults.standardUserDefaults objectForKey:@"edr"])
            mode = int([NSUserDefaults.standardUserDefaults integerForKey:@"edr"]);
#endif
        return mode;
    }();
    glow.edr = edr;
    packGlow(glow, uniforms);
    GLSElement packed[GLS_MAX_ELEMENTS] = {};
    packElements(ctx, packed);

    if (_keepsOutput) {
        const NSUInteger w = NSUInteger(_metalLayer.drawableSize.width), h = NSUInteger(_metalLayer.drawableSize.height);
        if (!_output || _output.width != w || _output.height != h) {
            MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:_metalLayer.pixelFormat
                                                                                          width:w
                                                                                         height:h
                                                                                      mipmapped:NO];
            td.usage = MTLTextureUsageShaderRead;
            td.storageMode = MTLStorageModePrivate;
            _output = [renderer.device newTextureWithDescriptor:td];
        }
        _outputRect = surfaceRect;
    }
    CALayer *maskLayer = host.layer;
    CGRect maskRect = surfaceRect;
    CGAffineTransform surfaceToMask = CGAffineTransformMakeScale(1 / surfaceRect.size.width, 1 / surfaceRect.size.height);
    if (UIView *reference = request.vibrantReference) {
        maskLayer = reference.layer;
        maskRect = reference.bounds;
        CALayer *shownReference = reference.layer.presentationLayer ?: reference.layer;
        CALayer *shownHost = host.layer.presentationLayer ?: host.layer;
        const CGPoint a = [shownReference convertPoint:CGPointZero toLayer:shownHost];
        const CGPoint x = [shownReference convertPoint:CGPointMake(1, 0) toLayer:shownHost];
        const CGPoint y = [shownReference convertPoint:CGPointMake(0, 1) toLayer:shownHost];
        const CGAffineTransform localToHost = CGAffineTransformMake(x.x - a.x, x.y - a.y, y.x - a.x, y.y - a.y, a.x, a.y);
        surfaceToMask = CGAffineTransformConcat(
            CGAffineTransformConcat(CGAffineTransformMakeTranslation(surfaceRect.origin.x, surfaceRect.origin.y),
                                    CGAffineTransformInvert(localToHost)),
            CGAffineTransformConcat(CGAffineTransformMakeTranslation(-maskRect.origin.x, -maskRect.origin.y),
                                    CGAffineTransformMakeScale(1 / maskRect.size.width, 1 / maskRect.size.height)));
    }
    uniforms.vibrantMap0 = {float(surfaceToMask.a), float(surfaceToMask.c), float(surfaceToMask.tx), 0.f};
    uniforms.vibrantMap1 = {float(surfaceToMask.b), float(surfaceToMask.d), float(surfaceToMask.ty), 0.f};
    id<MTLTexture> vibrantMask = nil;
    if (request.vibrantViews.count) {
        if (!_contentMask) _contentMask = [GLSContentMask new];
        vibrantMask = [_contentMask maskForViews:request.vibrantViews hostLayer:maskLayer rect:maskRect
                                           scale:screenScale device:renderer.device];
    }
    id<MTLTexture> tintedMask = nil;
    if (request.tintedVibrantViews.count) {
        if (!_tintedMask) _tintedMask = [GLSContentMask new];
        tintedMask = [_tintedMask maskForViews:request.tintedVibrantViews hostLayer:maskLayer rect:maskRect
                                         scale:screenScale device:renderer.device];
    }
    if (tintedMask) {
        const int scheme = appearance == Appearance::Dark ? 1 : 0;
        uniforms.vibrant0 = {1.f, float(1.0 / surfaceRect.size.width), float(1.0 / surfaceRect.size.height), 0.f};
        uniforms.vibrant1.x = 1.f;
        uniforms.vibrant1.y = request.tintedOpacity;
        for (int r = 0; r < 3; ++r) {
            const float *row = request.tintedMatrix[scheme][r];
            uniforms.vibrantCM2[r] = {row[0], row[1], row[2], row[3]};
        }
    }
    if (!CGRectIsNull(request.vibrantHole)) {
        const CGRect h = request.vibrantHole;
        uniforms.vibrant1.z = float(std::min(h.size.width, h.size.height) / 2);
        uniforms.vibrant1.w = 1.f;
        uniforms.vibrantHole = {float(CGRectGetMidX(h) - surfaceRect.origin.x), float(CGRectGetMidY(h) - surfaceRect.origin.y),
                                float(h.size.width / 2), float(h.size.height / 2)};
    }
    if (vibrantMask) {
        const bool dark = appearance == Appearance::Dark;
        const float b = dark ? 0.95f : 0.9f, c = dark ? 0.95f : 0.f;
        const float y[3] = {0.2126f, 0.7152f, 0.0722f};
        uniforms.vibrant0 = {1.f, float(1.0 / surfaceRect.size.width), float(1.0 / surfaceRect.size.height), 0.f};
        for (int r = 0; r < 3; ++r) {
            float row[4] = {-b * y[0], -b * y[1], -b * y[2], c};
            row[r] += 1.f;
            uniforms.vibrantCM[r] = {row[0], row[1], row[2], row[3]};
        }
    }
    [renderer drawInLayer:_metalLayer
              surfaceSize:surfaceRect.size
                 uniforms:&uniforms
                 elements:packed
                 backdrop:backdropTexture
                  content:request.content
              vibrantMask:vibrantMask
               tintedMask:tintedMask
                   output:_keepsOutput ? _output : nil];

    _lastHostRectInSource = hostInSource;
    _lastBackdropGeneration = _backdrop.generation;
}

@end

#pragma mark - Frame driver

@implementation GLSFrameDriver {
    CADisplayLink *_link;
    // Client to deadline.
    NSMapTable<id<GLSFrameClient>, NSNumber *> *_clients;
    CFTimeInterval _lastTimestamp, _statsStart, _tickTotal, _tickMax;
    NSUInteger _ticks, _missed;
}

+ (instancetype)shared {
    static GLSFrameDriver *driver;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ driver = [GLSFrameDriver new]; });
    return driver;
}

- (instancetype)init {
    if (!(self = [super init])) return nil;
    _clients = [NSMapTable weakToStrongObjectsMapTable];
    return self;
}

- (void)addClient:(id<GLSFrameClient>)client until:(CFTimeInterval)deadline {
    NSNumber *existing = [_clients objectForKey:client];
    if (!existing || existing.doubleValue < deadline) [_clients setObject:@(deadline) forKey:client];
    if (!_link) {
        _link = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
        [_link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    }
    _link.paused = NO;
}

- (void)removeClient:(id<GLSFrameClient>)client {
    [_clients removeObjectForKey:client];
}

- (void)tick:(CADisplayLink *)link {
    const CFTimeInterval now = CACurrentMediaTime();
    if ([GLSBackdrop logsStats]) [self recordTickStart:link];
    NSMutableArray *expired = [NSMutableArray array];
    for (id<GLSFrameClient> client in [[_clients keyEnumerator] allObjects]) {
        if (now > [_clients objectForKey:client].doubleValue && ![client wantsContinuousFrames]) {
            [expired addObject:client];
        }
        [client driverTick];
    }
    for (id client in expired) [_clients removeObjectForKey:client];
    if (_clients.count == 0) link.paused = YES;
    if ([GLSBackdrop logsStats]) [self recordTickEnd:CACurrentMediaTime() - now];
    static const BOOL slowLog = [NSUserDefaults.standardUserDefaults boolForKey:@"slowlog"];
    const CFTimeInterval spent = CACurrentMediaTime() - now;
    if (slowLog && spent > 0.012) NSLog(@"GLSSLOW tick %.1f ms (%lu clients)", spent * 1000, (unsigned long)_clients.count);
}

// The -stats 1 launch argument logs main-thread time in the frame driver and frames missed by the display link.
- (void)recordTickStart:(CADisplayLink *)link {
    if (_lastTimestamp > 0) {
        const CFTimeInterval interval = link.timestamp - _lastTimestamp;
        const CFTimeInterval expected = link.targetTimestamp - link.timestamp;
        if (expected > 0 && interval > expected * 1.5) _missed += NSUInteger(std::lround(interval / expected)) - 1;
    }
    _lastTimestamp = link.timestamp;
}

- (void)recordTickEnd:(CFTimeInterval)seconds {
    const CFTimeInterval now = CACurrentMediaTime();
    if (_statsStart == 0) _statsStart = now;
    _tickTotal += seconds;
    _tickMax = std::max(_tickMax, seconds);
    _ticks += 1;
    if (now - _statsStart >= 1.0) {
        NSString *line = [NSString stringWithFormat:@"driver: %lu ticks/s, %.2f ms avg, %.2f ms max, %lu missed",
                                                    (unsigned long)_ticks, _tickTotal * 1000.0 / _ticks, _tickMax * 1000.0,
                                                    (unsigned long)_missed];
        NSLog(@"[glassify] %@", line);
        [NSNotificationCenter.defaultCenter postNotificationName:@"GLSStatsLine" object:@"driver" userInfo:@{@"line" : line}];
        _statsStart = now;
        _tickTotal = _tickMax = 0;
        _ticks = _missed = 0;
    }
}

@end
