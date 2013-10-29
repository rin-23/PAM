//
//  PointCloud.h
//  Ossa
//
//  Created by Rinat Abdrashitov on 2013-10-14.
//  Copyright (c) 2013 Rinat Abdrashitov. All rights reserved.
//

#import "Mesh.h"

@interface PointCloudMesh : Mesh

-(void)setPointCloudData:(NSMutableData *)meshData
            numVerticies:(unsigned long)vertexNum
              colorSpace:(CGColorSpaceModel)colorSpace;

-(void)appendPointCloudData:(NSMutableData *)additionalMeshData
               numVerticies:(int)vertexNum;

@property (nonatomic, assign) float pointSize;
@property (nonatomic, assign) CGColorSpaceModel colorSpace;
@property (nonatomic, assign) GLKVector4 color;

-(void)drawWithPointSize:(float)aPointSize;
-(void)drawWithLargePointsSize;

@end
