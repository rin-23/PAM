//
//  PolarAnnularMesh.h
//  PAM
//
//  Created by Rinat Abdrashitov on 11/21/2013.
//  Copyright (c) 2013 Rinat Abdrashitov. All rights reserved.
//

#import "Mesh.h"
#include <vector>

@interface PolarAnnularMesh : Mesh

-(void)setMeshFromObjFile:(NSString*)objFile;

#pragma mark - TOUCHES: BRANCH/BUMPS CREATION ONE FINGER
-(void)startCreateBranch:(GLKVector3)touchPoint closestPoint:(GLKVector3)closestPoint;
-(void)continueCreateBranch:(GLKVector3)touchPoint;
-(void)endCreateBranchBended:(GLKVector3)touchPoint
                touchedModel:(BOOL)touchedModel
                   touchSize:(float)touchSize
           averageTouchSpeed:(float)touchSpeed;
-(std::vector<std::vector<GLKVector3>>)end3DCreateBranchBended:(GLKVector3)touchPoint
                    touchedModel:(BOOL)touchedModel
                     touchSize:(float)touchSize
             averageTouchSpeed:(float)touchSpeed;

#pragma mark - TOUCHES: BRANCH CREATION TWO FINGERS
-(void)startCreateBranchFinger1:(GLKVector3)touchPoint1 finger2:(GLKVector3)touchPoint2;
-(void)continueCreateBranchFinger1:(GLKVector3)touchPoint1 finger2:(GLKVector3)touchPoint2;
-(std::vector<std::vector<GLKVector3>>)endCreateBranchTwoFingersWithTouchedModel:(BOOL)touchedModel;

#pragma mark - TOUCHES: FACE PICKING
-(void)endSelectFaceWithRay:(GLKVector3)rayOrigin rayDirection:(GLKVector3)rayDir;

#pragma mark - TOUCHES: SINGLE RING SCALING
-(void)startScalingSingleRibWithTouchPoint1:(GLKVector3)touchPoint1
                                touchPoint2:(GLKVector3)touchPoint2
                                      scale:(float)scale
                                   velocity:(float)velocity;
-(void)changeScalingSingleRibWithScaleFactor:(float)scale;
-(void)endScalingSingleRibWithScaleFactor:(float)scale;

#pragma mark - TOUCHES: MULTIPLE RING SCALING
-(void)startScalingRibsWithRayOrigin1:(GLKVector3)rayOrigin1
                           rayOrigin2:(GLKVector3)rayOrigin2
                        rayDirection1:(GLKVector3)rayDir1
                        rayDirection2:(GLKVector3)rayDir2
                                scale:(float)scale;
-(void)changeScalingRibsWithScaleFactor:(float)scale;
-(void)endScalingRibsWithScaleFactor:(float)scale;

#pragma mark - Common bending methods
-(void)createPinPoint:(GLKVector3)touchPoint;
-(void)createPivotPoint:(GLKVector3)touchPoint;

#pragma mark - ROTATING THE BRANCH TREE
-(void)startBendingWithTouhcPoint:(GLKVector3)touchPoint angle:(float)angle;
-(void)continueBendingWithWithAngle:(float)angle;
-(void)endBendingWithAngle:(float)angle;

#pragma mark - SCALING THE BRANCH TREE
-(void)startScalingBranchTreeWithTouchPoint:(GLKVector3)touchPoint scale:(float)scale;
-(void)continueScalingBranchTreeWithScale:(float)scale;
-(void)endScalingBranchTreeWithScale:(float)scale;

#pragma mark - TRANSLATION OF THE BRANCH TREE
-(void)startTranslatingBranchTreeWithTouchPoint:(GLKVector3)touchPoint
                                    translation:(GLKVector3)translation;
-(void)continueTranslatingBranchTree:(GLKVector3)translation;
-(void)endTranslatingBranchTree:(GLKVector3)translation;

#pragma mark - SMOOTHING
-(void)smoothAtPoint:(GLKVector3)touchPoint;

#pragma mark - UTILITIES
-(void)clear;
-(void)undo;
-(void)showSkeleton:(BOOL)show;
-(void)showRibJunctions;
-(BOOL)manifoldIsLoaded;
@end
