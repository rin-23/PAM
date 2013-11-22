//
//  WireFrame.m
//  Ossa
//
//  Created by Rinat Abdrashitov on 2013-10-15.
//  Copyright (c) 2013 Rinat Abdrashitov. All rights reserved.
//

#import "WireFrame.h"

@implementation WireFrame

-(void)setVertexData:(NSMutableData*)vertexData vertexNum:(int)vertexNum {
    
    NSString* vShader = [[NSBundle mainBundle] pathForResource:@"PointCloudRGBAShader" ofType:@"vsh"];
    NSString* fShader = [[NSBundle mainBundle] pathForResource:@"PointCloudRGBAShader" ofType:@"fsh"];
    self.drawShaderProgram = [[ShaderProgram  alloc] initWithVertexShader:vShader fragmentShader:fShader];
    
    attrib[ATTRIB_POSITION] = [self.drawShaderProgram attributeLocation:"position"];
    attrib[ATTRIB_COLOR] = [self.drawShaderProgram attributeLocation:"color"];
    
    uniforms[UNIFORM_MODELVIEWPROJECTION_MATRIX] = [self.drawShaderProgram uniformLocation:"modelViewProjectionMatrix"];
    uniforms[UNIFORM_POINT_SIZE] = [self.drawShaderProgram uniformLocation:"u_PointSize"];
    
    self.numVertices = vertexNum;
    
    self.vertexDataBuffer = [[AGLKVertexAttribArrayBuffer alloc] initWithAttribStride:sizeof(VertexNormRGBA)
                                                                     numberOfVertices:self.numVertices
                                                                                bytes:vertexData.bytes
                                                                                usage:GL_STATIC_DRAW];
    glEnableVertexAttribArray(attrib[ATTRIB_POSITION]);
    glEnableVertexAttribArray(attrib[ATTRIB_COLOR]);
}

-(void)draw {
    glUseProgram(self.drawShaderProgram.program);
    
    glUniformMatrix4fv(uniforms[UNIFORM_MODELVIEWPROJECTION_MATRIX], 1, 0, self.modelViewProjectionMatrix.m);
    glUniform1f(uniforms[UNIFORM_POINT_SIZE], 5.0f);
    
    [self.vertexDataBuffer bind];
    [self.vertexDataBuffer prepareToDrawWithAttrib:attrib[ATTRIB_POSITION]
                               numberOfCoordinates:3
                                      attribOffset:0
                                          dataType:GL_FLOAT
                                         normalize:GL_FALSE];
    
    [self.vertexDataBuffer prepareToDrawWithAttrib:attrib[ATTRIB_COLOR]
                               numberOfCoordinates:4
                                      attribOffset:2*sizeof(PositionXYZ)
                                          dataType:GL_UNSIGNED_BYTE
                                         normalize:GL_TRUE];
    
    [AGLKVertexAttribArrayBuffer drawPreparedArraysWithMode:GL_LINES
                                           startVertexIndex:0
                                           numberOfVertices:self.numVertices];

}

@end
