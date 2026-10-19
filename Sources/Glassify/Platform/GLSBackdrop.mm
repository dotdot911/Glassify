//
//  GLSBackdrop.mm
//  Glassify
//
//  Copyright © 2026 Hung Phan.
//  See LICENSE file for license information.
//

#import "GLSBackdrop.h"
#import "Glassify/GLSDebug.h"

#import "GLSRenderer.h"

#include <algorithm>
#include <vector>
#include <cmath>

static BOOL gLogsStats = NO;

// Extra room captured around the needed rect, so that small moves reuse the snapshot.
static const CGFloat kSlackPt = 32;
// The capture grid in backdrop pixels, which keeps the mip blocks fixed to the content.
static const long kGridPx = 32;
// Storage grows in steps and is kept while it is at most this much too big, so moving glass does not reallocate.
static const long kStorageStepPx = 128, kStorageSlackPx = 256;

static NSHashTable<UIView *> *GlassViews() {
    static NSHashTable<UIView *> *views;
    if (!views) views = [NSHashTable weakObjectsHashTable];
    return views;
}

static BOOL VeilsEqual(const GLSBackdropVeil &a, const GLSBackdropVeil &b) {
    if (!a.on || !b.on) return a.on == b.on;
    return a.top == b.top && a.bottom == b.bottom && a.y0 == b.y0 && a.y1 == b.y1 && a.sigma == b.sigma &&
           memcmp(a.color, b.color, sizeof(a.color)) == 0;
}

@implementation GLSBackdrop {
    CGFloat _backdropScale;
    BOOL _dirty;
    // On devices the bitmap is the texture memory, so nothing is copied.
    id<MTLBuffer> _buffer;
    // The simulator has no linear textures on shared buffers, so it copies.
    NSMutableData *_cpuBitmap;
    id<MTLTexture> _linear;
    size_t _bytesPerRow;
    id<MTLCommandBuffer> _lastPyramid;
    GLSBackdropVeil _encodedVeil;
    // The part of `_capturedRect` that was on screen; the rest repeats its edge.
    CGRect _validRect;
    CFTimeInterval _statsStart, _captureTime;
    NSUInteger _captures;
}

+ (BOOL)logsStats { return gLogsStats; }
+ (void)setLogsStats:(BOOL)value { gLogsStats = value; }

+ (void)registerGlassView:(UIView *)view { [GlassViews() addObject:view]; }
+ (void)unregisterGlassView:(UIView *)view { [GlassViews() removeObject:view]; }

- (instancetype)initWithSource:(UIView *)source backdropScale:(CGFloat)backdropScale {
    if (!(self = [super init])) return nil;
    _source = source;
    _backdropScale = backdropScale;
    _dirty = YES;
    _capturedRect = CGRectNull;
    _validRect = CGRectNull;
    return self;
}

- (void)invalidate { _dirty = YES; }
- (BOOL)isInvalidated { return _dirty; }

