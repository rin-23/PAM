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
#import "Walker.h"
#include "polarize.h"

@interface QuadPolygonMesh() {
    HMesh::Manifold _manifold;
    WireFrame* _wireFrame;
    HMesh::VertexID _curSelectedVertexID;
    BoundingBox _boundingBox;

    //Gaussian
    HMesh::Manifold old_mani;
    GLKVector3 mousePoint;
    
    //Skeleton
    HMesh::Manifold skeletonMani;
    
    HMesh::VertexAttributeVector<float> weight_vector;
}

@property (nonatomic) AGLKVertexAttribArrayBuffer* wireframeVertexBuffer;
@end

@implementation QuadPolygonMesh

using namespace HMesh;

-(void)setMeshFromObjFile:(NSString*)objFilePath {
    
    _branchWidth = 1;
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

//Create branch at a point near touch point.
-(BOOL)createBranchAtPointAndRefine:(GLKVector3)touchPoint {
    VertexID newPoleID;
    BOOL result = [self createBranchAtPoint:touchPoint width:self.branchWidth vertexID:&newPoleID];
    if (result) {
        HMesh::VertexAttributeVector<int> poles(_manifold.no_vertices(), 0);
        poles[newPoleID] = 1;
        refine_poles(_manifold, poles);
        [self rebuffer];
    }
    
    return result;
}

-(void)createNewSpineAtPoint:(GLKVector3)touchPoint {
    VertexID vID = [self closestVertexID:touchPoint];
    HMesh::HalfEdgeAttributeVector<EdgeInfo> edgeInfo = trace_spine_edges(_manifold);
    Walker walker = _manifold.walker(vID);
    if (edgeInfo[walker.halfedge()].edge_type != RIB) {
        walker = walker.next();
    }
    add_spine(_manifold, walker.halfedge());
    [self rebuffer];
}      


-(void)createNewRibAtPoint:(GLKVector3)touchPoint {
    VertexID vID = [self closestVertexID:touchPoint];
    HMesh::HalfEdgeAttributeVector<EdgeInfo> edgeInfo = trace_spine_edges(_manifold);
    Walker walker = _manifold.walker(vID);
    if (edgeInfo[walker.halfedge()].edge_type != SPINE) {
        walker = walker.next();
    }
    add_rib(_manifold, walker.halfedge());
    [self rebuffer];
}

//Create branch at a point near touch point. Return VertexID of newly created pole. -1 is returned if failed.
-(BOOL)createBranchAtPoint:(GLKVector3)touchPoint width:(int)width vertexID:(VertexID*)newPoleID {
    VertexID vID = [self closestVertexID:touchPoint];
    if (is_pole(_manifold, vID)) {
        NSLog(@"Tried to create a branch at a pole");
        return NO;
    }

    HMesh::HalfEdgeAttributeVector<EdgeInfo> edgeInfo = trace_spine_edges(_manifold);

    Walker walker = _manifold.walker(vID);
    HalfEdgeID endHalfEdge = walker.halfedge();
    
    int num_rib_found = 0;
    VertexAttributeVector<int> vs(_manifold.no_vertices(), 0);
    vs[vID] = 1;
    
    vector<VertexID> ribs(2*width);

    walker = walker.next();//advance one step to pass while loop test
    while (walker.halfedge() != endHalfEdge) {
        while (walker.vertex() != vID) {
            walker = walker.next();
        }
        if (edgeInfo[walker.halfedge()].edge_type == RIB) {
            ribs[num_rib_found++] = walker.opp().vertex();
            int side_width = 1;
            //Advance until we reach desireed width
            Walker sideWalker = walker.opp();
            while (side_width != width) {
                sideWalker = sideWalker.next().opp().next();
                ribs[num_rib_found++] = sideWalker.vertex();
                side_width++;
            }
        }
        if (num_rib_found == 2*width) {
            break;
        }
        walker = walker.opp();
    }
    
    //Set all verticies to be branched out
    for (int i = 0; i < ribs.size(); i++) {
        VertexID cur_vID = ribs[i];
        vs[cur_vID] = 1;
    }
    
    *newPoleID = polar_add_branch(_manifold, vs);
    
    return YES;
    
    
//    Vec3d vec = _manifold.pos(vID);
//    Vec3d r_vec = _manifold.pos(ribs[0]);
//    Vec3d l_vec = _manifold.pos(ribs[1]);
//    
//    GLKVector3 vecGL = [self convertModel:GLKVector3Make(vec[0], vec[1], vec[2])];
//    GLKVector3 r_vecGL = [self convertModel:GLKVector3Make(r_vec[0], r_vec[1], r_vec[2])];
//    GLKVector3 l_vecGL = [self convertModel:GLKVector3Make(l_vec[0], l_vec[1], l_vec[2])];
//    
//    NSMutableData* data = [[NSMutableData alloc] init];
//    [data appendBytes:&vecGL length:sizeof(GLKVector3)];
//    [data appendBytes:&r_vecGL length:sizeof(GLKVector3)];
//    [data appendBytes:&l_vecGL length:sizeof(GLKVector3)];
//
//    
//    NSMutableData* vertexData = [[NSMutableData alloc] init];
//    NSMutableData* wireframeData = [[NSMutableData alloc] init];
//    [self triangulateManifold:_manifold trianglMeshData:&vertexData wireframeData:&wireframeData];
//    
//    self.numVertices = vertexData.length / sizeof(VertexNormRGBA);
//    
//    self.vertexDataBuffer = [[AGLKVertexAttribArrayBuffer alloc] initWithAttribStride:sizeof(VertexNormRGBA)
//                                                                     numberOfVertices:self.numVertices
//                                                                                bytes:vertexData.bytes
//                                                                                usage:GL_DYNAMIC_DRAW];
//    
//    [self.vertexDataBuffer enableAttribute:attrib[ATTRIB_POSITION]];
//    [self.vertexDataBuffer enableAttribute:attrib[ATTRIB_NORMAL]];
//    [self.vertexDataBuffer enableAttribute:attrib[ATTRIB_COLOR]];
//    
//    [_wireFrame setVertexData:wireframeData vertexNum:wireframeData.length/sizeof(VertexNormRGBA)];
    

    
//    return data;
}

//-(void)createBranchAtPoints:(NSMutableData*)pointData {
//    GLKVector3* points = (GLKVector3*)pointData.bytes;
//    int numOfPoints = pointData.length / sizeof(GLKVector3);
//    
//    int size = _manifold.no_vertices();
//    VertexAttributeVector<int> vs(size, 0);
//    
//    for (int i = 0; i < numOfPoints; i++) {
//        GLKVector3 ptn = points[i];
//        VertexID pointID = [self closestVertexID:ptn];
//        vs[pointID] = 1;
//    }
//
//    polar_add_branch(_manifold, vs);
//    
//    NSMutableData* vertexData = [[NSMutableData alloc] init];
//    NSMutableData* wireframeData = [[NSMutableData alloc] init];
//    [self triangulateManifold:_manifold trianglMeshData:&vertexData wireframeData:&wireframeData];
//    
//    self.numVertices = vertexData.length / sizeof(VertexNormRGBA);
//    
//    self.vertexDataBuffer = [[AGLKVertexAttribArrayBuffer alloc] initWithAttribStride:sizeof(VertexNormRGBA)
//                                                                     numberOfVertices:self.numVertices
//                                                                                bytes:vertexData.bytes
//                                                                                usage:GL_DYNAMIC_DRAW];
//    
//    [self.vertexDataBuffer enableAttribute:attrib[ATTRIB_POSITION]];
//    [self.vertexDataBuffer enableAttribute:attrib[ATTRIB_NORMAL]];
//    [self.vertexDataBuffer enableAttribute:attrib[ATTRIB_COLOR]];
//    
//    [_wireFrame setVertexData:wireframeData vertexNum:wireframeData.length/sizeof(VertexNormRGBA)];
//}

-(VertexID)closestVertexID:(GLKVector3)touchPoint {
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
    return closestVertex;
}

-(GLKVector3)closestVertexToMeshPoint:(GLKVector3)touchPoint setAsCurrentID:(BOOL)setAsCurrentID {
    
    VertexID vID = [self closestVertexID:touchPoint];
    if (setAsCurrentID) {
        _curSelectedVertexID = vID;
    }
    CGLA::Vec3d vertexPos = _manifold.pos(vID);
    GLKVector4 glkVertextPos = GLKVector4Make(vertexPos[0], vertexPos[1], vertexPos[2], 1.0);
    glkVertextPos = GLKMatrix4MultiplyVector4(self.modelMatrix, glkVertextPos);
    return  GLKVector3Make(glkVertextPos.x, glkVertextPos.y, glkVertextPos.z);
}

-(GLKVector3)convertModel:(GLKVector3)vertexPos {
    GLKVector4 glkVertextPos = GLKVector4MakeWithVector3(vertexPos, 1.0f);
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

-(GLKVector3)translateCurrentSelectedVertex:(GLKVector3)newPosition  {
    
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
    _manifold.pos(_curSelectedVertexID) = newPos;
    
    GLKVector4 glkVertextPos = GLKVector4MakeWithVector3(vk, 1.0f);
    glkVertextPos = GLKMatrix4MultiplyVector4(self.modelMatrix, glkVertextPos);
    return  GLKVector3Make(glkVertextPos.x, glkVertextPos.y, glkVertextPos.z);
}

-(void)rebuffer {
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
-(void)triangulateManifold:(HMesh::Manifold&)mani
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
        ColorRGBA wireframeColor = {0,0,0,255};
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

-(void)gaussianStart:(GLKVector3)touchPoint {
    touchPoint = [Utilities invertVector3:touchPoint withMatrix:self.modelMatrix];
    Vec3d p0 = Vec3d(touchPoint.x, touchPoint.y, touchPoint.z);
    float brush_size = 0.001;
    mousePoint = touchPoint;
    old_mani = _manifold;
    Vec3d c;
    float r;
    bsphere(_manifold, c, r);
    for(auto vid : _manifold.vertices())
    {
        double l = sqr_length(p0-_manifold.pos(vid));
        weight_vector[vid] = exp(-l/(brush_size*r*r));
    }
}

-(void)gaussianMove:(GLKVector3)touchPoint {
    touchPoint = [Utilities invertVector3:touchPoint withMatrix:self.modelMatrix];
    Vec3d displace = Vec3d(touchPoint.x - mousePoint.x, touchPoint.y - mousePoint.y, touchPoint.z - mousePoint.z);

    VertexID vID = [self closestVertexID:mousePoint];
    Vec3d norm = HMesh::normal(_manifold, vID);
    
    float angle = acos(dot(normalize(displace), normalize(norm)));
    Vec3d c;
    float r;
    bsphere(_manifold, c, r);
    
    if (angle < GLKMathDegreesToRadians(50) && length(displace) > r*0.05) {
        NSLog(@"MOVED PERPENDICULAR WAS %f", GLKMathRadiansToDegrees(angle));
        VertexID newPoleID;
        Vec3d mouseVertex = _manifold.pos(vID);

        BOOL result = [self createBranchAtPoint:GLKVector3Make(mouseVertex[0], mouseVertex[1], mouseVertex[2]) width:self.branchWidth vertexID:&newPoleID];
        if (result) {
            HMesh::VertexAttributeVector<int> poles(_manifold.no_vertices(), 0);
            poles[newPoleID] = 1;
            refine_poles(_manifold, poles);
            
//            float proj = dot(norm, displace)/length(norm);
//            displace = norm*proj;
            
            // Move pole
            _manifold.pos(newPoleID) = _manifold.pos(newPoleID) + displace;
            
            // Move vertecies adjacent to pole
            for (Walker walker = _manifold.walker(newPoleID); !walker.full_circle(); walker = walker.circulate_vertex_ccw()) {
                _manifold.pos(walker.vertex()) = _manifold.pos(walker.vertex()) + displace*0.97;
            }
        }
        
    } else {
        NSLog(@"GAUSSIAN MOVE %f", GLKMathRadiansToDegrees(angle));
        for(auto vid : _manifold.vertices())
        {
            _manifold.pos(vid) = old_mani.pos(vid) + weight_vector[vid] * displace;
        }
    }
}

-(void)showSkeleton:(BOOL)show {
    if (show) {
        skeletonMani = _manifold;
        skeleton_retract(_manifold, 0.9f);
    } else {
        _manifold = skeletonMani;
    }
    [self rebuffer];
}

-(void)moveVertexCloseTo:(GLKVector3)touchPoint orthogonallyBy:(float)distance {
    touchPoint = [Utilities invertVector3:touchPoint withMatrix:self.modelMatrix];
    VertexID vID = [self closestVertexID:touchPoint];
    Vec3d norm = HMesh::normal(_manifold, vID);
    
    _manifold.pos(vID) = _manifold.pos(vID) + norm*distance;
    
    if (is_pole(_manifold, vID)) {
        // Move vertecies adjacent to pole
        for (Walker walker = _manifold.walker(vID); !walker.full_circle(); walker = walker.circulate_vertex_ccw()) {
            _manifold.pos(walker.vertex()) = _manifold.pos(walker.vertex()) + norm*distance*0.98;
        }
    }
    
    [self rebuffer];
}

-(void)moveVertexOrthogonallyCloseTo:(GLKVector3)touchPoint {
    Vec3d c;
    float r;
    bsphere(_manifold, c, r);
    [self moveVertexCloseTo:touchPoint orthogonallyBy:r * 0.05];
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

    glEnable(GL_POLYGON_OFFSET_FILL);
    glPolygonOffset(2.0f, 2.0f);
    
    [AGLKVertexAttribArrayBuffer drawPreparedArraysWithMode:GL_TRIANGLES
                                           startVertexIndex:0
                                           numberOfVertices:self.numVertices];

    glDisable(GL_POLYGON_OFFSET_FILL);
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
