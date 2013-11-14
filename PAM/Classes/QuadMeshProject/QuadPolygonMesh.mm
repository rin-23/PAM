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
#include "Mat4x4d.h"

@interface QuadPolygonMesh() {
    HMesh::Manifold _manifold;
    WireFrame* _wireFrame;
    HMesh::VertexID _curSelectedVertexID;
    BoundingBox _boundingBox;

    //Gaussian
    HMesh::Manifold old_mani;
    GLKVector3 mousePoint;
    HMesh::VertexAttributeVector<float> weight_vector;
    
    //Branch bending
    HMesh::FaceID _branchBendFaceID;
    GLKVector3 _branchBendingInitialPoint;
    
    //Skeleton
    HMesh::Manifold skeletonMani;
    
    //Undo
    HMesh::Manifold undoMani;
}

@property (nonatomic) AGLKVertexAttribArrayBuffer* wireframeVertexBuffer;
@end

@implementation QuadPolygonMesh

GLKVector3 GLKMatrix4MultiplyVector3Custom(GLKMatrix4 matrix, GLKVector3 vector3) {
    GLKVector4 vector4 = GLKVector4MakeWithVector3(vector3, 1.0f);
    vector4 = GLKMatrix4MultiplyVector4(matrix, vector4);
    return GLKVector3Make(vector4.x, vector4.y, vector4.z);
}

GLKVector2 GLKVector2MakeWithVector3(GLKVector3 vector3) {
    return GLKVector2Make(vector3.x, vector3.y);
}

GLKVector3 GLKVector3MakeWithVec3d(Vec3d v) {
    return GLKVector3Make(v[0], v[1], v[2]);
}

using namespace HMesh;

-(void)setMeshFromObjFile:(NSString*)objFilePath {
    
    _branchWidth = 1;
    //Load manifold
    _manifold = HMesh::Manifold();
    undoMani = _manifold;
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
    undoMani = _manifold;
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
    undoMani = _manifold;
    VertexID vID = [self closestVertexID:touchPoint];
    HMesh::HalfEdgeAttributeVector<EdgeInfo> edgeInfo = trace_spine_edges(_manifold);
    Walker walker = _manifold.walker(vID);
    if (edgeInfo[walker.halfedge()].edge_type != SPINE) {
        walker = walker.next();
    }
    HalfEdgeID newEdge = add_rib(_manifold, walker.halfedge());
    add_rib(_manifold, walker.halfedge());
    add_rib(_manifold, newEdge);
    [self rebuffer];
}

