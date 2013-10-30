//
//  QuadPolygonMesh.m
//  Ossa
//
//  Created by Rinat Abdrashitov on 2013-10-15.
//  Copyright (c) 2013 Rinat Abdrashitov. All rights reserved.
//

#import "QuadPolygonMesh.h"
#import "polygonize.h"
#import "MetaBalls.h"
#import "Implicit.h"
#import "triangulate.h"
#import "Manifold.h"
#import "../HMesh/obj_load.h"
#import <GLKit/GLKit.h>
#import "WireFrame.h"
#import "Utilities.h"

@interface QuadPolygonMesh() {
    HMesh::Manifold _manifold;
    WireFrame* _wireFrame;
    HMesh::VertexID _curSelectedVertexID;
    BoundingBox _boundingBox;
}

@property (nonatomic) AGLKVertexAttribArrayBuffer* wireframeVertexBuffer;
@end

@implementation QuadPolygonMesh

using namespace HMesh;

-(void)setMeshFromObjFile:(NSString*)objFilePath {
    //Load manifold
    _manifold = HMesh::Manifold();
    HMesh::obj_load(objFilePath.UTF8String, _manifold);
    
    //Calculate Bounding Box
    Manifold::Vec pmin = Manifold::Vec();
    Manifold::Vec pmax = Manifold::Vec();
    HMesh::bbox(_manifold, pmin, pmax);
    
    self.centerAtBoundingBox = YES;
    _boundingBox.minBound = GLKVector3Make(pmin[0], pmin[1], pmin[2]);
    _boundingBox.maxBound = GLKVector3Make(pmax[0], pmax[1], pmax[2]);
    _boundingBox.center = GLKVector3MultiplyScalar(GLKVector3Add(_boundingBox.minBound, _boundingBox.maxBound), 0.5f);
    
    GLKVector3 mid = GLKVector3MultiplyScalar(GLKVector3Subtract(_boundingBox.maxBound, _boundingBox.minBound), 0.5f);
    _boundingBox.radius = GLKVector3Length(mid);
    _boundingBox.width = fabsf(_boundingBox.maxBound.x - _boundingBox.minBound.x);
    _boundingBox.height = fabsf(_boundingBox.maxBound.y - _boundingBox.minBound.y);
    _boundingBox.depth = fabsf(_boundingBox.maxBound.z - _boundingBox.minBound.z);
    
    //Load shader
    NSString* vShader = [[NSBundle mainBundle] pathForResource:@"DirectionalLight" ofType:@"vsh"];
    NSString* fShader = [[NSBundle mainBundle] pathForResource:@"DirectionalLight" ofType:@"fsh"];
    self.drawShaderProgram = [[ShaderProgram alloc] initWithVertexShader:vShader fragmentShader:fShader];
    
    attrib[ATTRIB_POSITION] = [self.drawShaderProgram attributeLocation:"position"];
    attrib[ATTRIB_NORMAL] = [self.drawShaderProgram attributeLocation:"normal"];
    attrib[ATTRIB_COLOR] = [self.drawShaderProgram attributeLocation:"color"];
    
    uniforms[UNIFORM_MODELVIEWPROJECTION_MATRIX] = [self.drawShaderProgram uniformLocation:"matrix"];
    uniforms[UNIFORM_LIGHT_DIRECTION] = [self.drawShaderProgram uniformLocation:"lightDirection"];
    uniforms[UNIFORM_LIGHT_COLOR] = [self.drawShaderProgram uniformLocation:"lightDiffuseColor"];

    //Load data
    NSMutableData* vertexData = [[NSMutableData alloc] init];
    NSMutableData* wireframeData = [[NSMutableData alloc] init];
    [self triangulateManifold:_manifold trianglMeshData:&vertexData wireframeData:&wireframeData];

    self.numVertices = vertexData.length / sizeof(VertexNormRGBA);
    
    self.vertexDataBuffer = [[AGLKVertexAttribArrayBuffer alloc] initWithAttribStride:sizeof(VertexNormRGBA)
                                                                     numberOfVertices:self.numVertices
                                                                                bytes:vertexData.bytes
                                                                                usage:GL_DYNAMIC_DRAW];
    [self.vertexDataBuffer enableAttribute:attrib[ATTRIB_POSITION]];
    [self.vertexDataBuffer enableAttribute:attrib[ATTRIB_NORMAL]];
    [self.vertexDataBuffer enableAttribute:attrib[ATTRIB_COLOR]];
    
    
    //Create Wireframe Object
    _wireFrame = [[WireFrame alloc]  init];
    _wireFrame.centerAtBoundingBox = YES;
    _wireFrame.boundingBox = _boundingBox;
    [_wireFrame setVertexData:wireframeData vertexNum:wireframeData.length/sizeof(VertexNormRGBA)];
}


