//
//  PlateStartPoint.m
//  Ossa
//
//  Created by Rinat Abdrashitov on 2013-08-22.
//  Copyright (c) 2013 Rinat Abdrashitov. All rights reserved.
//

#import "PlateStartPoint.h"

@implementation PlateStartPoint

-(id)initWithPoint:(GLKVector3)point color:(GLKVector3)color {
    self = [super init];
    if (self) {
        self.point = point;
        NSString* vShader = [[NSBundle mainBundle] pathForResource:@"PointCloudRGBAShader" ofType:@"vsh"];
        NSString* fShader = [[NSBundle mainBundle] pathForResource:@"PointCloudRGBAShader" ofType:@"fsh"];
        self.drawShaderProgram = [[ShaderProgram alloc] initWithVertexShader:vShader fragmentShader:fShader];
        
        attrib[ATTRIB_POSITION] = [self.drawShaderProgram attributeLocation:"position"];
        attrib[ATTRIB_COLOR] = [self.drawShaderProgram attributeLocation:"color"];
        uniforms[UNIFORM_MODELVIEWPROJECTION_MATRIX] = [self.drawShaderProgram uniformLocation:"modelViewProjectionMatrix"];
        uniforms[UNIFORM_POINT_SIZE] = [self.drawShaderProgram uniformLocation:"u_PointSize"];

        VertexRGBA vertex = {{point.x,point.y,point.z}, {color.r, color.g, color.b, 255}};
        self.meshData = [NSMutableData dataWithBytes:&vertex length:sizeof(VertexRGBA)];
        self.numVertices = 1;
        
        self.vertexDataBuffer = [[AGLKVertexAttribArrayBuffer alloc] initWithAttribStride:sizeof(VertexRGBA)
                                                                           numberOfVertices:self.numVertices
                                                                                      bytes:self.meshData.bytes
                                                                                      usage:GL_STATIC_DRAW];
        [self.vertexDataBuffer enableAttribute:attrib[ATTRIB_POSITION]];
        [self.vertexDataBuffer enableAttribute:attrib[ATTRIB_COLOR]];
    }
    return self;
}

-(void)draw {
    
    glUseProgram(self.drawShaderProgram.program);
    
    glUniformMatrix4fv(uniforms[UNIFORM_MODELVIEWPROJECTION_MATRIX], 1, 0, self.modelViewProjectionMatrix.m);
    glUniform1f(uniforms[UNIFORM_POINT_SIZE], 10.0f);
    
    [self.vertexDataBuffer bind];
    [self.vertexDataBuffer prepareToDrawWithAttrib:attrib[ATTRIB_POSITION]
                                       numberOfCoordinates:3
                                              attribOffset:0
                                                  dataType:GL_FLOAT
                                                 normalize:GL_FALSE];

    [self.vertexDataBuffer prepareToDrawWithAttrib:attrib[ATTRIB_COLOR]
                               numberOfCoordinates:4
                                      attribOffset:sizeof(PositionXYZ)
                                          dataType:GL_UNSIGNED_BYTE
                                         normalize:GL_TRUE];

    [AGLKVertexAttribArrayBuffer drawPreparedArraysWithMode:GL_POINTS
                                           startVertexIndex:0
                                           numberOfVertices:self.numVertices];
}

@end
