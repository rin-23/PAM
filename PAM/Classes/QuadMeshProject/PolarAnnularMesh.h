//
//  PolarAnnularMesh.h
//  PAM
//
//  Created by Rinat Abdrashitov on 11/21/2013.
//  Copyright (c) 2013 Rinat Abdrashitov. All rights reserved.
//

#import "Mesh.h"
#include <vector>

typedef enum {
    MODIFICATION_NONE,
    MODIFICATION_SCULPTING_SCALING,
    MODIFICATION_PIN_POINT_SET,
    MODIFICATION_BRANCH_ROTATION,
    MODIFICATION_BRANCH_SCALING,
    MODIFICATION_BRANCH_TRANSLATION,
    MODIFICATION_BRANCH_DETACHED,
    MODIFICATION_BRANCH_DETACHED_AN_MOVED
} CurrentModification;

@interface PolarAnnularMesh : Mesh

@property (nonatomic, assign) CurrentModification modState;

-(void)setMeshFromObjFile:(NSString*)objFile;

#pragma mark - BRANCH/BUMPS CREATION ONE FINGER
-(void)startCreateBranch:(GLKVector3)touchPoint closestPoint:(GLKVector3)closestPoint;
-(void)continueCreateBranch:(GLKVector3)touchPoint;
-(std::vector<std::vector<GLKVector3>>)endCreateBranchBended:(GLKVector3)touchPoint
                                                touchedModel:(BOOL)touchedModel
                                                   touchSize:(float)touchSize
                                           averageTouchSpeed:(float)touchSpeed;

#pragma mark - BODY CREATION TWO FINGERS
-(void)startCreateBodyFinger1:(GLKVector3)touchPoint1 finger2:(GLKVector3)touchPoint2;
-(void)continueCreateBodyFinger1:(GLKVector3)touchPoint1 finger2:(GLKVector3)touchPoint2;
-(std::vector<std::vector<GLKVector3>>)endCreateBody;

#pragma mark - TOUCHES: FACE PICKING
-(void)endSelectFaceWithRay:(GLKVector3)rayOrigin rayDirection:(GLKVector3)rayDir;

#pragma mark - TOUCHES: SINGLE RING SCALING
-(void)startScalingSingleRibWithTouchPoint1:(GLKVector3)touchPoint1
                                touchPoint2:(GLKVector3)touchPoint2
                                      scale:(float)scale
                                   velocity:(float)velocity;
-(void)changeScalingSingleRibWithScaleFactor:(float)scale;
-(void)endScalingSingleRibWithScaleFactor:(float)scale;

#pragma mark - Common bending methods
-(void)createPinPoint:(GLKVector3)touchPoint;
-(void)deleteCurrentPinPoint;

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

#pragma mark - DELETING/REPOSITIONING BRANCH
/*
 Detach a branch containing touchPoint. Pin point MUST have been already selected.
 Returns YES if branch was successfully detached.
 */
-(BOOL)detachBranch:(GLKVector3)touchPoint;

/*
 Delete a branch containing touchPoint. Pin point MUST have been already selected.
 Returns YES if branch was successfully deleted.
 */
-(BOOL)deleteBranch:(GLKVector3)touchPoint;

/*
 Move detached branch to a new point.
 Returns YES if branch was successfully moved.
 */
-(BOOL)moveDetachedBranchToPoint:(GLKVector3)touchPoint;

/*
 Attach a branch that is in the detached state. Either attached back to same place it was cutoff or to a new place (in that case it was suppose to have been moved before and new point is set.
 Returns YES if branch was successfully attached.
 */
-(BOOL)attachDetachedBranch;

#pragma mark - UTILITIES
-(void)clear;
-(void)undo;
-(void)showSkeleton:(BOOL)show;
-(void)showRibJunctions;
-(BOOL)isLoaded;
-(BOOL)notCurrentlytModified;
@end