//-(void)setVertexData:(NSMutableData*)vertexData numOfVerticies:(uint32_t)vertexNum {
//    
//    NSString* vShader = [[NSBundle mainBundle] pathForResource:@"DirectionalLight" ofType:@"vsh"];
//    NSString* fShader = [[NSBundle mainBundle] pathForResource:@"DirectionalLight" ofType:@"fsh"];
//    self.drawShaderProgram = [[ShaderProgram alloc] initWithVertexShader:vShader fragmentShader:fShader];
//    
//    attrib[ATTRIB_POSITION] = [self.drawShaderProgram attributeLocation:"position"];
//    attrib[ATTRIB_NORMAL] = [self.drawShaderProgram attributeLocation:"normal"];
//    attrib[ATTRIB_COLOR] = [self.drawShaderProgram attributeLocation:"color"];
//    
//    uniforms[UNIFORM_MODELVIEWPROJECTION_MATRIX] = [self.drawShaderProgram uniformLocation:"matrix"];
//    uniforms[UNIFORM_LIGHT_DIRECTION] = [self.drawShaderProgram uniformLocation:"lightDirection"];
//    uniforms[UNIFORM_LIGHT_COLOR] = [self.drawShaderProgram uniformLocation:"lightDiffuseColor"];
//    
//    self.numVertices = vertexData.length / sizeof(VertexNormRGBA);
//    
//    self.vertexDataBuffer = [[AGLKVertexAttribArrayBuffer alloc] initWithAttribStride:sizeof(VertexNormRGBA)
//                                                                     numberOfVertices:self.numVertices
//                                                                                bytes:vertexData.bytes
//                                                                                usage:GL_DYNAMIC_DRAW];
//    [self.vertexDataBuffer enableAttribute:attrib[ATTRIB_POSITION]];
//    [self.vertexDataBuffer enableAttribute:attrib[ATTRIB_NORMAL]];
//    [self.vertexDataBuffer enableAttribute:attrib[ATTRIB_COLOR]];
//}

-(GLKVector3)closestVertexToMeshPoint:(GLKVector3)touchPoint {
    //iterate over every face
    float distance = FLT_MAX;
    HMesh::VertexID closestVertex;

    touchPoint = [Utilities invertVector3:touchPoint withMatrix:self.modelMatrix];
    
    for(FaceIDIterator fid = _manifold.faces_begin(); fid != _manifold.faces_end(); ++fid) {
        //iterate over every vertex of the face
        for (Walker w = _manifold.walker(*fid); !w.full_circle(); w = w.circulate_face_ccw()) {
            CGLA::Vec3d vertexPos = _manifold.pos(w.vertex());
            GLKVector3 glkVertextPos = GLKVector3Make(vertexPos[0], vertexPos[1], vertexPos[2]);
            float cur_distance = GLKVector3Distance(touchPoint, glkVertextPos);
            if (cur_distance < distance) {
                distance = cur_distance;
                closestVertex = w.vertex();
            }
        }
    }
    
    _curSelectedVertexID = closestVertex;
    CGLA::Vec3d vertexPos = _manifold.pos(_curSelectedVertexID);
    GLKVector4 glkVertextPos = GLKVector4Make(vertexPos[0], vertexPos[1], vertexPos[2], 1.0);
    glkVertextPos = GLKMatrix4MultiplyVector4(self.modelMatrix, glkVertextPos);
    return  GLKVector3Make(glkVertextPos.x, glkVertextPos.y, glkVertextPos.z);
}