- (BOOL)updateForRect:(CGRect)neededRect wantedRect:(CGRect)wantedRect {
    UIView *source = _source;
    GLSRenderer *renderer = [GLSRenderer shared];
    if (!source || !renderer) return NO;

    const CGFloat screenScale = source.window ? source.window.screen.scale : UIScreen.mainScreen.scale;
    const CGFloat s = screenScale * _backdropScale;
    const CGRect bounds = _underlayTexture && source.window ? [source convertRect:source.window.bounds fromView:nil]
                                                            : source.bounds;
    const long vx0 = long(std::ceil(CGRectGetMinX(bounds) * s)), vy0 = long(std::ceil(CGRectGetMinY(bounds) * s));
    const long vx1 = long(std::floor(CGRectGetMaxX(bounds) * s)), vy1 = long(std::floor(CGRectGetMaxY(bounds) * s));
    const CGRect visible = CGRectMake(vx0 / s, vy0 / s, (vx1 - vx0) / s, (vy1 - vy0) / s);
    const CGRect needed = CGRectIntersection(neededRect, visible);
    if (CGRectIsNull(needed) || CGRectIsEmpty(needed)) return NO;
    if (!_dirty && CGRectContainsRect(_validRect, needed)) {
        if (!VeilsEqual(_veil, _encodedVeil) && _linear) {
            [self encodePyramidFor:source renderer:renderer];
            _generation += 1;
            return YES;
        }
        return NO;
    }

    const CGRect want = CGRectInset(CGRectUnion(needed, wantedRect), -kSlackPt, -kSlackPt);
    auto snapDown = [](long v) { return long(std::floor(double(v) / kGridPx)) * kGridPx; };
    auto snapUp = [](long v) { return long(std::ceil(double(v) / kGridPx)) * kGridPx; };
    const long ix0 = std::max(long(std::floor(CGRectGetMinX(want) * s)), vx0);
    const long iy0 = std::max(long(std::floor(CGRectGetMinY(want) * s)), vy0);
    const long ix1 = std::min(long(std::ceil(CGRectGetMaxX(want) * s)), vx1);
    const long iy1 = std::min(long(std::ceil(CGRectGetMaxY(want) * s)), vy1);
    if (ix1 <= ix0 || iy1 <= iy0) return NO;
    const long x0 = snapDown(ix0), y0 = snapDown(iy0);
    auto storageSide = [](long needed, NSUInteger current) {
        if (long(current) >= needed && long(current) - needed <= kStorageSlackPx) return long(current);
        return (needed + kStorageStepPx - 1) / kStorageStepPx * kStorageStepPx;
    };
    const long x1 = x0 + storageSide(snapUp(ix1) - x0, _linear.width), y1 = y0 + storageSide(snapUp(iy1) - y0, _linear.height);
    const size_t width = size_t(x1 - x0), height = size_t(y1 - y0);
    const CGRect captured = CGRectMake(x0 / s, y0 / s, width / s, height / s);
    const CGRect valid = CGRectMake(ix0 / s, iy0 / s, (ix1 - ix0) / s, (iy1 - iy0) / s);
    const long validPx[4] = {ix0 - x0, iy0 - y0, ix1 - x0, iy1 - y0};

    [_lastPyramid waitUntilCompleted];
    [self ensureStorageWidth:width height:height device:renderer.device];

    const CFTimeInterval t0 = CACurrentMediaTime();
    if (![self captureRect:captured valid:validPx of:source width:width height:height pxPerPt:s]) return NO;
    [self recordCapture:CACurrentMediaTime() - t0];

    _pixelsPerPoint = s;
    _capturedRect = captured;
    _validRect = valid;
    [self encodePyramidFor:source renderer:renderer];
    _generation += 1;
    _dirty = NO;
    return YES;
}

- (void)encodePyramidFor:(UIView *)source renderer:(GLSRenderer *)renderer {
    const CGFloat s = _pixelsPerPoint;
    const CGRect captured = _capturedRect;
    id<MTLCommandBuffer> commandBuffer = [renderer.queue commandBuffer];
    if (_underlayTexture) {
        float base[4] = {0, 0, 0, 1};
        CGFloat r = 0, g = 0, b = 0, a = 1;
        UIColor *color = [[self resolvedBaseColorFor:source] resolvedColorWithTraitCollection:source.traitCollection];
        if ([color getRed:&r green:&g blue:&b alpha:&a]) base[0] = float(r), base[1] = float(g), base[2] = float(b);
        const CGRect under = CGRectOffset(_underlayRect, -captured.origin.x, -captured.origin.y);
        [renderer encodePyramid:_texture fromLinear:_linear underlay:_underlayTexture underlayRect:under page:_pageTexture
                       pageRect:CGRectOffset(_pageRect, -captured.origin.x, -captured.origin.y) pxPerPt:s base:base
                  commandBuffer:commandBuffer];
    } else if (_veil.on) {
        const float params[12] = {float(captured.origin.y), float(s), float(_veil.top), float(_veil.bottom),
                                  float(_veil.y0), float(_veil.y1), float(_veil.sigma), 0,
                                  _veil.color[0], _veil.color[1], _veil.color[2], _veil.color[3]};
        [renderer encodePyramid:_texture fromLinear:_linear veil:params commandBuffer:commandBuffer];
    } else {
        [renderer encodePyramid:_texture fromLinear:_linear commandBuffer:commandBuffer];
    }
    [commandBuffer commit];
    _lastPyramid = commandBuffer;
    _encodedVeil = _veil;
}

