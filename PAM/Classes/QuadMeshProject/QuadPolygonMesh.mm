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
#include <map>
#include <set>
#import "Vec4uc.h"

typedef CGLA::Vec3d Vec;
typedef CGLA::Vec3f Vecf;


@interface QuadPolygonMesh() {
    int current_buffer;
    HMesh::Manifold _manifold;
    HMesh::HalfEdgeAttributeVector<EdgeInfo> _edgeInfo;

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
    BOOL _firstTouchedFace;
    float _accumScale;
    
    //Scaling of Rings
    HMesh::FaceID _scaleRibFace1;
    HMesh::FaceID _scaleRibFace2;
    BOOL _shouldBeginRibScaling;
    vector<HMesh::HalfEdgeID> _edges_to_scale;
    vector<HMesh::VertexID> _all_vector_vid;
    HMesh::VertexAttributeVector<Vec> _current_scale_position;
//    HMesh::Manifold _scaleSaveMani;
    
    //Skeleton
    HMesh::Manifold skeletonMani;
    
    //Undo
    HMesh::Manifold undoMani;
 
    map<HMesh::VertexID, vector<HMesh::FaceID>> dic_vertex_to_face; //store information about regions need to be updated
    map<HMesh::FaceID, unsigned long> dic_face_to_buffer; //store information about regions need to be updated
    
