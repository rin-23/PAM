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

-(GLKVector3)closestVertexToMeshPoint:(GLKVector3)touchPoint setAsCurrentID:(BOOL)setAsCurrentID;
-(GLKVector3)translateCurrentSelectedVertex:(GLKVector3)newPosition;
-(BOOL)touchedCloseToTheCurrentVertex:(GLKVector3)touchPoint;

-(void)rebuffer;
-(void)gaussianStart:(GLKVector3)touchPoint;
-(void)gaussianMove:(GLKVector3)touchPoint;
-(BOOL)createBranchAtPointAndRefine:(GLKVector3)touchPoint;

-(void)showSkeleton:(BOOL)show;
-(void)moveVertexOrthogonallyCloseTo:(GLKVector3)touchPoint;

@property (nonatomic, assign) int branchWidth;
@end