// Render-server-only layers such as CABackdropLayer and CAPortalLayer turn -renderInContext: black or grey.
static void HideServerOnlyLayers(CALayer *layer, NSMutableArray<CALayer *> *hidden) {
    static Class backdrop = NSClassFromString(@"CABackdropLayer"), portal = NSClassFromString(@"CAPortalLayer");
    for (CALayer *sub in layer.sublayers) {
        if (sub.hidden) continue;
        if ((backdrop && [sub isKindOfClass:backdrop]) || (portal && [sub isKindOfClass:portal])) {
            sub.hidden = YES;
            [hidden addObject:sub];
        } else {
            HideServerOnlyLayers(sub, hidden);
        }
    }
}

- (BOOL)captureRect:(CGRect)rect valid:(const long *)valid of:(UIView *)source width:(size_t)width height:(size_t)height
            pxPerPt:(CGFloat)pxPerPt {
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef ctx = CGBitmapContextCreate([self bitmapMemory], width, height, 8, _bytesPerRow, space,
                                             kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
    CGColorSpaceRelease(space);
    if (!ctx) return NO;
    const CGRect validCG = CGRectMake(valid[0], height - valid[3], valid[2] - valid[0], valid[3] - valid[1]);
    CGContextClipToRect(ctx, validCG);
    if (_underlayTexture) {
        CGContextClearRect(ctx, validCG);
    } else {
        UIColor *base = [self resolvedBaseColorFor:source];
        CGContextSetFillColorWithColor(ctx, [base resolvedColorWithTraitCollection:source.traitCollection].CGColor);
        CGContextFillRect(ctx, validCG);
    }
    CGContextTranslateCTM(ctx, 0, height);
    CGContextScaleCTM(ctx, pxPerPt, -pxPerPt);
    CGContextTranslateCTM(ctx, -rect.origin.x, -rect.origin.y);

    NSMutableArray<UIView *> *hidden = [NSMutableArray array];
    for (UIView *view in GlassViews()) {
        if (!view.layer.hidden && [view isDescendantOfView:source]) {
            view.layer.hidden = YES;
            [hidden addObject:view];
        }
    }
    NSMutableArray<CALayer *> *serverOnly = [NSMutableArray array];
    HideServerOnlyLayers(source.layer, serverOnly);
    [source.layer renderInContext:ctx];
    for (CALayer *layer in serverOnly) layer.hidden = NO;
    for (UIView *view in hidden) view.layer.hidden = NO;
    CGContextRelease(ctx);
    [self repeatEdgesOutside:valid width:width height:height];
#if TARGET_OS_SIMULATOR
    [_linear replaceRegion:MTLRegionMake2D(0, 0, width, height) mipmapLevel:0 withBytes:_cpuBitmap.mutableBytes
               bytesPerRow:_bytesPerRow];
#endif

    return YES;
}

// The real backdrop is the opaque composited screen, so a transparent source is drawn over this colour.
- (UIColor *)resolvedBaseColorFor:(UIView *)source {
    UIColor *base = _baseColor;
    for (UIView *v = source; !base && v; v = v.superview) {
        CGFloat r, g, b, a = 0;
        UIColor *bg = v.backgroundColor;
        if (bg && [[bg resolvedColorWithTraitCollection:source.traitCollection] getRed:&r green:&g blue:&b alpha:&a] && a >= 1)
            base = bg;
    }
    if (!base) base = source.window.backgroundColor;
    CGFloat r, g, b, alpha = 0;
    if (!base || ![[base resolvedColorWithTraitCollection:source.traitCollection] getRed:&r green:&g blue:&b alpha:&alpha] ||
        alpha < 1)
        base = UIColor.blackColor;
    return base;
}

// Fills the pixels outside the valid box [x0, y0, x1, y1) with the nearest valid pixel.
- (void)repeatEdgesOutside:(const long *)valid width:(size_t)width height:(size_t)height {
    uint8_t *bytes = (uint8_t *)[self bitmapMemory];
    const long x0 = valid[0], y0 = valid[1], x1 = valid[2], y1 = valid[3];
    if (x0 > 0 || x1 < long(width)) {
        for (long y = y0; y < y1; ++y) {
            uint32_t *row = (uint32_t *)(bytes + y * _bytesPerRow);
            std::fill(row, row + x0, row[x0]);
            std::fill(row + x1, row + width, row[x1 - 1]);
        }
    }
    for (long y = 0; y < y0; ++y) memcpy(bytes + y * _bytesPerRow, bytes + y0 * _bytesPerRow, width * 4);
    for (long y = y1; y < long(height); ++y) memcpy(bytes + y * _bytesPerRow, bytes + (y1 - 1) * _bytesPerRow, width * 4);
}

- (void)recordCapture:(CFTimeInterval)seconds {
    if (!gLogsStats) return;
    const CFTimeInterval now = CACurrentMediaTime();
    if (_statsStart == 0) _statsStart = now;
    _captureTime += seconds;
    _captures += 1;
    if (now - _statsStart >= 1.0) {
        NSString *line = [NSString stringWithFormat:@"backdrop %.0fx%.0f: %lu/s, %.2f ms", _linear.width * 1.0,
                                                    _linear.height * 1.0, (unsigned long)_captures,
                                                    _captureTime * 1000.0 / _captures];
        NSLog(@"[glassify] %@", line);
        [NSNotificationCenter.defaultCenter postNotificationName:@"GLSStatsLine"
                                                          object:[NSString stringWithFormat:@"%p", self]
                                                        userInfo:@{@"line" : line}];
        _statsStart = now;
        _captureTime = 0;
        _captures = 0;
    }
}

- (float)meanLumaInRect:(CGRect)rect {
    const uint8_t *bytes = (const uint8_t *)[self bitmapMemory];
    if (!bytes || !_linear || _pixelsPerPoint <= 0) return -1.f;
    const CGFloat s = _pixelsPerPoint;
    rect = CGRectOffset(rect, -_capturedRect.origin.x, -_capturedRect.origin.y);
    const long x0 = std::max<long>(0, long(std::floor(rect.origin.x * s)));
    const long y0 = std::max<long>(0, long(std::floor(rect.origin.y * s)));
    const long x1 = std::min<long>(long(_linear.width), long(std::ceil(CGRectGetMaxX(rect) * s)));
    const long y1 = std::min<long>(long(_linear.height), long(std::ceil(CGRectGetMaxY(rect) * s)));
    const long stepX = std::max<long>(1, (x1 - x0) / 64), stepY = std::max<long>(1, (y1 - y0) / 64);
    double sum = 0;
    long count = 0;
    for (long y = y0; y < y1; y += stepY) {
        const uint8_t *row = bytes + y * _bytesPerRow;
        for (long x = x0; x < x1; x += stepX) {
            const uint8_t *px = row + x * 4;
            const float a = px[3] / 255.f;
            if (a <= 0) continue;
            sum += (0.2126f * px[2] + 0.7152f * px[1] + 0.0722f * px[0]) / (255.f * a);
            ++count;
        }
    }
    return count ? float(sum / count) : -1.f;
}

- (float)lumaInRect:(CGRect)rect hiding:(UIView *)hiddenView {
    UIView *source = _source;
    if (!source || rect.size.width <= 0 || rect.size.height <= 0) return -1.f;
    constexpr CGFloat s = 0.25;
    const size_t width = std::max<size_t>(1, size_t(std::ceil(rect.size.width * s)));
    const size_t height = std::max<size_t>(1, size_t(std::ceil(rect.size.height * s)));
    std::vector<uint32_t> pixels(width * height);
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef ctx = CGBitmapContextCreate(pixels.data(), width, height, 8, width * 4, space,
                                             kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
    CGColorSpaceRelease(space);
    if (!ctx) return -1.f;
    UIColor *base = [self resolvedBaseColorFor:source];
    CGContextSetFillColorWithColor(ctx, [base resolvedColorWithTraitCollection:source.traitCollection].CGColor);
    CGContextFillRect(ctx, CGRectMake(0, 0, width, height));
    CGContextTranslateCTM(ctx, 0, height);
    CGContextScaleCTM(ctx, s, -s);
    CGContextTranslateCTM(ctx, -rect.origin.x, -rect.origin.y);
    NSMutableArray<UIView *> *hidden = [NSMutableArray array];
    for (UIView *view in [GlassViews().allObjects arrayByAddingObject:hiddenView]) {
        if (!view.layer.hidden && [view isDescendantOfView:source]) {
            view.layer.hidden = YES;
            [hidden addObject:view];
        }
    }
    [source.layer renderInContext:ctx];
    for (UIView *view in hidden) view.layer.hidden = NO;
    CGContextRelease(ctx);
    double sum = 0;
    for (uint32_t p : pixels) {
        sum += 0.2126 * ((p >> 16) & 0xff) + 0.7152 * ((p >> 8) & 0xff) + 0.0722 * (p & 0xff);
    }
    return float(sum / (255.0 * pixels.size()));
}

- (void *)bitmapMemory {
#if TARGET_OS_SIMULATOR
    return _cpuBitmap.mutableBytes;
#else
    return _buffer.contents;
#endif
}

- (void)ensureStorageWidth:(size_t)width height:(size_t)height device:(id<MTLDevice>)device {
    if (_linear && _linear.width == width && _linear.height == height) return;

    const MTLPixelFormat format = MTLPixelFormatBGRA8Unorm;
    const NSUInteger alignment = [device minimumLinearTextureAlignmentForPixelFormat:format];
    _bytesPerRow = ((width * 4 + alignment - 1) / alignment) * alignment;
    MTLTextureDescriptor *linear = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:format
                                                                                      width:width
                                                                                     height:height
                                                                                  mipmapped:NO];
    linear.storageMode = MTLStorageModeShared;
    linear.usage = MTLTextureUsageShaderRead;
#if TARGET_OS_SIMULATOR
    _cpuBitmap = [NSMutableData dataWithLength:_bytesPerRow * height];
    _linear = [device newTextureWithDescriptor:linear];
#else
    _buffer = [device newBufferWithLength:_bytesPerRow * height options:MTLResourceStorageModeShared];
    _linear = [_buffer newTextureWithDescriptor:linear offset:0 bytesPerRow:_bytesPerRow];
#endif

    MTLTextureDescriptor *pyramid = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:format
                                                                                       width:width
                                                                                      height:height
                                                                                   mipmapped:YES];
    pyramid.mipmapLevelCount = std::min<NSUInteger>(pyramid.mipmapLevelCount, 8);
    pyramid.storageMode = MTLStorageModePrivate;
    pyramid.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite | MTLTextureUsagePixelFormatView;
    _texture = [device newTextureWithDescriptor:pyramid];
}

@end

@implementation GLSDebug
+ (BOOL)logsStats { return GLSBackdrop.logsStats; }
+ (void)setLogsStats:(BOOL)logsStats { GLSBackdrop.logsStats = logsStats; }
@end
