//
//  SettingsManager.h
//  PAM
//
//  Created by Rinat Abdrashitov on 12/25/2013.
//  Copyright (c) 2013 Rinat Abdrashitov. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef enum {
    CircularScaling,
    SilhouetteScaling
} ScultpScalingType;

@interface SettingsManager : NSObject

+(SettingsManager*)sharedInstance;

@property (nonatomic, assign) BOOL transform;
@property (nonatomic, assign) BOOL showSkeleton;
@property (nonatomic, assign) float smoothingBrushSize;
@property (nonatomic, assign) float thinBranchWidth;
@property (nonatomic, assign) float mediumBranchWidth;
@property (nonatomic, assign) float largeBranchWidth;
@property (nonatomic, assign) int baseSmoothingIterations;
@property (nonatomic, assign) BOOL spineSmoothing;
@property (nonatomic, assign) BOOL poleSmoothing;
@property (nonatomic, assign) ScultpScalingType sculptScalingType;
@property (nonatomic, assign) float silhouetteScalingBrushSize;
@property (nonatomic, assign) float tapSmoothing;

@end
