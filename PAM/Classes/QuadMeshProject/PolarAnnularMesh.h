//
//  PolarAnnularMesh.h
//  PAM
//
//  Created by Rinat Abdrashitov on 11/21/2013.
//  Copyright (c) 2013 Rinat Abdrashitov. All rights reserved.
//

#import "Mesh.h"

@interface PolarAnnularMesh : Mesh

-(void)setMeshFromObjFile:(NSString*)objFile;

-(void)startCreateBranch:(GLKVector3)touchPoint;
-(void)endCreateBranch:(GLKVector3)touchPoint touchedModel:(BOOL)touchedModel;

@property (nonatomic, assign) int branchWidth;

@end
