//
//  Line.m
//  Ossa
//
//  Created by Rinat Abdrashitov on 2013-08-15.
//  Copyright (c) 2013 Rinat Abdrashitov. All rights reserved.
//

#import "Line.h"

@implementation Line

-(id)initWithVertexData:(NSMutableData*)vertexData {
    self = [super init];
    if (self) {
        
        self.lineDrawingMode = GL_LINE_STRIP;
        
        NSString* vShaderPath = [[NSBundle mainBundle] pathForResource:@"PointCloudRGBAShader" ofType:@"vsh"];
        NSString* fShaderPath = [[NSBundle mainBundle] pathForResource:@"PointCloudRGBAShader" ofType:@"fsh"];
        self.drawShaderProgram = [[ShaderProgram alloc] initWithVertexShader:vShaderPath fragmentShader:fShaderPath];

        attrib[ATTRIB_COLOR] = [self.drawShaderProgram attributeLocation:"color"];
        attrib[ATTRIB_POSITION] = [self.drawShaderProgram attributeLocation:"position"];
        
        uniforms[UNIFORM_MODELVIEWPROJECTION_MATRIX] = [self.drawShaderProgram uniformLocation:"modelViewProjectionMatrix"];
        uniforms[UNIFORM_POINT_SIZE] = [self.drawShaderProgram uniformLocation:"u_PointSize"];
        
        self.meshData = vertexData;
        self.numVertices = vertexData.length / sizeof(VertexRGBA);
        
        self.vertexDataBuffer = [[AGLKVertexAttribArrayBuffer alloc] initWithAttribStride:sizeof(VertexRGBA)
                                                                         numberOfVertices:self.numVertices
                                                                                    bytes:self.meshData.bytes
                                                                                    usage:GL_DYNAMIC_DRAW];
        [self.vertexDataBuffer enableAttribute:attrib[ATTRIB_COLOR]];
        [self.vertexDataBuffer enableAttribute:attrib[ATTRIB_POSITION]];

    }
    return self;
}

-(void)reBuffer:(NSMutableData*) vertexData{
    self.meshData = vertexData;
    self.numVertices = vertexData.length / sizeof(VertexRGBA);
    
    self.vertexDataBuffer = [[AGLKVertexAttribArrayBuffer alloc] initWithAttribStride:sizeof(VertexRGBA)
                                                                     numberOfVertices:self.numVertices
                                                                                bytes:self.meshData.bytes
                                                                                usage:GL_DYNAMIC_DRAW];
    [self.vertexDataBuffer enableAttribute:attrib[ATTRIB_COLOR]];
    [self.vertexDataBuffer enableAttribute:attrib[ATTRIB_POSITION]];
}

-(void)addVertex:(GLKVector3)vertex {
    
}

-(void)draw {
    if (self.drawShaderProgram != nil) {
        glUseProgram(self.drawShaderProgram.program);
       
        glUniformMatrix4fv(uniforms[UNIFORM_MODELVIEWPROJECTION_MATRIX], 1, 0, self.modelViewProjectionMatrix.m);
        glUniform1f(uniforms[UNIFORM_POINT_SIZE], 2.0f);
        
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
        
        [AGLKVertexAttribArrayBuffer drawPreparedArraysWithMode:self.lineDrawingMode
                                               startVertexIndex:0
                                               numberOfVertices:self.numVertices];

    }
}

@end