    map<HMesh::VertexID, vector<int>> dic_wireframe_vertex_to_buffer; //store information about regions need to be updated
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

GLKVector3 GLKVector3MakeWithVec(Vec v) {
    return GLKVector3Make(v[0], v[1], v[2]);
}

using namespace HMesh;

-(void)setMeshFromObjFile:(NSString*)objFilePath {
    
    _branchWidth = 1;
    current_buffer = 0;
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
    NSMutableData* indexData = [[NSMutableData alloc] init];
    [self triangulateManifold:_manifold vertexPositionData:&vertexData vertexPositionIndexData:&indexData];

    self.numVertices = vertexData.length / sizeof(VertexNormRGBA);
    self.meshData = vertexData;
    
    self.vertexDataBuffer = [[AGLKVertexAttribArrayBuffer alloc]     initWithAttribStride:sizeof(VertexNormRGBA)
                                                                     numberOfVertices:self.numVertices
                                                                                bytes:vertexData.bytes
                                                                                usage:GL_DYNAMIC_DRAW
                                                                               target:GL_ARRAY_BUFFER];
    [self.vertexDataBuffer enableAttribute:attrib[ATTRIB_POSITION]];
    [self.vertexDataBuffer enableAttribute:attrib[ATTRIB_NORMAL]];
    [self.vertexDataBuffer enableAttribute:attrib[ATTRIB_COLOR]];

    self.doubleVertexBuffer = [[AGLKVertexAttribArrayBuffer alloc] initWithAttribStride:sizeof(VertexNormRGBA)
                                                                     numberOfVertices:self.numVertices
                                                                                bytes:vertexData.bytes
                                                                                usage:GL_DYNAMIC_DRAW
                                                                                target:GL_ARRAY_BUFFER];
    [self.doubleVertexBuffer enableAttribute:attrib[ATTRIB_POSITION]];
    [self.doubleVertexBuffer enableAttribute:attrib[ATTRIB_NORMAL]];
    [self.doubleVertexBuffer enableAttribute:attrib[ATTRIB_COLOR]];

    
    //Create Wireframe Object
    _wireFrame = [[WireFrame alloc]  init];
    _wireFrame.centerAtBoundingBox = YES;
    _wireFrame.boundingBox = _boundingBox;
//    [_wireFrame setVertexData:wireframeData vertexNum:wireframeData.length/sizeof(VertexNormRGBA)];
}

//Create branch at a point near touch point.
-(BOOL)createBranchAtPointAndRefine:(GLKVector3)touchPoint {
    VertexID newPoleID;
    BOOL result = [self createBranchAtPoint:touchPoint width:self.branchWidth vertexID:&newPoleID];
    if (result) {
        HMesh::VertexAttributeVector<int> poles(_manifold.no_vertices(), 0);
        poles[newPoleID] = 1;
//        refine_poles(_manifold, poles);
        [self rebuffer];
    }
    return result;
}

-(void)createNewSpineAtPoint:(GLKVector3)touchPoint {
    undoMani = _manifold;
    VertexID vID = [self closestVertexID:touchPoint];
    Walker walker = _manifold.walker(vID);
    if (_edgeInfo[walker.halfedge()].edge_type != RIB) {
        walker = walker.next();
    }
    add_spine(_manifold, walker.halfedge());
    [self rebuffer];
}      

-(void)createNewRibAtPoint:(GLKVector3)touchPoint {
    undoMani = _manifold;
    VertexID vID = [self closestVertexID:touchPoint];
    Walker walker = _manifold.walker(vID);
    if (_edgeInfo[walker.halfedge()].edge_type != SPINE) {
        walker = walker.next();
    }
    HalfEdgeID newEdge = add_rib(_manifold, walker.halfedge(), _edgeInfo);
    add_rib(_manifold, walker.halfedge(), _edgeInfo);
    add_rib(_manifold, newEdge, _edgeInfo);
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
        if (_edgeInfo[walker.halfedge()].edge_type == RIB) {
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
        Vec vertexPos = _manifold.pos(*vID);
        
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
            Vec vertexPos = _manifold.pos(*vID);
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

-(BOOL)pickFace:(FaceID*)faceID rayOrigin:(GLKVector3)rayOrigin rayDirection:(GLKVector3)rayDirection

{
    for(FaceIDIterator fid = _manifold.faces_begin(); fid != _manifold.faces_end(); ++fid) {
        
        GLKVector3 faceVerticies[4];
        int num_edges = 0;
        for(Walker w = _manifold.walker(*fid); !w.full_circle(); w = w.circulate_face_cw()) {
            Vec v = _manifold.pos(w.vertex());
            faceVerticies[num_edges] = GLKVector3Make(v[0], v[1], v[2]);
            num_edges++;
            if (num_edges > 4) { //either quad or triangle
                NSLog(@"[ERROR][QuadPolygonMesh][pickFacetRayOrigin:rayDirection:] Wrong number of edges");
                return NO;
            }
        }

        BOOL hit = NO;
        if (num_edges == 3) {
            hit = [Utilities hitTestTriangle:faceVerticies withRayStart:rayOrigin rayDirection:rayDirection];
        } else { //quad
            hit = [Utilities hitTestQuad:faceVerticies withRayStart:rayOrigin rayDirection:rayDirection];
        }
        
        if (hit) {
            *faceID = *fid;
            return YES;
        }
    }
    return NO;
}

//-(GLKVector3)closestVertexToMeshPoint:(GLKVector3)touchPoint setAsCurrentID:(BOOL)setAsCurrentID {
//    
//    VertexID vID = [self closestVertexID:touchPoint];
//    if (setAsCurrentID) {
//        _curSelectedVertexID = vID;
//    }
//    Vec vertexPos = _manifold.pos(vID);
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
//    Vec vertexPos = _manifold.pos(_curSelectedVertexID);
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
//    Vec vertexPos = _manifold.pos(_curSelectedVertexID);
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
//    Vec newPos = Vec(vk.x, vk.y, vk.z);
//    _manifold.pos(_curSelectedVertexID) = newPos;
//    
//    GLKVector4 glkVertextPos = GLKVector4MakeWithVector3(vk, 1.0f);
//    glkVertextPos = GLKMatrix4MultiplyVector4(self.modelMatrix, glkVertextPos);
//    return  GLKVector3Make(glkVertextPos.x, glkVertextPos.y, glkVertextPos.z);
//}

-(void)rebuffer {
    
    NSMutableData* vertexData = [[NSMutableData alloc] init];
    NSMutableData* wireframeData = [[NSMutableData alloc] init];
//    [self triangulateManifold:_manifold trianglMeshData:&vertexData wireframeData:&wireframeData];
    
    self.numVertices = vertexData.length / sizeof(VertexNormRGBA);
    self.meshData = vertexData;
    
    self.vertexDataBuffer = [[AGLKVertexAttribArrayBuffer alloc] initWithAttribStride:sizeof(VertexNormRGBA)
                                                                     numberOfVertices:self.numVertices
                                                                                bytes:self.meshData.bytes
                                                                                usage:GL_DYNAMIC_DRAW
                                                                               target:GL_ARRAY_BUFFER] ;
    
    glEnableVertexAttribArray(attrib[ATTRIB_POSITION]);
    glEnableVertexAttribArray(attrib[ATTRIB_NORMAL]);
    glEnableVertexAttribArray(attrib[ATTRIB_COLOR]);
    
    self.doubleVertexBuffer = [[AGLKVertexAttribArrayBuffer alloc] initWithAttribStride:sizeof(VertexNormRGBA)
                                                                     numberOfVertices:self.numVertices
                                                                                bytes:self.meshData.bytes
                                                                                usage:GL_DYNAMIC_DRAW
                                                                                 target:GL_ARRAY_BUFFER];
    
    glEnableVertexAttribArray(attrib[ATTRIB_POSITION]);
    glEnableVertexAttribArray(attrib[ATTRIB_NORMAL]);
    glEnableVertexAttribArray(attrib[ATTRIB_COLOR]);
    
    [_wireFrame setVertexData:wireframeData vertexNum:wireframeData.length/sizeof(VertexNormRGBA)];
    
}

//Triangulate manifold for display in case it has quads. GLES doesnt handle quads.
-(void)triangulateManifold:(HMesh::Manifold&)mani
        vertexPositionData:(NSMutableData**)vertexPosition
   vertexPositionIndexData:(NSMutableData**)vertexPositionIndex
{
    //clear dictionaries
//    dic_vertex_to_face.clear();
//    dic_face_to_buffer.clear();
//    dic_wireframe_vertex_to_buffer.clear();
    
    //iterate over every face
    
    for (VertexIDIterator vid = mani.vertices_begin(); vid != mani.vertices_end(); ++vid) {
        Vecf positionf = mani.posf(*vid);
        [*vertexPosition appendBytes:positionf.get() length:sizeof(float) * positionf.get_dim()];
    }
    
    for(FaceIDIterator fid = mani.faces_begin(); fid != mani.faces_end(); ++fid) {
        int vertexNum = 0;
        int facet[4];
        
//        Vecf norm = HMesh::normalf(mani, *fid);
//        Vec4uc color(200,200,200,255);
//        PositionXYZ normGL = {(GLfloat)norm[0], (GLfloat)norm[1], (GLfloat)norm[2]};
//        ColorRGBA vertexColor = {200,200,200,255};
//        dic_face_to_buffer[*fid] = (*verticies).length;
        
        //iterate over every vertex of the face
        for(Walker w = mani.walker(*fid); !w.full_circle(); w = w.circulate_face_ccw()) {
            //add vertex to the data array
            VertexID vID = w.vertex();
            int index = vID.index;

//            Vecf c = mani.posf(vID);
//            PositionXYZ positionDCM = {(GLfloat)c[0], (GLfloat)c[1], (GLfloat)c[2]};
//            VertexNormRGBA vertexMono = {positionDCM, normGL, vertexColor};
            facet[vertexNum] = index;

            vertexNum++;
        
            if (vertexNum == 4) {
                //Create a second triangle
                [*vertexPositionIndex appendBytes:&facet[0] length:sizeof(int)];
                [*vertexPositionIndex appendBytes:&facet[2] length:sizeof(int)];

//                [*verticies appendBytes:&facet[0] length:sizeof(VertexNormRGBA)];
//                [*verticies appendBytes:&facet[2] length:sizeof(VertexNormRGBA)];
            }
            
            [*vertexPositionIndex appendBytes:&index length:sizeof(int)];
            
//            [*verticies appendBytes:&vertexMono length:sizeof(VertexNormRGBA)];
            
//            //Populate vertex to face dictionary
//            if (dic_vertex_to_face.count(vID) == 0) {
//                vector<HMesh::FaceID> faces;
//                faces.push_back(*fid);
//                dic_vertex_to_face.insert(pair<VertexID, vector<FaceID>>(vID, faces));
//            } else {
//                vector<HMesh::FaceID> faces = dic_vertex_to_face[vID];
//                faces.push_back(*fid);
//                dic_vertex_to_face[vID] = faces;
//            }
            
        }
        
//        //add wireframe data
//        ColorRGBA wireframeColor = {0,0,0,255};
//        if (vertexNum == 3 || vertexNum == 4) {
//            facet[0].color = wireframeColor;
//            facet[1].color = wireframeColor;
//            facet[2].color = wireframeColor;
//            
//            [*wireframe appendBytes:&facet[0] length:sizeof(VertexNormRGBA)];
//            [*wireframe appendBytes:&facet[1] length:sizeof(VertexNormRGBA)];
//            [*wireframe appendBytes:&facet[1] length:sizeof(VertexNormRGBA)];
//            [*wireframe appendBytes:&facet[2] length:sizeof(VertexNormRGBA)];
//            if (vertexNum == 3) {
//                [*wireframe appendBytes:&facet[2] length:sizeof(VertexNormRGBA)];
//                [*wireframe appendBytes:&facet[0] length:sizeof(VertexNormRGBA)];
//            } else if (vertexNum == 4) {
//                facet[3].color = wireframeColor;
//                [*wireframe appendBytes:&facet[2] length:sizeof(VertexNormRGBA)];
//                [*wireframe appendBytes:&facet[3] length:sizeof(VertexNormRGBA)];
//                [*wireframe appendBytes:&facet[3] length:sizeof(VertexNormRGBA)];
//                [*wireframe appendBytes:&facet[0] length:sizeof(VertexNormRGBA)];
//            }
//        }
    }
    
    _edgeInfo = trace_spine_edges(_manifold);
}

-(void)subBufferForVertexIDs:(vector<HMesh::VertexID>)vector_of_vid mani:(HMesh::Manifold) mani mappedData:(GLvoid*)ptr {
    
    for (HalfEdgeID hID: _edges_to_scale) {
        scaled_pos_for_rib(_manifold, hID, _edgeInfo, _accumScale, _current_scale_position);
        //            vector<VertexID> vector_vid = change_rib_radius(_manifold, hID, k);
        //            _all_vector_vid.insert(_all_vector_vid.end(), vector_vid.begin(), vector_vid.end());
    }
    
    set<FaceID> set_of_faces;
    
    //Add all faces that are affected by the verticies
    for (VertexID vid: vector_of_vid) {
        if (dic_vertex_to_face.count(vid) >0 ) {
            vector<FaceID>vector_of_faces = dic_vertex_to_face[vid];
            for (FaceID fid: vector_of_faces) {
                set_of_faces.insert(fid);
            }
        } else {
            NSLog(@"[ERROR][QuadPolygonMesh][subBufferForVertexID:] unkown vertex id");
        }
    }
    
    //Update the mesh
    for (FaceID fid: set_of_faces) {
        NSMutableData* verticies = [[NSMutableData alloc] init];
        int vertexNum = 0;
        VertexNormRGBA facet[4];
        
//        Vec norm = HMesh::normal(mani, fid);
        Vec norm = Vec(0,0,0);
        PositionXYZ normGL = {(GLfloat)norm[0], (GLfloat)norm[1], (GLfloat)norm[2]};
        
        ColorRGBA vertexColor = {200,200,200,255};
        
        //iterate over every vertex of the face
        for(Walker w = mani.walker(fid); !w.full_circle(); w = w.circulate_face_ccw()) {
            
            //            Vec norm = HMesh::normal(mani, w.vertex());
            //            PositionXYZ normGL = {(GLfloat)norm[0], (GLfloat)norm[1], (GLfloat)norm[2]};
            
            //add vertex to the data array
            VertexID vID = w.vertex();
            Vec c = mani.pos(vID);
            for (VertexID v: vector_of_vid) {
                if (v == vID) {
                    c = _current_scale_position[vID];
                    break;
                }
            }
            
//            Vec c = _current_scale_position[vID];
            PositionXYZ positionDCM = {(GLfloat)c[0], (GLfloat)c[1], (GLfloat)c[2]};
            VertexNormRGBA vertexMono = {positionDCM, normGL, vertexColor};
            
            facet[vertexNum] = vertexMono;
            vertexNum++;
            
            if (vertexNum == 4) {
                //Create a second triangle
                [verticies appendBytes:&facet[0] length:sizeof(VertexNormRGBA)];
                [verticies appendBytes:&facet[2] length:sizeof(VertexNormRGBA)];
            }
            [verticies appendBytes:&vertexMono length:sizeof(VertexNormRGBA)];
        }
        
        unsigned long offset = dic_face_to_buffer[fid];
//        NSRange range = {offset, verticies.length};
        memcpy(((char*)ptr) + offset, verticies.bytes, verticies.length);
//        [self.meshData replaceBytesInRange:range withBytes:verticies.bytes];
//        [self.vertexDataBuffer bufferSubDataWithOffset:offset size:verticies.length data:verticies.bytes];
    }
}

-(BoundingBox)boundingBox {
    return _boundingBox;
}

-(void)saveState {
    undoMani = _manifold;
}

#pragma mark - CREATING A BRANCH WHEN TOUCHED OUTSIDE OF MODEL

-(void)branchCreateMovementStart:(GLKVector3)touchPoint {
    
    mousePoint = [Utilities invertVector3:touchPoint withMatrix:self.modelMatrix];;
}

-(void)branchCreateMovementEnd:(GLKVector3)touchPoint {
    [self saveState];
    touchPoint = [Utilities invertVector3:touchPoint withMatrix:self.modelMatrix];
    
    GLKVector3 mousePoint_inView_3 = GLKMatrix4MultiplyVector3Custom(self.modelViewMatrix, mousePoint);
    VertexID vID = [self closestVertexID_2DProjection:GLKVector2Make(mousePoint_inView_3.x, mousePoint_inView_3.y)];
    Vec norm = normalize(HMesh::normal(_manifold, vID));
    
//    GLKVector3 touchPoint_inView_3 = touchPoint;//GLKMatrix4MultiplyVector3Custom(self.viewMatrix, touchPoint);
//    GLKVector2 touchPoint_inView_2 = GLKVector2Make(touchPoint_inView_3.x, touchPoint_inView_3.y);
//    Vec2d displace2d = Vec2d(touchPoint_inView_2.x - mousePoint_inView_2.x, touchPoint_inView_2.y - mousePoint_inView_2.y);
    Vec displace = Vec(touchPoint.x - mousePoint.x, touchPoint.y - mousePoint.y, touchPoint.z - mousePoint.z);

    VertexID newPoleID;
    Vec mouseVertex = _manifold.pos(vID);
    BOOL result = [self createBranchAtPoint:GLKVector3Make(mouseVertex[0], mouseVertex[1], mouseVertex[2])
                                      width:self.branchWidth
                                   vertexID:&newPoleID];
    if (result) {
        HMesh::VertexAttributeVector<int> poles(_manifold.no_vertices(), 0);
        poles[newPoleID] = 1;
//        refine_poles(_manifold, poles);

        Vec displace3d =  norm * displace.length();
        
        // Move pole
        _manifold.pos(newPoleID) = _manifold.pos(newPoleID) + displace3d;
        
        // Move vertecies adjacent to pole
        for (Walker walker = _manifold.walker(newPoleID); !walker.full_circle(); walker = walker.circulate_vertex_ccw()) {
            _manifold.pos(walker.vertex()) = _manifold.pos(walker.vertex()) + displace3d*0.95f;
        }
        
        //Add ribs for the new branch
        Walker walker = _manifold.walker(newPoleID);
        HalfEdgeID ID_1 = walker.next().opp().next().halfedge();
        recursively_add_rib(_manifold, ID_1, 5, _edgeInfo);

        [self rebuffer];
    }
}

#pragma mark - CREATING A BRANCH WHEN TOUCHED INSIDE OF MODEL

-(void)gaussianStart:(GLKVector3)touchPoint {
    touchPoint = [Utilities invertVector3:touchPoint withMatrix:self.modelMatrix];
    Vec p0 = Vec(touchPoint.x, touchPoint.y, touchPoint.z);
    float brush_size = 0.001;
    mousePoint = touchPoint;
    old_mani = _manifold;
    Vec c;
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
    Vec displace = Vec(touchPoint.x - mousePoint.x, touchPoint.y - mousePoint.y, touchPoint.z - mousePoint.z);

    VertexID vID = [self closestVertexID:mousePoint];
    Vec norm = HMesh::normal(_manifold, vID);
    
//    float angle = acos(dot(normalize(displace), normalize(norm)));
    Vec c;
    float r;
    bsphere(_manifold, c, r);
    
    if (length(displace) > r*0.05) {
//        NSLog(@"MOVED PERPENDICULAR WAS %f", GLKMathRadiansToDegrees(angle));
        VertexID newPoleID;
        Vec mouseVertex = _manifold.pos(vID);

        BOOL result = [self createBranchAtPoint:GLKVector3Make(mouseVertex[0], mouseVertex[1], mouseVertex[2]) width:self.branchWidth vertexID:&newPoleID];
        if (result) {
            HMesh::VertexAttributeVector<int> poles(_manifold.no_vertices(), 0);
            poles[newPoleID] = 1;
//            refine_poles(_manifold, poles);
            
//            float proj = dot(norm, displace)/length(norm);
            displace = norm * displace.length();
            
            // Move pole
            _manifold.pos(newPoleID) = _manifold.pos(newPoleID) + displace;
            
            // Move vertecies adjacent to pole
            for (Walker walker = _manifold.walker(newPoleID); !walker.full_circle(); walker = walker.circulate_vertex_ccw()) {
                _manifold.pos(walker.vertex()) = _manifold.pos(walker.vertex()) + displace*0.95f;
            }
            
            //Add ribs for the new branch
            Walker walker = _manifold.walker(newPoleID);
            HalfEdgeID ID_1 = walker.next().opp().next().halfedge();
            recursively_add_rib(_manifold, ID_1, 5, _edgeInfo);
//            HalfEdgeID ID_2 = add_rib(_manifold, ID_1);
//            add_rib(_manifold, ID_1);
//            add_rib(_manifold, ID_2);
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

#pragma mark - BENDING

//Touch point in VIEW coordinates. Return true if you can begin bending
-(BOOL)bendBranchBeginWithFirstTouchRayOrigin:(GLKVector3)rayOrigin
                                 rayDirection:(GLKVector3)rayDirection
                             secondTouchPoint:(GLKVector3)touchPoint
{
//    _branchBendFaceID = [self closestFaceID_2DProjection:bendingPivot];
    _firstTouchedFace = [self pickFace:&_branchBendFaceID
                            rayOrigin:rayOrigin
                         rayDirection:rayDirection];
    _branchBendingInitialPoint = touchPoint;
    
    return _firstTouchedFace;
}

//Touch point in VIEW coordinates
-(void)bendBranchEnd:(GLKVector3)touchPoint {
    if (!_firstTouchedFace) return;
    [self saveState];
    Walker w = _manifold.walker(_branchBendFaceID);
    
    if (_edgeInfo[w.halfedge()].edge_type == RIB) {
        w = w.next(); //spine
    }
    
    assert(_edgeInfo[w.halfedge()].edge_type == SPINE);
    
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
    vector<Vec> centroids;
    Walker spineWalker = _manifold.walker(poleDirectionHalfEdge);
    spineWalker = spineWalker.next().opp().next(); //advance to the next spine
    for (; !is_pole(_manifold, spineWalker.vertex()); spineWalker = spineWalker.next().opp().next())
    {
        assert(_edgeInfo[spineWalker.next().halfedge()].edge_type == RIB);
        
        vector<VertexID> vIDs;
        Vec centroid = Vec(0,0,0);
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
            Vec v_pos = _manifold.pos(vID);
            GLKVector3 v_pos_glk_model = GLKVector3MakeWithVec(v_pos);
            GLKVector3 v_pos_glk_world = GLKMatrix4MultiplyVector3Custom(self.modelViewMatrix, v_pos_glk_model);
            v_pos_glk_world.x += weight * displacement.x;
            v_pos_glk_world.y += weight * displacement.y;
            v_pos_glk_model = [Utilities invertVector3:v_pos_glk_world withMatrix:self.modelViewMatrix];
            v_pos = Vec(v_pos_glk_model.x, v_pos_glk_model.y, v_pos_glk_model.z);
            _manifold.pos(vID) = v_pos;
        }
    }
    [self rebuffer];
}

#pragma mark - SCALING

-(void)beginScalingRibsWithRayOrigin1:(GLKVector3)rayOrigin1
                           rayOrigin2:(GLKVector3)rayOrigin2
                        rayDirection1:(GLKVector3)rayDir1
                        rayDirection2:(GLKVector3)rayDir2
{
    BOOL hit1 = [self pickFace:&_scaleRibFace1 rayOrigin:rayOrigin1 rayDirection:rayDir1];
    BOOL hit2 = [self pickFace:&_scaleRibFace2 rayOrigin:rayOrigin2 rayDirection:rayDir2];
    
    _shouldBeginRibScaling = NO;
    if (hit1 && hit2) {
        if (_scaleRibFace1 != _scaleRibFace2) { //dont scale same faces
            _shouldBeginRibScaling = YES;
        }
    }
    
    Walker w1 = _manifold.walker(_scaleRibFace1);
    Walker w2 = _manifold.walker(_scaleRibFace2);
    
    //TODO handle triangles
    
    if (_edgeInfo[w1.halfedge()].edge_type != SPINE) {
        w1 = w1.next();
    }
    assert(_edgeInfo[w1.halfedge()].edge_type == SPINE);
    
    if (_edgeInfo[w2.halfedge()].edge_type != SPINE) {
        w2 = w2.next();
    }
    assert(_edgeInfo[w2.halfedge()].edge_type == SPINE);
    
    //test which direction to go from face1 to reach face2
    //i.e. find out rib edges in between fingers
    Vec w1pos1 = _manifold.pos(w1.vertex());
    Vec w1pos2 = _manifold.pos(w1.opp().vertex());
    Vec w2pos1 = _manifold.pos(w2.vertex());
    Vec w2pos2 = _manifold.pos(w2.opp().vertex());
    
    if ((w1pos2 - w2pos1).length() < (w1pos1 - w2pos1).length()) {
        //w1.opp is closer
        w1 = w1.opp();
    }
    
    if ((w2pos2 - w1pos1).length() < (w2pos1 - w1pos1).length()) {
        //w2.opp is closer
        w2 = w2.opp();
    }
    
    HalfEdgeID finalRib = w2.next().halfedge();
    
//    Manifold temp_mani = _manifold;
    _edges_to_scale.clear();
    _all_vector_vid.clear();
//    vector<VertexID> all_vector_vid;
    while (!lie_on_same_rib(_manifold, w1.next().halfedge(), finalRib, _edgeInfo)) {
        _edges_to_scale.push_back(w1.next().halfedge());
        vector<VertexID> vector_vid = verticies_along_the_rib(_manifold, w1.next().halfedge(), _edgeInfo);
        _all_vector_vid.insert(_all_vector_vid.end(), vector_vid.begin(), vector_vid.end());
        w1 =  w1.next().opp().next();
    }
    _edges_to_scale.push_back(w1.next().halfedge());
    vector<VertexID> vector_vid = verticies_along_the_rib(_manifold, w1.next().halfedge(), _edgeInfo); //last one
    _all_vector_vid.insert(_all_vector_vid.end(), vector_vid.begin(), vector_vid.end());
    
    _current_scale_position = VertexAttributeVector<Vec>(_manifold.no_vertices());
    
//    [self rebuffer];
//    [self subBufferForVertexIDs:all_vector_vid mani:_manifold];


    NSLog(@"Finished calling begin scalling funtion");
    
//    touchPoint = [Utilities invertVector3:touchPoint withMatrix:self.modelMatrix];
//    VertexID vID = [self closestVertexID:touchPoint];
//    Walker w = _manifold.walker(vID);
//    if (_edgeInfo[w.halfedge()].edge_type != RIB) {
//        w = w.prev();
//    }
//    assert(_edgeInfo[w.halfedge()].edge_type == RIB);
//    
//    change_rib_radius(_manifold, w.halfedge(), scale);
//    [self rebuffer];
}

-(void)changeScalingRibsWithScaleFactor:(float)scale {
//    NSLog(@"Pumpmpm");
    
   
    if (!_shouldBeginRibScaling) {
        return;
    }
//    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0ul);
//    dispatch_async(queue, ^{
//        float k;
//        if (scale < 1)
//            k = 0.9;
//        else
//            k = 1.1;

        _accumScale = scale;
//        for (HalfEdgeID hID: _edges_to_scale) {
//            scaled_pos_for_rib(_manifold, hID, _edgeInfo, scale, _current_scale_position);
////            vector<VertexID> vector_vid = change_rib_radius(_manifold, hID, k);
////            _all_vector_vid.insert(_all_vector_vid.end(), vector_vid.begin(), vector_vid.end());
//        }
    //    [self rebuffer];

//    });
    
//
//        Walker w1 = _manifold.walker(_scaleRibFace1);
//        Walker w2 = _manifold.walker(_scaleRibFace2);
//        
//        //TODO handle triangles
//        
//        if (_edgeInfo[w1.halfedge()].edge_type != SPINE) {
//            w1 = w1.next();
//        }
//        assert(_edgeInfo[w1.halfedge()].edge_type == SPINE);
//        
//        if (_edgeInfo[w2.halfedge()].edge_type != SPINE) {
//            w2 = w2.next();
//        }
//        assert(_edgeInfo[w2.halfedge()].edge_type == SPINE);
//        
//        //test which direction to go from face1 to  reach face2
//        //i.e. find out rib edges in between fingers
//        Vec w1pos1 = _manifold.pos(w1.vertex());
//        Vec w1pos2 = _manifold.pos(w1.opp().vertex());
//        Vec w2pos1 = _manifold.pos(w2.vertex());
//        Vec w2pos2 = _manifold.pos(w2.opp().vertex());
//        
//        if ((w1pos2 - w2pos1).length() < (w1pos1 - w2pos1).length()) {
//            //w1.opp is closer
//            w1 = w1.opp();
//        }
//        
//        if ((w2pos2 - w1pos1).length() < (w2pos1 - w1pos1).length()) {
//            //w2.opp is closer
//            w2 = w2.opp();
//        }
//        
//        HalfEdgeID finalRib = w2.next().halfedge();
//        
//        Manifold temp_mani = _manifold;
//        
//        vector<VertexID> all_vector_vid;
//        while (!lie_on_same_rib(temp_mani, w1.next().halfedge(), finalRib, _edgeInfo)) {
//            vector<VertexID> vector_vid = change_rib_radius(temp_mani, w1.next().halfedge(), scale);
//            all_vector_vid.insert(all_vector_vid.end(), vector_vid.begin(), vector_vid.end());
//            w1 =  w1.next().opp().next();
//        }
//        vector<VertexID> vector_vid =change_rib_radius(temp_mani, w1.next().halfedge(), scale); //last one
//        all_vector_vid.insert(all_vector_vid.end(), vector_vid.begin(), vector_vid.end());
//        
//        //    [self rebuffer];
//        [self subBufferForVertexIDs:all_vector_vid mani:temp_mani];

    
}

-(void)endScalingRibsWithScaleFactor:(float)scale {

    if (!_shouldBeginRibScaling) {
        return;
    }
    
    for (HalfEdgeID hID: _edges_to_scale) {
        change_rib_radius(_manifold, hID, _edgeInfo, scale);
//        scaled_pos_for_rib(_manifold, hID, _edgeInfo, scale, _current_scale_position);
    }

    _edges_to_scale.clear();
    _all_vector_vid.clear();
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
    Vec norm = HMesh::normal(_manifold, vID);
    
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
    Vec c;
    float r;
    bsphere(_manifold, c, r);
    [self moveVertexCloseTo:touchPoint orthogonallyBy:r * 0.05];
}

#pragma mark - DRAWING

-(void)draw {

//    NSLog(@"Draw");
    
//    if (current_buffer == 0) current_buffer = 1; else current_buffer = 0;

    if (current_buffer == 0) {
        [self.vertexDataBuffer bind];
    } else {
        [self.doubleVertexBuffer bind];
    }
    
    glBufferData(GL_ARRAY_BUFFER, self.meshData.length, NULL, GL_DYNAMIC_DRAW);
    GLvoid* temp = glMapBufferOES(GL_ARRAY_BUFFER, GL_WRITE_ONLY_OES);
    [self subBufferForVertexIDs:_all_vector_vid mani:_manifold mappedData:temp];
//    memcpy(temp, self.meshData.bytes, self.meshData.length);
    glUnmapBufferOES(GL_ARRAY_BUFFER);
    
    glUseProgram(self.drawShaderProgram.program);
    glUniformMatrix4fv(uniforms[UNIFORM_MODELVIEWPROJECTION_MATRIX], 1, 0, self.modelViewProjectionMatrix.m);
    glUniform4f(uniforms[UNIFORM_LIGHT_DIRECTION], 0.0, 0.0, 0.0, 1.0);
    glUniform4f(uniforms[UNIFORM_LIGHT_COLOR], 1.0, 1.0, 1.0, 1.0);
    if (current_buffer == 0) {
        [self.doubleVertexBuffer bind];
        [self.doubleVertexBuffer prepareToDrawWithAttrib:attrib[ATTRIB_POSITION]
                                   numberOfCoordinates:3
                                          attribOffset:0
                                              dataType:GL_FLOAT
                                             normalize:GL_FALSE];
        
        [self.doubleVertexBuffer prepareToDrawWithAttrib:attrib[ATTRIB_NORMAL]
                                   numberOfCoordinates:3
                                          attribOffset:sizeof(PositionXYZ)
                                              dataType:GL_FLOAT
                                             normalize:GL_FALSE];
        
        [self.doubleVertexBuffer prepareToDrawWithAttrib:attrib[ATTRIB_COLOR]
                                   numberOfCoordinates:4
                                          attribOffset:2*sizeof(PositionXYZ)
                                              dataType:GL_UNSIGNED_BYTE
                                             normalize:GL_TRUE];
    } else {
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
        
        [self.vertexDataBuffer prepareToDrawWithAttrib:attrib[ATTRIB_COLOR]
                                   numberOfCoordinates:4
                                          attribOffset:2*sizeof(PositionXYZ)
                                              dataType:GL_UNSIGNED_BYTE
                                             normalize:GL_TRUE];
    }

    current_buffer = !current_buffer;
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
    
    glBindBuffer(GL_ARRAY_BUFFER, 0);
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
    
    [AGLKVertexAttribArrayBuffer drawPreparedArraysWithMode:GL_TRIANGLES
                                           startVertexIndex:0
                                           numberOfVertices:self.numVertices];
}


@end