-(BOOL)touchedCloseToTheCurrentVertex:(GLKVector3)touchPoint {
    touchPoint = [Utilities invertVector3:touchPoint withMatrix:self.modelMatrix];
    float threshold = _boundingBox.radius * 0.1;
    
    CGLA::Vec3d vertexPos = _manifold.pos(_curSelectedVertexID);
    GLKVector3 glkPos = GLKVector3Make(vertexPos[0], vertexPos[1], vertexPos[2]);
    
    GLKVector4 currentPosition4 = GLKMatrix4MultiplyVector4(self.modelViewMatrix, GLKVector4MakeWithVector3(glkPos, 1.0));
    GLKVector4 newPosition4 = GLKMatrix4MultiplyVector4(self.modelViewMatrix, GLKVector4MakeWithVector3(touchPoint, 1.0));
    
    float d = GLKVector2Distance(GLKVector2Make(currentPosition4.x, currentPosition4.y), GLKVector2Make(newPosition4.x, newPosition4.y));
    if (d <= threshold) {
        return YES;
    }
    return NO;
}

-(void)translateCurrentSelectedVertex:(GLKVector3)newPosition {
    
    newPosition = [Utilities invertVector3:newPosition withMatrix:self.modelMatrix];
    
    CGLA::Vec3d vertexPos = _manifold.pos(_curSelectedVertexID);
    GLKVector3 currePosition = GLKVector3Make(vertexPos[0], vertexPos[1], vertexPos[2]);
    
    GLKVector4 currentPosition4 = GLKMatrix4MultiplyVector4(self.modelViewMatrix, GLKVector4MakeWithVector3(currePosition, 1.0));
    GLKVector4 newPosition4 = GLKMatrix4MultiplyVector4(self.modelViewMatrix, GLKVector4MakeWithVector3(newPosition, 1.0));
    GLKVector3 point3 = GLKVector3Make(newPosition4.x, newPosition4.y, currentPosition4.z);
    
    bool isInvertible;
    GLKVector4 axis = GLKMatrix4MultiplyVector4(GLKMatrix4Invert(self.modelViewMatrix, &isInvertible), GLKVector4MakeWithVector3(point3, 1.0));
    
    
    GLKVector3 vk = GLKVector3Make(axis.x, axis.y, axis.z);

    CGLA::Vec3d newPos = CGLA::Vec3d(vk.x, vk.y, vk.z);
    _manifold.setPos(_curSelectedVertexID, newPos);
    NSMutableData* vertexData = [[NSMutableData alloc] init];
    NSMutableData* wireframeData = [[NSMutableData alloc] init];
    [self triangulateManifold:_manifold trianglMeshData:&vertexData wireframeData:&wireframeData];

    self.numVertices = vertexData.length / sizeof(VertexNormRGBA);

    self.vertexDataBuffer = [[AGLKVertexAttribArrayBuffer alloc] initWithAttribStride:sizeof(VertexNormRGBA)
                                                                     numberOfVertices:self.numVertices
                                                                                bytes:vertexData.bytes
                                                                                usage:GL_DYNAMIC_DRAW];

    glEnableVertexAttribArray(attrib[ATTRIB_POSITION]);
    glEnableVertexAttribArray(attrib[ATTRIB_NORMAL]);
    glEnableVertexAttribArray(attrib[ATTRIB_COLOR]);


    [_wireFrame setVertexData:wireframeData vertexNum:wireframeData.length/sizeof(VertexNormRGBA)];
}

