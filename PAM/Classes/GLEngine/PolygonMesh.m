//
//  PolygonMesh.m
//  Ossa
//
//  Created by Rinat Abdrashitov on 2013-10-14.
//  Copyright (c) 2013 Rinat Abdrashitov. All rights reserved.
//

#import "PolygonMesh.h"


@implementation PolygonMesh

#pragma mark - Surface Mesh Data

-(void)setMeshDataWithNorm:(NSMutableData *)meshData {
    
    self.meshData = meshData;
    self.numVertices = meshData.length/sizeof(VertexNormRGBA);

    NSString* vShader = [[NSBundle mainBundle] pathForResource:@"DirectionalLight" ofType:@"vsh"];
    NSString* fShader = [[NSBundle mainBundle] pathForResource:@"DirectionalLight" ofType:@"fsh"];
    
    self.drawShaderProgram = [[ShaderProgram alloc] initWithVertexShader:vShader fragmentShader:fShader];

    attrib[ATTRIB_POSITION] = [self.drawShaderProgram attributeLocation:"position"];
    attrib[ATTRIB_NORMAL] = [self.drawShaderProgram attributeLocation:"normal"];
    
    uniforms[UNIFORM_MODELVIEWPROJECTION_MATRIX] = [self.drawShaderProgram uniformLocation:"matrix"];
    uniforms[UNIFORM_LIGHT_DIRECTION] = [self.drawShaderProgram uniformLocation:"lightDirection"];
    uniforms[UNIFORM_LIGHT_COLOR] = [self.drawShaderProgram uniformLocation:"lightDiffuseColor"];
    
    self.vertexDataBuffer = [[AGLKVertexAttribArrayBuffer alloc] initWithAttribStride:sizeof(VertexNormRGBA)
                                                                     numberOfVertices:self.numVertices
                                                                                bytes:self.meshData.bytes
                                                                                usage:GL_STATIC_DRAW];
    glEnableVertexAttribArray(attrib[ATTRIB_POSITION]);
    glEnableVertexAttribArray(attrib[ATTRIB_NORMAL]);
}

-(void)draw {
    
    glUseProgram(self.drawShaderProgram.program);
    
    glUniformMatrix4fv(uniforms[UNIFORM_MODELVIEWPROJECTION_MATRIX], 1, 0, self.modelViewProjectionMatrix.m);
    glUniform4f(uniforms[UNIFORM_LIGHT_DIRECTION], 1.0, 0.75, 0.25, 1.0);
    glUniform4f(uniforms[UNIFORM_LIGHT_COLOR], 0.8, 0.8, 1.0, 1.0);
    
    [self.vertexDataBuffer bind];
    
    [self.vertexDataBuffer prepareToDrawWithAttrib:attrib[ATTRIB_POSITION]
                               numberOfCoordinates:3
                                      attribOffset:0
                                          dataType:GL_FLOAT
                                         normalize:GL_FALSE];
    
    [self.vertexDataBuffer prepareToDrawWithAttrib:attrib[ATTRIB_NORMAL]
                               numberOfCoordinates:3
                                      attribOffset:sizeof(PositionXYZ)
                                          dataType:GL_FLOAT
                                         normalize:GL_FALSE];
    
    [AGLKVertexAttribArrayBuffer drawPreparedArraysWithMode:GL_TRIANGLES
                                           startVertexIndex:0
                                           numberOfVertices:self.numVertices];
}

-(void)drawToDepthBuffer {
    if (self.depthShaderProgram == nil) {
        NSString* vShader = [[NSBundle mainBundle] pathForResource:@"DepthShader" ofType:@"vsh"];
        NSString* fShader = [[NSBundle mainBundle] pathForResource:@"DepthShader" ofType:@"fsh"];
        
        self.depthShaderProgram = [[ShaderProgram alloc] initWithVertexShader:vShader fragmentShader:fShader];
        attribDepth[ATTRIB_POSITION] = [self.depthShaderProgram attributeLocation:"position"];
        glEnableVertexAttribArray(attribDepth[ATTRIB_POSITION]);
        uniformsDepth[UNIFORM_MODELVIEWPROJECTION_MATRIX] = [self.depthShaderProgram uniformLocation:"modelViewProjectionMatrix"];
    }
    
    glUseProgram(self.depthShaderProgram.program);
    glUniformMatrix4fv(uniformsDepth[UNIFORM_MODELVIEWPROJECTION_MATRIX], 1, 0, self.modelViewProjectionMatrix.m);
    
    [self.vertexDataBuffer bind];
    [self.vertexDataBuffer prepareToDrawWithAttrib:attribDepth[ATTRIB_POSITION]
                               numberOfCoordinates:3
                                      attribOffset:0
                                          dataType:GL_FLOAT
                                         normalize:GL_FALSE];
    
    [AGLKVertexAttribArrayBuffer drawPreparedArraysWithMode:GL_POINTS
                                           startVertexIndex:0
                                           numberOfVertices:self.numVertices];
}



@end
