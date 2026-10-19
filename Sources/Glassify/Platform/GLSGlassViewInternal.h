//
//  GLSGlassViewInternal.h
//  Glassify
//
//  Copyright © 2026 Hung Phan.
//  See LICENSE file for license information.
//

#pragma once

#import "Glassify/GLSGlassView.h"
#import "GLSGlassSurface.h"

// The view a control's glass snapshots by default: the nearest ancestor with an opaque background, else the window.
UIKIT_EXTERN UIView *GLSDefaultBackdropSource(UIView *view);

@interface GLSGlassView (Internal)
- (GLSGlassSurface *)gls_surface;
// The container's surface when the glass is grouped.
- (GLSGlassSurface *)gls_renderingSurface;
// Views drawn through their own mask with `matrix` (rows of the light and dark schemes) over the glass.
- (void)gls_setTintedVibrantViews:(NSArray<UIView *> *)views matrix:(const float (*)[3][4])matrix;
// A capsule in the view's bounds cut out of the vibrant content and shown in the tinted set, at `opacity`.
- (void)gls_setVibrantHole:(CGRect)hole tintedOpacity:(CGFloat)opacity;
- (void)gls_fillTintedVibrancy:(GLSSurfaceRequest &)request inLayer:(nullable CALayer *)target;
@end
