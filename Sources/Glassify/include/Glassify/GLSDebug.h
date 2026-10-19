//
//  GLSDebug.h
//  Glassify
//
//  Copyright © 2026 Hung Phan.
//  See LICENSE file for license information.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Debug switches for demos and measurements.
@interface GLSDebug : NSObject
/// A Boolean value that determines whether backdrop capture and frame timings are logged once per second.
@property (class, nonatomic) BOOL logsStats;
@end

NS_ASSUME_NONNULL_END
