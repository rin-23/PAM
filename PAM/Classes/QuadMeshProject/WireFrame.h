//
//  WireFrame.h
//  Ossa
//
//  Created by Rinat Abdrashitov on 2013-10-15.
//  Copyright (c) 2013 Rinat Abdrashitov. All rights reserved.
//

#import "PolygonMesh.h"

@interface WireFrame : PolygonMesh

-(void)setVertexData:(NSMutableData*)vertexData vertexNum:(uint32_t)vertexNum;

@end
