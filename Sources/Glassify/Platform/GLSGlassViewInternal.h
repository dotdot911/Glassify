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

@interface GLSGlassView (Internal)
- (GLSGlassSurface *)gls_surface;
// The container's surface when the glass is grouped.
- (GLSGlassSurface *)gls_renderingSurface;
@end
