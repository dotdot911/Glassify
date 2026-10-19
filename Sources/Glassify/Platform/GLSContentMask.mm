//
//  GLSContentMask.mm
//  Glassify
//
//  Copyright © 2026 Hung Phan.
//  See LICENSE file for license information.
//

#import "GLSContentMask.h"

#include <cmath>
#include <vector>

@implementation GLSContentMask {
    std::vector<double> _signature;
    id<MTLTexture> _texture;
    std::vector<uint8_t> _pixels;
}

static CALayer *Shown(CALayer *layer) { return layer.presentationLayer ?: layer; }

// Goes through every transform, the press lift included.
static CGAffineTransform ToHost(CALayer *layer, CALayer *host) {
    const CGPoint a = [layer convertPoint:CGPointZero toLayer:host];
    const CGPoint x = [layer convertPoint:CGPointMake(1, 0) toLayer:host];
    const CGPoint y = [layer convertPoint:CGPointMake(0, 1) toLayer:host];
    return CGAffineTransformMake(x.x - a.x, x.y - a.y, y.x - a.x, y.y - a.y, a.x, a.y);
}

// A mask layer is outside the layer tree, so it has no transform to its owner.
static CGAffineTransform MaskToOwner(CALayer *mask) {
    const CGRect f = mask.frame, b = mask.bounds;
    return CGAffineTransformMakeTranslation(f.origin.x - b.origin.x, f.origin.y - b.origin.y);
}

// What decides the mask: each layer's placement in the host, size, opacity, visibility and contents.
static void Sign(CALayer *layer, CALayer *host, std::vector<double> &out) {
    const CGAffineTransform t = ToHost(layer, host);
    const CGRect b = layer.bounds;
    out.insert(out.end(), {t.a, t.b, t.c, t.d, t.tx, t.ty, b.origin.x, b.origin.y, b.size.width, b.size.height,
                           layer.opacity, double(layer.hidden), double(uintptr_t((__bridge void *)layer.contents))});
    for (CALayer *s in layer.sublayers) Sign(s, host, out);
}

static void SignMask(CALayer *layer, std::vector<double> &out) {
    const CGRect f = layer.frame;
    out.insert(out.end(), {f.origin.x, f.origin.y, f.size.width, f.size.height, layer.opacity, double(layer.hidden),
                           double(uintptr_t((__bridge void *)layer.contents))});
    if ([layer isKindOfClass:[CAShapeLayer class]]) {
        CGPathRef path = ((CAShapeLayer *)layer).path;
        const CGRect box = path ? CGPathGetBoundingBox(path) : CGRectNull;
        out.insert(out.end(), {double(uintptr_t(path)), box.origin.x, box.origin.y, box.size.width, box.size.height});
    }
    for (CALayer *s in layer.sublayers) SignMask(s, out);
}

static CALayer *AppliedMask(UIView *view) {
    CALayer *mask = Shown(view.layer).mask;
    return mask && ![mask.name isEqualToString:GLSContentMaskHiddenName] ? mask : nil;
}

- (id<MTLTexture>)maskForViews:(NSArray<UIView *> *)views
                     hostLayer:(CALayer *)hostLayer
                          rect:(CGRect)rect
                         scale:(CGFloat)scale
                        device:(id<MTLDevice>)device {
    CALayer *host = Shown(hostLayer);
    std::vector<double> signature = {rect.origin.x, rect.origin.y, rect.size.width, rect.size.height, scale};
    struct Group {
        std::vector<CALayer *> layers;
        CALayer *owner, *mask;
    };
    std::vector<Group> groups;
    for (UIView *view in views) {
        Group group{{}, Shown(view.layer), AppliedMask(view)};
        for (CALayer *sub in view.layer.sublayers) {
            CALayer *shown = Shown(sub);
            if (shown.hidden || shown.opacity <= 0) continue;
            group.layers.push_back(shown);
            Sign(shown, host, signature);
        }
        if (group.layers.empty()) continue;
        if (group.mask) {
            const CGAffineTransform t = ToHost(group.owner, host);
            signature.insert(signature.end(), {t.a, t.b, t.c, t.d, t.tx, t.ty});
            SignMask(group.mask, signature);
        }
        groups.push_back(group);
    }
    if (groups.empty()) return nil;
    if (_texture && signature == _signature) return _texture;
    _signature = signature;

    const size_t width = size_t(std::ceil(rect.size.width * scale)), height = size_t(std::ceil(rect.size.height * scale));
    if (width == 0 || height == 0) return nil;
    _pixels.assign(width * height, 0);
    CGContextRef ctx = CGBitmapContextCreate(_pixels.data(), width, height, 8, width, nullptr, kCGImageAlphaOnly);
    if (!ctx) return nil;
    const CGAffineTransform base = CGAffineTransformTranslate(CGAffineTransformMake(scale, 0, 0, -scale, 0, height),
                                                              -rect.origin.x, -rect.origin.y);
    for (const Group &group : groups) {
        std::vector<uint8_t> maskPixels;
        CGContextSaveGState(ctx);
        if (group.mask) {
            maskPixels.assign(width * height, 0);
            CGContextRef mctx = CGBitmapContextCreate(maskPixels.data(), width, height, 8, width, nullptr, kCGImageAlphaOnly);
            if (mctx) {
                CGContextConcatCTM(mctx, CGAffineTransformConcat(CGAffineTransformConcat(MaskToOwner(group.mask),
                                                                                         ToHost(group.owner, host)),
                                                                 base));
                [group.mask renderInContext:mctx];
                CGContextRelease(mctx);
            }
            CGColorSpaceRef gray = CGColorSpaceCreateDeviceGray();
            CGDataProviderRef provider = CGDataProviderCreateWithData(nullptr, maskPixels.data(), maskPixels.size(), nullptr);
            CGImageRef image = CGImageCreate(width, height, 8, 8, width, gray, kCGImageAlphaNone, provider, nullptr, false,
                                             kCGRenderingIntentDefault);
            CGContextClipToMask(ctx, CGRectMake(0, 0, width, height), image);
            CGImageRelease(image);
            CGDataProviderRelease(provider);
            CGColorSpaceRelease(gray);
        }
        for (CALayer *layer : group.layers) {
            CGContextSaveGState(ctx);
            CGContextConcatCTM(ctx, CGAffineTransformConcat(ToHost(layer, host), base));
            [layer renderInContext:ctx];
            CGContextRestoreGState(ctx);
        }
        CGContextRestoreGState(ctx);
    }
    CGContextRelease(ctx);

    {
        MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatA8Unorm
                                                                                      width:width
                                                                                     height:height
                                                                                  mipmapped:NO];
        td.usage = MTLTextureUsageShaderRead;
        _texture = [device newTextureWithDescriptor:td];
    }
    [_texture replaceRegion:MTLRegionMake2D(0, 0, width, height) mipmapLevel:0 withBytes:_pixels.data() bytesPerRow:width];
    return _texture;
}

@end
