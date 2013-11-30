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
                                                                                    usage:GL_DYNAMIC_DRAW target:GL_ARRAY_BUFFER];
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
                                                                                usage:GL_DYNAMIC_DRAW target:GL_ARRAY_BUFFER];
    [self.vertexDataBuffer enableAttribute:attrib[ATTRIB_COLOR]];
    [self.vertexDataBuffer enableAttribute:attrib[ATTRIB_POSITION]];
}

-(void)addVertex:(GLKVector3)vector3 {
    VertexRGBA vertex = {{vector3.x, vector3.y,vector3.z}, {255,0,0,255}};
    [self.meshData appendBytes:&vertex length:sizeof(VertexRGBA)];
    [self rebuffer];
}

//meshData was changed, so need to rebuffer
-(void)rebuffer {
    self.numVertices = self.meshData.length / sizeof(VertexRGBA);
    self.vertexDataBuffer = [[AGLKVertexAttribArrayBuffer alloc] initWithAttribStride:sizeof(VertexRGBA)
                                                                     numberOfVertices:self.numVertices
                                                                                bytes:self.meshData.bytes
                                                                                usage:GL_DYNAMIC_DRAW
                                                                               target:GL_ARRAY_BUFFER];
    [self.vertexDataBuffer enableAttribute:attrib[ATTRIB_COLOR]];
    [self.vertexDataBuffer enableAttribute:attrib[ATTRIB_POSITION]];
}

-(void)draw {
    if (self.drawShaderProgram != nil) {
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
        
        [AGLKVertexAttribArrayBuffer drawPreparedArraysWithMode:GL_LINE_STRIP
                                               startVertexIndex:0
                                               numberOfVertices:self.numVertices];
        
        [AGLKVertexAttribArrayBuffer drawPreparedArraysWithMode:GL_POINTS
                                               startVertexIndex:0
                                               numberOfVertices:self.numVertices];

    }
}

@end
