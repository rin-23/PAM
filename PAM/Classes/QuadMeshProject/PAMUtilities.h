//
//  PAMUtilities.h
//  PAM
//
//  Created by Rinat Abdrashitov on 2013-11-27.
//  Copyright (c) 2013 Rinat Abdrashitov. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <GLKit/GLKMath.h>
#include <vector>

@interface PAMUtilities : NSObject


+(void)centroids:(std::vector<GLKVector2>&)centroids ribWidth:(std::vector<float>&)ribWidth
                                       forTwoFingerTouchPoint:(std::vector<GLKVector2>)touchPointsWorld
                                         withNextCentroidStep:(double)step;

+(void)centroids:(std::vector<GLKVector2>&)centroids forOneFingerTouchPoint:(std::vector<GLKVector2>)touchPointsWorld
                                                       withNextCentroidStep:(double)step;

+(void)normals:(std::vector<GLKVector2>&)normals
      tangents:(std::vector<GLKVector2>&)tangents
   forSkeleton:(std::vector<GLKVector2>)skeleton;

//+(std::vector<float>)ribWidthForSkeleton:(std::vector<GLKVector2>)skeleton
//                                 normals:(std::vector<GLKVector2>)normals
//                                tangents:(std::vector<GLKVector2>)tangents
//                             touchPoints:(std::vector<GLKVector2>)touchPoints;

+(std::vector<GLKVector2>)laplacianSmoothing:(std::vector<GLKVector2>)points
                                  iterations:(int)iterations;


@end