//Create branch at a point near touch point. Return VertexID of newly created pole. -1 is returned if failed.
-(BOOL)createBranchAtPoint:(GLKVector3)touchPoint width:(int)width vertexID:(VertexID*)newPoleID {
    undoMani = _manifold;
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

    walker = walker.next(); //advance one step to pass while loop test
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
    refine_branch(_manifold, *newPoleID);
    
    return YES;
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


//touchPoint is in WORLD coordinates. need to convert manifold coordinates into view coordinates
-(VertexID)closestVertexID_2DProjection:(GLKVector2)touchPoint {
    float distance = FLT_MAX;
    HMesh::VertexID closestVertex;
    
    for (VertexIDIterator vID = _manifold.vertices_begin(); vID != _manifold.vertices_end(); vID++) {
        CGLA::Vec3d vertexPos = _manifold.pos(*vID);
        
        GLKVector4 glkVertextPos = GLKVector4Make(vertexPos[0], vertexPos[1], vertexPos[2], 1.0f);
        GLKVector4 glkVertextPosModelView = GLKMatrix4MultiplyVector4(self.modelViewMatrix, glkVertextPos);
        GLKVector2 glkVertextPosModelView_2 = GLKVector2Make(glkVertextPosModelView.x, glkVertextPosModelView.y);
        float cur_distance = GLKVector2Distance(touchPoint, glkVertextPosModelView_2);

        if (cur_distance < distance) {
            distance = cur_distance;
            closestVertex = *vID;
        }
    }
    return closestVertex;
}

//touchPoint is in VIEW coordinates.
-(VertexID)closestVertexID:(GLKVector3)touchPoint {
    //iterate over every face
    float distance = FLT_MAX;
    HMesh::VertexID closestVertex;
    
    touchPoint = [Utilities invertVector3:touchPoint withMatrix:self.modelMatrix];
    
    //TODO refactor
    for (VertexIDIterator vID = _manifold.vertices_begin(); vID != _manifold.vertices_end(); vID++) {
            CGLA::Vec3d vertexPos = _manifold.pos(*vID);
            GLKVector3 glkVertextPos = GLKVector3Make(vertexPos[0], vertexPos[1], vertexPos[2]);
            float cur_distance = GLKVector3Distance(touchPoint, glkVertextPos);
            if (cur_distance < distance) {
                distance = cur_distance;
                closestVertex = *vID;
            }
    }
    return closestVertex;
}

//touchPoint is in VIEW coordinates. Need to convert manifold coordinates into view coordinates
//TODO make it better by figuring out the FaceID that contain touchPoint within
-(FaceID)closestFaceID_2DProjection:(GLKVector3)touchPoint {
    touchPoint = GLKMatrix4MultiplyVector3Custom(self.viewMatrix, touchPoint);
    VertexID vID = [self closestVertexID_2DProjection:GLKVector2Make(touchPoint.x, touchPoint.y)];
    Walker w = _manifold.walker(vID);
    return w.face();
}



//-(GLKVector3)closestVertexToMeshPoint:(GLKVector3)touchPoint setAsCurrentID:(BOOL)setAsCurrentID {
//    
//    VertexID vID = [self closestVertexID:touchPoint];
//    if (setAsCurrentID) {
//        _curSelectedVertexID = vID;
//    }
//    CGLA::Vec3d vertexPos = _manifold.pos(vID);
//    GLKVector4 glkVertextPos = GLKVector4Make(vertexPos[0], vertexPos[1], vertexPos[2], 1.0);
//    glkVertextPos = GLKMatrix4MultiplyVector4(self.modelMatrix, glkVertextPos);
//    return  GLKVector3Make(glkVertextPos.x, glkVertextPos.y, glkVertextPos.z);
//}

//-(GLKVector3)convertModel:(GLKVector3)vertexPos {
//    GLKVector4 glkVertextPos = GLKVector4MakeWithVector3(vertexPos, 1.0f);
//    glkVertextPos = GLKMatrix4MultiplyVector4(self.modelMatrix, glkVertextPos);
//    return  GLKVector3Make(glkVertextPos.x, glkVertextPos.y, glkVertextPos.z);
//}

//-(BOOL)touchedCloseToTheCurrentVertex:(GLKVector3)touchPoint {
//    touchPoint = [Utilities invertVector3:touchPoint withMatrix:self.modelMatrix];
//    float threshold = _boundingBox.radius * 0.1;
//    
//    CGLA::Vec3d vertexPos = _manifold.pos(_curSelectedVertexID);
//    GLKVector3 glkPos = GLKVector3Make(vertexPos[0], vertexPos[1], vertexPos[2]);
//    
//    GLKVector4 currentPosition4 = GLKMatrix4MultiplyVector4(self.modelViewMatrix, GLKVector4MakeWithVector3(glkPos, 1.0));
//    GLKVector4 newPosition4 = GLKMatrix4MultiplyVector4(self.modelViewMatrix, GLKVector4MakeWithVector3(touchPoint, 1.0));
//    
//    float d = GLKVector2Distance(GLKVector2Make(currentPosition4.x, currentPosition4.y), GLKVector2Make(newPosition4.x, newPosition4.y));
//    if (d <= threshold) {
//        return YES;
//    }
//    return NO;
//}
//
//-(GLKVector3)translateCurrentSelectedVertex:(GLKVector3)newPosition  {
//    
//    newPosition = [Utilities invertVector3:newPosition withMatrix:self.modelMatrix];
//    
//    CGLA::Vec3d vertexPos = _manifold.pos(_curSelectedVertexID);
//    GLKVector3 currePosition = GLKVector3Make(vertexPos[0], vertexPos[1], vertexPos[2]);
//    
//    GLKVector4 currentPosition4 = GLKMatrix4MultiplyVector4(self.modelViewMatrix, GLKVector4MakeWithVector3(currePosition, 1.0));
//    GLKVector4 newPosition4 = GLKMatrix4MultiplyVector4(self.modelViewMatrix, GLKVector4MakeWithVector3(newPosition, 1.0));
//    GLKVector3 point3 = GLKVector3Make(newPosition4.x, newPosition4.y, currentPosition4.z);
//    
//    bool isInvertible;
//    GLKVector4 axis = GLKMatrix4MultiplyVector4(GLKMatrix4Invert(self.modelViewMatrix, &isInvertible), GLKVector4MakeWithVector3(point3, 1.0));
//        
//    GLKVector3 vk = GLKVector3Make(axis.x, axis.y, axis.z);
//
//    CGLA::Vec3d newPos = CGLA::Vec3d(vk.x, vk.y, vk.z);
//    _manifold.pos(_curSelectedVertexID) = newPos;
//    
//    GLKVector4 glkVertextPos = GLKVector4MakeWithVector3(vk, 1.0f);
//    glkVertextPos = GLKMatrix4MultiplyVector4(self.modelMatrix, glkVertextPos);
//    return  GLKVector3Make(glkVertextPos.x, glkVertextPos.y, glkVertextPos.z);
//}

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

-(void)scaleRib:(GLKVector3)touchPoint byFactor:(float)scale {
    touchPoint = [Utilities invertVector3:touchPoint withMatrix:self.modelMatrix];
    VertexID vID = [self closestVertexID:touchPoint];
    Walker w = _manifold.walker(vID);
    HMesh::HalfEdgeAttributeVector<EdgeInfo> edgeInfo = trace_spine_edges(_manifold);
    if (edgeInfo[w.halfedge()].edge_type != RIB) {
        w = w.prev();
    }
    assert(edgeInfo[w.halfedge()].edge_type == RIB);
    
    change_rib_radius(_manifold, w.halfedge(), scale);
    [self rebuffer];
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

-(void)saveState {
    undoMani = _manifold;
}

-(void)branchCreateMovementStart:(GLKVector3)touchPoint {
    
    mousePoint = [Utilities invertVector3:touchPoint withMatrix:self.modelMatrix];;
}

-(void)branchCreateMovementEnd:(GLKVector3)touchPoint {
    [self saveState];
    touchPoint = [Utilities invertVector3:touchPoint withMatrix:self.modelMatrix];
    
    GLKVector3 mousePoint_inView_3 = GLKMatrix4MultiplyVector3Custom(self.modelViewMatrix, mousePoint);
    VertexID vID = [self closestVertexID_2DProjection:GLKVector2Make(mousePoint_inView_3.x, mousePoint_inView_3.y)];
    Vec3d norm = normalize(HMesh::normal(_manifold, vID));
    
//    GLKVector3 touchPoint_inView_3 = touchPoint;//GLKMatrix4MultiplyVector3Custom(self.viewMatrix, touchPoint);
//    GLKVector2 touchPoint_inView_2 = GLKVector2Make(touchPoint_inView_3.x, touchPoint_inView_3.y);
//    Vec2d displace2d = Vec2d(touchPoint_inView_2.x - mousePoint_inView_2.x, touchPoint_inView_2.y - mousePoint_inView_2.y);
    Vec3d displace = Vec3d(touchPoint.x - mousePoint.x, touchPoint.y - mousePoint.y, touchPoint.z - mousePoint.z);

    VertexID newPoleID;
    Vec3d mouseVertex = _manifold.pos(vID);
    BOOL result = [self createBranchAtPoint:GLKVector3Make(mouseVertex[0], mouseVertex[1], mouseVertex[2])
                                      width:self.branchWidth
                                   vertexID:&newPoleID];
    if (result) {
        HMesh::VertexAttributeVector<int> poles(_manifold.no_vertices(), 0);
        poles[newPoleID] = 1;
        refine_poles(_manifold, poles);

        Vec3d displace3d =  norm * displace.length();
        
        // Move pole
        _manifold.pos(newPoleID) = _manifold.pos(newPoleID) + displace3d;
        
        // Move vertecies adjacent to pole
        for (Walker walker = _manifold.walker(newPoleID); !walker.full_circle(); walker = walker.circulate_vertex_ccw()) {
            _manifold.pos(walker.vertex()) = _manifold.pos(walker.vertex()) + displace3d*0.8f;
        }
        
        //Add ribs for the new branch
        Walker walker = _manifold.walker(newPoleID);
        HalfEdgeID ID_1 = walker.next().opp().next().halfedge();
        recursively_add_rib(_manifold, ID_1, 4);

        [self rebuffer];
    }
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
        double l = sqr_length(p0 - _manifold.pos(vid));
        weight_vector[vid] = exp(-l/(brush_size*r*r));
    }
}

-(void)gaussianMove:(GLKVector3)touchPoint {
    [self saveState];
    
    touchPoint = [Utilities invertVector3:touchPoint withMatrix:self.modelMatrix];
    Vec3d displace = Vec3d(touchPoint.x - mousePoint.x, touchPoint.y - mousePoint.y, touchPoint.z - mousePoint.z);

    VertexID vID = [self closestVertexID:mousePoint];
    Vec3d norm = HMesh::normal(_manifold, vID);
    
//    float angle = acos(dot(normalize(displace), normalize(norm)));
    Vec3d c;
    float r;
    bsphere(_manifold, c, r);
    
    if (length(displace) > r*0.05) {
//        NSLog(@"MOVED PERPENDICULAR WAS %f", GLKMathRadiansToDegrees(angle));
        VertexID newPoleID;
        Vec3d mouseVertex = _manifold.pos(vID);

        BOOL result = [self createBranchAtPoint:GLKVector3Make(mouseVertex[0], mouseVertex[1], mouseVertex[2]) width:self.branchWidth vertexID:&newPoleID];
        if (result) {
            HMesh::VertexAttributeVector<int> poles(_manifold.no_vertices(), 0);
            poles[newPoleID] = 1;
            refine_poles(_manifold, poles);
            
//            float proj = dot(norm, displace)/length(norm);
            displace = norm * displace.length();
            
            // Move pole
            _manifold.pos(newPoleID) = _manifold.pos(newPoleID) + displace;
            
            // Move vertecies adjacent to pole
            for (Walker walker = _manifold.walker(newPoleID); !walker.full_circle(); walker = walker.circulate_vertex_ccw()) {
                _manifold.pos(walker.vertex()) = _manifold.pos(walker.vertex()) + displace*0.8f;
            }
            
            //Add ribs for the new branch
            Walker walker = _manifold.walker(newPoleID);
            HalfEdgeID ID_1 = walker.next().opp().next().halfedge();
            HalfEdgeID ID_2 = add_rib(_manifold, ID_1);
            add_rib(_manifold, ID_1);
            add_rib(_manifold, ID_2);
        }
        
    } else {
//        NSLog(@"GAUSSIAN MOVE %f", GLKMathRadiansToDegrees(angle));
//        for(auto vid : _manifold.vertices())
//        {
//            _manifold.pos(vid) = old_mani.pos(vid) + weight_vector[vid] * displace;
//        }
    }
    [self rebuffer];
}


//Touch point in VIEW coordinates
-(void)bendBranchBeginWithBendingPivot:(GLKVector3)bendingPivot touchPoint:(GLKVector3)touchPoint {
    _branchBendingInitialPoint = touchPoint;
    _branchBendFaceID = [self closestFaceID_2DProjection:bendingPivot];
}

//Touch point in VIEW coordinates
-(void)bendBranchEnd:(GLKVector3)touchPoint {
    [self saveState];
    HMesh::HalfEdgeAttributeVector<EdgeInfo> edgeInfo = trace_spine_edges(_manifold);
    Walker w = _manifold.walker(_branchBendFaceID);
    
    if (edgeInfo[w.halfedge()].edge_type == RIB) {
        w = w.next();
    }
    
    assert(edgeInfo[w.halfedge()].edge_type == SPINE);
    
    //FIND POLE
    //Walk one direction
    HalfEdgeID poleDirectionHalfEdge;
    Walker w1 = w;
    
    while (!is_pole(_manifold, w1.vertex()) && !is_connecting_ring(_manifold, w1.next().halfedge())) {
        w1 = w1.next().opp().next();
    }
    if (is_pole(_manifold, w1.vertex())) {
        poleDirectionHalfEdge = w.halfedge();
    } else if (is_connecting_ring(_manifold, w1.next().halfedge())) {
        //walk opposite direction
        Walker w1 = w.opp();
        while (!is_pole(_manifold, w1.vertex()) && !is_connecting_ring(_manifold, w1.next().halfedge())) {
            w1 = w1.next().opp().next();
        }
        if (is_pole(_manifold, w1.vertex())) {
            poleDirectionHalfEdge = w.opp().halfedge();
        } else if (is_connecting_ring(_manifold, w1.next().halfedge())) {
            NSLog(@"Erroe bending the branch. Couldnt find the pole");
            return;
        }
    }
    
    //Walk towards pole and collect vertex ids for every ring
    vector<vector<VertexID>> rings;
    vector<Vec3d> centroids;
    Walker spineWalker = _manifold.walker(poleDirectionHalfEdge);
    for (; !is_pole(_manifold, spineWalker.vertex()); spineWalker = spineWalker.next().opp().next())
    {
        assert(edgeInfo[spineWalker.next().halfedge()].edge_type == RIB);
        
        vector<VertexID> vIDs;
        Vec3d centroid = Vec3d(0,0,0);
        Walker ribWalker = _manifold.walker(spineWalker.next().halfedge());
        
        for (;!ribWalker.full_circle(); ribWalker = ribWalker.next().opp().next())
        {
            vIDs.push_back(ribWalker.vertex());
            centroid += _manifold.pos(ribWalker.vertex());
        }
        centroids.push_back(centroid/(float)vIDs.size());
        rings.push_back(vIDs);
    }
    //Add the pole
    centroids.push_back(_manifold.pos(spineWalker.vertex()));
    vector<VertexID> vIDs;
    vIDs.push_back(spineWalker.vertex());
    rings.push_back(vIDs);
    
    assert(centroids.size() == rings.size());
    
    //Get the length of the branch
    float branch_length = 0;
    for (int i = centroids.size() - 1; i > 0; i--) {
        branch_length += (centroids[i] - centroids[i-1]).length();
    }
    
    //Calculate gaussian weights
    vector<float> gaussian_weights(centroids.size());
    for (int i = 0; i < centroids.size(); i++) {
        double l = sqr_length(centroids[i] - centroids[centroids.size() - 1]);
        gaussian_weights[i] = exp(-l/(0.3*branch_length*branch_length));
    }
    
    //TODO apply translation and apply gaussian weights
    GLKVector3 startBendingWorld = GLKMatrix4MultiplyVector3Custom(self.viewMatrix, _branchBendingInitialPoint);
    GLKVector3 endBendingWorld = GLKMatrix4MultiplyVector3Custom(self.viewMatrix, touchPoint);
    GLKVector2 displacement = GLKVector2Subtract(GLKVector2MakeWithVector3(endBendingWorld),
                                                 GLKVector2MakeWithVector3(startBendingWorld));
    
    for (int i = 0; i < rings.size(); i++) {
        vector<VertexID> vIDs = rings[i];
        float weight = gaussian_weights[i];
        for (int j = 0; j < vIDs.size(); j++) {
            VertexID vID = vIDs[j];
            Vec3d v_pos = _manifold.pos(vID);
            GLKVector3 v_pos_glk_model = GLKVector3MakeWithVec3d(v_pos);
            GLKVector3 v_pos_glk_world = GLKMatrix4MultiplyVector3Custom(self.modelViewMatrix, v_pos_glk_model);
            v_pos_glk_world.x += weight * displacement.x;
            v_pos_glk_world.y += weight * displacement.y;
            v_pos_glk_model = [Utilities invertVector3:v_pos_glk_world withMatrix:self.modelViewMatrix];
            v_pos = Vec3d(v_pos_glk_model.x, v_pos_glk_model.y, v_pos_glk_model.z);
            _manifold.pos(vID) = v_pos;
        }
    }
    [self rebuffer];
}

-(void)undo {
    _manifold = undoMani;
    [self rebuffer];    
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
    undoMani = _manifold;
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
