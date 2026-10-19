//
//  GLSScrollEdgeEffectViewInternal.h
//  Glassify
//
//  Copyright © 2026 Hung Phan.
//  See LICENSE file for license information.
//

#import "GLSBackdrop.h"
#import "Glassify/GLSScrollEdgeEffectView.h"

@interface GLSScrollEdgeEffectView (Internal)
// `on` is NO when the effect cannot be converted into `source`'s bounds space.
- (GLSBackdropVeil)gls_veilInView:(UIView *)source;
// Takes the effect's colour from the first opaque background at or above `view`, as UIKit follows its scroll view's background.
- (void)gls_matchBackgroundOf:(UIView *)view;
@end
