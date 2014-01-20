//
//  PolarAnnularMesh.h
//  PAM
//
//  Created by Rinat Abdrashitov on 11/21/2013.
//  Copyright (c) 2013 Rinat Abdrashitov. All rights reserved.
//

#import "Mesh.h"


typedef enum {
    MODIFICATION_NONE,
    MODIFICATION_SCULPTING_SCALING,
    MODIFICATION_SCULPTING_ANISOTROPIC_SCALING,
    MODIFICATION_SCULPTING_BUMP_CREATION,
    MODIFICATION_PIN_POINT_SET,
    MODIFICATION_BRANCH_ROTATION,
    MODIFICATION_BRANCH_SCALING,
    MODIFICATION_BRANCH_TRANSLATION,
    MODIFICATION_BRANCH_DETACHED,
    MODIFICATION_BRANCH_DETACHED_AN_MOVED,
    MODIFICATION_BRANCH_DETACHED_ROTATE,
    MODIFICATION_BRANCH_COPIED_BRANCH_FOR_CLONING,
    MODIFICATION_BRANCH_COPIED_AND_MOVED_THE_CLONE,
    MODIFICATION_BRANCH_CLONE_ROTATION
} CurrentModification;

@protocol PolarAnnularMeshDelegate <NSObject>

-(void)modStateChangedTo:(CurrentModification)modState;
-(void)displayHint:(NSString*)hintString;

@end

@interface PolarAnnularMesh : Mesh

@property (nonatomic, assign) CurrentModification modState;
@property (nonatomic, weak) id<PolarAnnularMeshDelegate> delegate;

#pragma mark - Loading Form OBJ files
/*
 * Load 3d party obj file
 */
-(void)setMeshFromObjFile:(NSString*)objFilePath;

/*
 * Restore session with previously saved obj file
 */
-(void)restoreMeshFromObjFile:(NSString*)objFilePath;

#pragma mark - BRANCH/BUMPS CREATION ONE FINGER
-(void)startCreateBranch:(GLKVector3)touchPoint closestPoint:(GLKVector3)closestPoint;
-(void)continueCreateBranch:(GLKVector3)touchPoint;
-(void)endCreateBranchBended:(GLKVector3)touchPoint
                                 touchedModelStart:(BOOL)touchedModel
                                   touchedModelEnd:(BOOL)touchedModelEnd
                                       shouldStick:(BOOL)shouldStick
                                         touchSize:(float)touchSize
                                 averageTouchSpeed:(float)touchSpeed;

-(void)startBumpCreationAtPoint:(GLKVector3)touchPoint
                      brushSize:(float)brushSize
                     brushDepth:(float)brushDepth;

-(void)continueBumpCreationWithBrushDepth:(float)brushDepth;
-(void)endBumpCreation;

#pragma mark - BODY CREATION TWO FINGERS
-(void)startCreateBodyFinger1:(GLKVector3)touchPoint1 finger2:(GLKVector3)touchPoint2;
-(void)continueCreateBodyFinger1:(GLKVector3)touchPoint1 finger2:(GLKVector3)touchPoint2;
-(void)endCreateBody;

#pragma mark - TOUCHES: FACE PICKING
-(void)endSelectFaceWithRay:(GLKVector3)rayOrigin rayDirection:(GLKVector3)rayDir;

#pragma mark - TOUCHES: SINGLE RING SCALING
-(void)startScalingSingleRibWithTouchPoint:(GLKVector3)touchPoint
                      secondPointOnTheModel:(BOOL)secondPointOnTheModel
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

/*
 * Rotating detached branch araound base norm axis
 */
-(BOOL)startRotateDetachedBranch:(float)angle;
-(void)continueRotateDetachedBranch:(float)angle;
-(void)endRotateDetachedBranch:(float)angle;

#pragma mark - CLONING
-(BOOL)copyBranchToBuffer:(GLKVector3)touchPoint;
-(BOOL)cloneBranchTo:(GLKVector3)touchPoint;
-(BOOL)attachClonedBranch;
-(void)dismissCopiedBranch;
-(BOOL)startRotateClonedBranch:(float)angle;
-(void)continueRotateClonedBranch:(float)angle;
-(void)endRotateClonedBranch:(float)angle;

#pragma mark - UTILITIES
-(void)clear;
-(void)undo;
-(void)showSkeleton:(BOOL)show;
-(void)showRibJunctions;
-(BOOL)isLoaded;
-(void)subdivide;
-(BOOL)saveAsObj:(NSString*)filePath;
-(BOOL)backup:(NSString*)path;
-(void)clearMemmory;
@end
