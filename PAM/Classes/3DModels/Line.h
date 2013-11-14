//
//  Line.h
//  Ossa
//
//  Created by Rinat Abdrashitov on 2013-08-15.
//  Copyright (c) 2013 Rinat Abdrashitov. All rights reserved.
//

#import "Mesh.h"

@interface Line : Mesh

-(id)initWithVertexData:(NSMutableData*)vertexData;
-(void)addVertex:(GLKVector3)vertex;
-(void)reBuffer:(NSMutableData*)vertexData;

@property (nonatomic, assign) GLenum lineDrawingMode;

@end