//Triangulate manifold for display in case it has quads. GLES doesnt handle quads.
-(void)triangulateManifold:(const HMesh::Manifold&)mani
           trianglMeshData:(NSMutableData**)verticies
             wireframeData:(NSMutableData**)wireframe
{
    
    if (*verticies == nil) {
        *verticies = [[NSMutableData alloc] init];
    }
    
    if (*wireframe == nil) {
        *wireframe = [[NSMutableData alloc] init];
    }
    
    //iterate over every face
    for(FaceIDIterator fid = mani.faces_begin(); fid != mani.faces_end(); ++fid) {
        int vertexNum = 0;
        VertexNormRGBA firstVertex;
        VertexNormRGBA secondVertex;
        VertexNormRGBA thirdVertex;
        VertexNormRGBA fourthVertex;

        CGLA::Vec3d norm = HMesh::normal(mani, *fid);
        PositionXYZ normGL = {(GLfloat)norm[0], (GLfloat)norm[1], (GLfloat)norm[2]};
        
        ColorRGBA vertexColor = {200,200,200,255};
        
        //iterate over every vertex of the face
        for(Walker w = mani.walker(*fid); !w.full_circle(); w = w.circulate_face_ccw()) {
            
            //add vertex to the data array
            CGLA::Vec3d c = mani.pos(w.vertex());
            PositionXYZ positionDCM = {(GLfloat)c[0], (GLfloat)c[1], (GLfloat)c[2]};
            VertexNormRGBA vertexMono = {positionDCM, normGL, vertexColor};

            vertexNum++;
            
            //Create a second triangle
            switch (vertexNum) {
                case 1:
                    firstVertex = vertexMono;
                    break;
                case 2:
                    secondVertex = vertexMono;
                    break;
                case 3:
                    thirdVertex = vertexMono;
                    break;
                case 4:
                    //Create a second triangle from quad
                    [*verticies appendBytes:&firstVertex length:sizeof(VertexNormRGBA)];
                    [*verticies appendBytes:&thirdVertex length:sizeof(VertexNormRGBA)];
                    fourthVertex = vertexMono;
                    break;
                default:
                    break;
            }
            
            [*verticies appendBytes:&vertexMono length:sizeof(VertexNormRGBA)];
        }
        
        //add wireframe data
        ColorRGBA wireframeColor = {200,0,0,255};
        if (vertexNum == 3 || vertexNum == 4) {
            firstVertex.color = wireframeColor;
            secondVertex.color = wireframeColor;
            thirdVertex.color = wireframeColor;
            
            [*wireframe appendBytes:&firstVertex length:sizeof(VertexNormRGBA)];
            [*wireframe appendBytes:&secondVertex length:sizeof(VertexNormRGBA)];
            [*wireframe appendBytes:&secondVertex length:sizeof(VertexNormRGBA)];
            [*wireframe appendBytes:&thirdVertex length:sizeof(VertexNormRGBA)];
            if (vertexNum == 3) {
                [*wireframe appendBytes:&thirdVertex length:sizeof(VertexNormRGBA)];
                [*wireframe appendBytes:&firstVertex length:sizeof(VertexNormRGBA)];
            } else if (vertexNum == 4) {
                fourthVertex.color = wireframeColor;
                [*wireframe appendBytes:&thirdVertex length:sizeof(VertexNormRGBA)];
                [*wireframe appendBytes:&fourthVertex length:sizeof(VertexNormRGBA)];
                [*wireframe appendBytes:&fourthVertex length:sizeof(VertexNormRGBA)];
                [*wireframe appendBytes:&firstVertex length:sizeof(VertexNormRGBA)];
            }
        }
    }
}

-(BoundingBox)boundingBox {
    return _boundingBox;
}

-(void)draw {
    glUseProgram(self.drawShaderProgram.program);
    
    glUniformMatrix4fv(uniforms[UNIFORM_MODELVIEWPROJECTION_MATRIX], 1, 0, self.modelViewProjectionMatrix.m);
    glUniform4f(uniforms[UNIFORM_LIGHT_DIRECTION], 0.0, 0.0, 0.0, 1.0);
    glUniform4f(uniforms[UNIFORM_LIGHT_COLOR], 1.0, 1.0, 1.0, 1.0);
    
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
    
    [self.vertexDataBuffer prepareToDrawWithAttrib:attrib[ATTRIB_COLOR]
                               numberOfCoordinates:4
                                      attribOffset:2*sizeof(PositionXYZ)
                                          dataType:GL_UNSIGNED_BYTE
                                         normalize:GL_TRUE];

    
    [AGLKVertexAttribArrayBuffer drawPreparedArraysWithMode:GL_TRIANGLES
                                           startVertexIndex:0
                                           numberOfVertices:self.numVertices];

    _wireFrame.rotationManager.rotationMatrix = self.rotationManager.rotationMatrix;
    _wireFrame.translationManager.translationMatrix = self.translationManager.translationMatrix;
    _wireFrame.viewMatrix = self.viewMatrix;
    _wireFrame.projectionMatrix = self.projectionMatrix;
    
    [_wireFrame draw];
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
    
    [self.vertexDataBuffer prepareToDrawWithAttrib:attribDepth[ATTRIB_POSITION]
                               numberOfCoordinates:3
                                      attribOffset:0
                                          dataType:GL_FLOAT
                                         normalize:GL_FALSE];
    
    [AGLKVertexAttribArrayBuffer drawPreparedArraysWithMode:GL_TRIANGLES
                                           startVertexIndex:0
                                           numberOfVertices:self.numVertices];
}


@end
