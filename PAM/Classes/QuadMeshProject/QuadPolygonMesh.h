//
//  QuadPolygonMesh.h
//  Ossa
//
//  Created by Rinat Abdrashitov on 2013-10-15.
//  Copyright (c) 2013 Rinat Abdrashitov. All rights reserved.
//

#import "PolygonMesh.h"

@interface QuadPolygonMesh : PolygonMesh

-(void)setMeshFromObjFile:(NSString*)objFile;

//-(GLKVector3)closestVertexToMeshPoint:(GLKVector3)touchPoint setAsCurrentID:(BOOL)setAsCurrentID;
//-(GLKVector3)translateCurrentSelectedVertex:(GLKVector3)newPosition;
//-(BOOL)touchedCloseToTheCurrentVertex:(GLKVector3)touchPoint;

-(void)rebuffer;

-(void)gaussianStart:(GLKVector3)touchPoint;
-(void)gaussianMove:(GLKVector3)touchPoint;

-(BOOL)createBranchAtPointAndRefine:(GLKVector3)touchPoint;

-(void)showSkeleton:(BOOL)show;
-(void)moveVertexOrthogonallyCloseTo:(GLKVector3)touchPoint;

-(void)createNewRibAtPoint:(GLKVector3)touchPoint;
-(void)createNewSpineAtPoint:(GLKVector3)touchPoint;

-(void)undo;

-(void)branchCreateMovementStart:(GLKVector3)touchPoint;
-(void)branchCreateMovementEnd:(GLKVector3)touchPoint;

-(BOOL)bendBranchBeginWithFirstTouchRayOrigin:(GLKVector3)rayOrigin
                                 rayDirection:(GLKVector3)rayDirection
                             secondTouchPoint:(GLKVector3)touchPoint;
-(void)bendBranchEnd:(GLKVector3)touchPoint;

-(void)beginScalingRibsWithRayOrigin1:(GLKVector3)rayOrigin1
                           rayOrigin2:(GLKVector3)rayOrigin2
                        rayDirection1:(GLKVector3)rayDir1
                        rayDirection2:(GLKVector3)rayDir2;
-(void)endScalingRibsWithScaleFactor:(float)scale;
-(void)changeScalingRibsWithScaleFactor:(float)scale;

@property (nonatomic, assign) int branchWidth;

@end