//
//  Mesh.h
//  Ossa
//
//  Created by Rinat Abdrashitov on 2013-07-31.
//  Copyright (c) 2013 Rinat Abdrashitov. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <GLKit/GLKMath.h>
#import "ShaderProgram.h"
#import "GLStructures.h"
#import "AGLKVertexAttribArrayBuffer.h"
#import "RotationManager.h"
#import "TranslationManager.h"

enum {
    OSSAPositionMask = 0,
    OSSATextureMask = 1 << 1,
    OSSANormalMask = 1 << 2,
    OSSARGBAColorMask = 1 << 3,
    OSSAMonochromeColorMask  = 1 << 4
};

enum {
    UNIFORM_MODELVIEWPROJECTION_MATRIX,
    UNIFORM_MODELVIEW_MATRIX,
    UNIFORM_MODEL_MATRIX,
    UNIFORM_NORMAL_MATRIX,
    UNIFORM_TEXTURE,
    UNIFORM_LIGHT_POSITION,
    UNIFORM_LIGHT_DIRECTION,
    UNIFORM_LIGHT_COLOR,
    UNIFORM_POINT_SIZE,
    NUM_UNIFORMS
};

enum {
    ATTRIB_COLOR,
    ATTRIB_POSITION,
    ATTRIB_TEXT,
    ATTRIB_NORMAL,
    NUM_ATTRIB
};

typedef struct _BoundingBox {
    GLKVector3 minBound;
    GLKVector3 maxBound;
    GLKVector3 center;

    float radius;
    float width;
    float height;
    float depth;
} BoundingBox;

@interface Mesh : NSObject {
    //Display Shader Variables
    GLint attrib[NUM_ATTRIB];
    GLint uniforms[NUM_UNIFORMS];
    
    //Off Screen Depth Shader Variables
    GLint attribDepth[NUM_ATTRIB];
    GLint uniformsDepth[NUM_UNIFORMS];
    
    @protected
    GLKMatrix4 _modelMatrix;
    GLKMatrix3 _normalMatrix;
}

-(GLKMatrix4)modelViewMatrix;
-(GLKMatrix4)modelViewProjectionMatrix;

-(void)draw;
-(void)drawToDepthBuffer;

@property (nonatomic) ShaderProgram* drawShaderProgram; //shader used for displaying
@property (nonatomic) ShaderProgram* depthShaderProgram; //shader used for getting depth

@property (nonatomic) AGLKVertexAttribArrayBuffer *vertexDataBuffer;
@property (nonatomic) AGLKVertexAttribArrayBuffer *indexDataBuffer;
@property (nonatomic) AGLKVertexAttribArrayBuffer *doubleVertexBuffer;


@property (nonatomic) RotationManager* rotationManager;
@property (nonatomic) TranslationManager* translationManager;
@property (nonatomic, assign) GLKVector3 centroid;

@property (nonatomic) NSMutableData* meshData;
@property (nonatomic) NSMutableData* indexData;
@property (nonatomic, assign) GLsizei numVertices;
@property (nonatomic, assign) GLsizei numIndices;

@property (nonatomic, assign, readonly) GLKMatrix4 modelMatrix;
@property (nonatomic, assign) GLKMatrix4 viewMatrix;
@property (nonatomic, assign) GLKMatrix4 projectionMatrix;
@property (nonatomic, assign, readonly) GLKMatrix3 normalMatrix;
@property (nonatomic, assign) BoundingBox boundingBox;
@property (nonatomic, assign) BOOL centerAtBoundingBox; //default is NO

@end
