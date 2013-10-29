//
//  PointCloud.m
//  Ossa
//
//  Created by Rinat Abdrashitov on 2013-10-14.
//  Copyright (c) 2013 Rinat Abdrashitov. All rights reserved.
//

#import "PointCloudMesh.h"
#import "PlateStartPoint.h"


@implementation PointCloudMesh

-(id)init {
    self = [super init];
    if (self) {
        _pointSize = 1.0f;
    }
    return self;
}

#pragma mark - Point Cloud
-(void)setPointCloudData:(NSMutableData *)meshData numVerticies:(unsigned long)vertexNum colorSpace:(CGColorSpaceModel)colorSpace {
    self.meshData = meshData;
    self.numVertices = vertexNum;
    self.colorSpace = colorSpace;
    size_t stride;
    
    //Set up display shader
    ShaderProgramType programType = (colorSpace == kCGColorSpaceModelMonochrome) ? ShaderProgramTypeBoneMonochrome : ShaderProgramTypeBoneRGBA;
    self.drawShaderProgram = [[ShadersManager sharedInstance] shaderProgramWithType:programType];
    
    attrib[ATTRIB_COLOR] = [self.drawShaderProgram attributeLocation:"color"];
    glEnableVertexAttribArray(attrib[ATTRIB_COLOR]);
    attrib[ATTRIB_POSITION] = [self.drawShaderProgram attributeLocation:"position"];
    glEnableVertexAttribArray(attrib[ATTRIB_POSITION]);
    uniforms[UNIFORM_MODELVIEWPROJECTION_MATRIX] = [self.drawShaderProgram uniformLocation:"modelViewProjectionMatrix"];
    uniforms[UNIFORM_POINT_SIZE] = [self.drawShaderProgram uniformLocation:"u_PointSize"];
    
    if (colorSpace == kCGColorSpaceModelMonochrome) {
        stride = sizeof(VertexMonochrome);
    } else {
        stride = sizeof(VertexRGBA);
        //Get current color
        VertexRGBA* vertices = (VertexRGBA*) self.meshData.bytes;
        VertexRGBA firstVertex = vertices[0];
        self.color = GLKVector4Make(firstVertex.color.r, firstVertex.color.g, firstVertex.color.b, firstVertex.color.a);
    }
    
    self.vertexDataBuffer = [[AGLKVertexAttribArrayBuffer alloc] initWithAttribStride:stride
                                                                     numberOfVertices:self.numVertices
                                                                                bytes:self.meshData.bytes
                                                                                usage:GL_STATIC_DRAW];
}

-(void)appendPointCloudData:(NSMutableData*)additionalMeshData numVerticies:(int)vertexNum {
    
    [self.meshData appendData:additionalMeshData];
    self.numVertices += vertexNum;
    
    size_t stride;
    if (self.colorSpace == kCGColorSpaceModelMonochrome) {
        stride = sizeof(VertexMonochrome);
    } else {
        stride = sizeof(VertexRGBA);
    }
    self.vertexDataBuffer = [[AGLKVertexAttribArrayBuffer alloc] initWithAttribStride:stride
                                                                     numberOfVertices:self.numVertices
                                                                                bytes:self.meshData.bytes
                                                                                usage:GL_STATIC_DRAW];
}


#pragma mark - Drawing
-(void)draw {
    glUseProgram(self.drawShaderProgram.program);
    glUniformMatrix4fv(uniforms[UNIFORM_MODELVIEWPROJECTION_MATRIX], 1, 0, self.modelViewProjectionMatrix.m);
    glUniform1f(uniforms[UNIFORM_POINT_SIZE], self.pointSize);
    
    [self.vertexDataBuffer prepareToDrawWithAttrib:attrib[ATTRIB_POSITION]
                               numberOfCoordinates:3
                                      attribOffset:0
                                          dataType:GL_FLOAT
                                         normalize:GL_FALSE];    
    
    int numOfCoord = self.colorSpace == kCGColorSpaceModelMonochrome ? 1 : 4;
    
    [self.vertexDataBuffer prepareToDrawWithAttrib:attrib[ATTRIB_COLOR]
                               numberOfCoordinates:numOfCoord
                                      attribOffset:sizeof(PositionXYZ)
                                          dataType:GL_UNSIGNED_BYTE
                                         normalize:GL_TRUE];
    
    
    [AGLKVertexAttribArrayBuffer drawPreparedArraysWithMode:GL_POINTS
                                           startVertexIndex:0
                                           numberOfVertices:self.numVertices];
}

-(void)drawToDepthBuffer {    
    if (self.depthShaderProgram == nil) {
        self.depthShaderProgram = [[ShadersManager sharedInstance] shaderProgramWithType:ShaderProgramTypeBoneDepth];
        attribDepth[ATTRIB_POSITION] = [self.depthShaderProgram attributeLocation:"position"];
        glEnableVertexAttribArray(attribDepth[ATTRIB_POSITION]);
        uniformsDepth[UNIFORM_MODELVIEWPROJECTION_MATRIX] = [self.depthShaderProgram uniformLocation:"modelViewProjectionMatrix"];
    }
    
    glUseProgram(self.depthShaderProgram.program);
    glUniformMatrix4fv(uniformsDepth[UNIFORM_MODELVIEWPROJECTION_MATRIX], 1, 0, self.modelViewProjectionMatrix.m);
    
    [self.vertexDataBuffer prepareToDrawWithAttrib:attribDepth[ATTRIB_POSITION]
                               numberOfCoordinates:3
                                      attribOffset:0
                                          dataType:GL_FLOAT
                                         normalize:GL_FALSE];
    
    [AGLKVertexAttribArrayBuffer drawPreparedArraysWithMode:GL_POINTS
                                           startVertexIndex:0
                                           numberOfVertices:self.numVertices];
}


-(void)drawWithPointSize:(float)aPointSize {
    float curPointSize = self.pointSize;
    self.pointSize = aPointSize;
    
    [self draw];
    
    self.pointSize = curPointSize;
}

-(void)drawWithLargePointsSize {
    [self drawWithPointSize:10.0f];
}

@end
