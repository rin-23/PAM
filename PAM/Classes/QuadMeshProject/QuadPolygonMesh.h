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
//-(void)setVertexData:(NSMutableData*)vertexData numOfVerticies:(uint32_t)vertexNum;
-(GLKVector3)closestVertexToMeshPoint:(GLKVector3)touchPoint;
-(GLKVector3)translateCurrentSelectedVertex:(GLKVector3)newPosition;
-(BOOL)touchedCloseToTheCurrentVertex:(GLKVector3)touchPoint;

-(void)createBranchAtPoints:(NSMutableData*)pointData;

@end
