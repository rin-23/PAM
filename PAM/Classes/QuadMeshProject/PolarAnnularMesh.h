//
//  PolarAnnularMesh.h
//  PAM
//
//  Created by Rinat Abdrashitov on 11/21/2013.
//  Copyright (c) 2013 Rinat Abdrashitov. All rights reserved.
//

#import "Mesh.h"

@interface PolarAnnularMesh : Mesh

@property (nonatomic, assign) int branchWidth;

-(void)setMeshFromObjFile:(NSString*)objFile;

#pragma mark - TOUCHES: BRANCH CREATION
-(void)startCreateBranch:(GLKVector3)touchPoint;
-(void)endCreateBranch:(GLKVector3)touchPoint touchedModel:(BOOL)touchedModel;

#pragma mark - TOUCHES: FACE PICKING
-(void)endSelectFaceWithRay:(GLKVector3)rayOrigin rayDirection:(GLKVector3)rayDir;

#pragma mark - TOUHCES: SCALING
-(void)startScalingRibsWithRayOrigin1:(GLKVector3)rayOrigin1
                           rayOrigin2:(GLKVector3)rayOrigin2
                        rayDirection1:(GLKVector3)rayDir1
                        rayDirection2:(GLKVector3)rayDir2
                                scale:(float)scale;
-(void)changeScalingRibsWithScaleFactor:(float)scale;
-(void)endScalingRibsWithScaleFactor:(float)scale;

@end
