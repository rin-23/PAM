//
//  PolarAnnularMesh.m
//  PAM
//
//  Created by Rinat Abdrashitov on 11/21/2013.
//  Copyright (c) 2013 Rinat Abdrashitov. All rights reserved.
//

#import "PolarAnnularMesh.h"
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
#import <OpenGLES/ES2/gl.h>
#import <OpenGLES/ES2/glext.h>

static int VERTEX_SIZE =  3 * sizeof(float);
static int COLOR_SIZE =  4 * sizeof(unsigned char);
static int INDEX_SIZE  = sizeof(unsigned int);

typedef enum {
    MODIFICATION_NONE,
    MODIFICATION_SCALING
} CurrentModification;

typedef CGLA::Vec3d Vec;
typedef CGLA::Vec3f Vecf;

using namespace HMesh;

@interface PolarAnnularMesh() {
    
    HMesh::Manifold _manifold;
    HMesh::HalfEdgeAttributeVector<EdgeInfo> _edgeInfo;
    BoundingBox _boundingBox;

    GLKVector3 _initialTouch;
    
    //Scaling of Rings
    HMesh::FaceID _scaleRibFace1;
    HMesh::FaceID _scaleRibFace2;
    float _scaleFactor;
    vector<float> _scale_weight_vector;
    HMesh::VertexAttributeVector<Vecf> _current_scale_position;
        
    //Selection
    vector<HMesh::HalfEdgeID> _edges_to_scale;
    vector<HMesh::VertexID> _all_vector_vid;
    vector<CGLA::Vec3f> _centroids;
    vector<GLKVector3> _touchPoints;
    
    //Undo
    HMesh::Manifold undoMani;
    
    CurrentModification modState;
}

@property (nonatomic) AGLKVertexAttribArrayBuffer* normalDataBuffer;
@property (nonatomic) AGLKVertexAttribArrayBuffer* colorDataBuffer;

@property (nonatomic) AGLKVertexAttribArrayBuffer* wireframeColorDataBuffer;
@property (nonatomic) AGLKVertexAttribArrayBuffer* wireframeIndexBuffer;
@property (nonatomic, assign) int wireframeNumOfIndicies;

@end

@implementation PolarAnnularMesh


//GLKVector3 GLKVector3MakeWithVec(Vec v) {
//    return GLKVector3Make(v[0], v[1], v[2]);
//}

-(id)init {
    self = [super init];
    if (self) {
        //Load shader
        NSString* vShader = [[NSBundle mainBundle] pathForResource:@"Shader" ofType:@"vsh"];
        NSString* fShader = [[NSBundle mainBundle] pathForResource:@"Shader" ofType:@"fsh"];
        self.drawShaderProgram = [[ShaderProgram alloc] initWithVertexShader:vShader fragmentShader:fShader];
        
        attrib[ATTRIB_POSITION] = [self.drawShaderProgram attributeLocation:"position"];
        attrib[ATTRIB_NORMAL] = [self.drawShaderProgram attributeLocation:"normal"];
        attrib[ATTRIB_COLOR] = [self.drawShaderProgram attributeLocation:"color"];
        
        uniforms[UNIFORM_MODELVIEWPROJECTION_MATRIX] = [self.drawShaderProgram uniformLocation:"modelViewProjectionMatrix"];
        uniforms[UNIFORM_NORMAL_MATRIX] = [self.drawShaderProgram uniformLocation:"normalMatrix"];
    }
    return self;
}

-(void)setMeshFromObjFile:(NSString*)objFilePath {

    _branchWidth = 1;
    modState = MODIFICATION_NONE;
    
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
    
    
    
    [self rebuffer];
}

-(void)rebuffer{
    //Load data
    NSMutableData* positionData = [[NSMutableData alloc] init];
    NSMutableData* normalData = [[NSMutableData alloc] init];
    NSMutableData* colorData = [[NSMutableData alloc] init];
    NSMutableData* indexData = [[NSMutableData alloc] init];
    
    NSMutableData* wireframeColorData = [[NSMutableData alloc] init];
    NSMutableData* wireframeIndexData = [[NSMutableData alloc] init];
    [self triangulateManifold:_manifold
               vertexPosition:&positionData
                 vertexNormal:&normalData
                  vertexColor:&colorData
                    indexData:&indexData
           wireframeColorData:&wireframeColorData 
           wireframeIndexData:&wireframeIndexData];
    
    //Buffer vertex data
    self.numVertices = positionData.length / VERTEX_SIZE;
    self.vertexDataBuffer = [[AGLKVertexAttribArrayBuffer alloc] initWithAttribStride:VERTEX_SIZE
                                                                     numberOfVertices:self.numVertices
                                                                                bytes:positionData.bytes
                                                                                usage:GL_DYNAMIC_DRAW
                                                                               target:GL_ARRAY_BUFFER];
    [self.vertexDataBuffer enableAttribute:attrib[ATTRIB_POSITION]];
    
    self.normalDataBuffer = [[AGLKVertexAttribArrayBuffer alloc] initWithAttribStride:VERTEX_SIZE
                                                                     numberOfVertices:self.numVertices
                                                                                bytes:normalData.bytes
                                                                                usage:GL_DYNAMIC_DRAW
                                                                               target:GL_ARRAY_BUFFER];
    [self.normalDataBuffer enableAttribute:attrib[ATTRIB_NORMAL]];
    
    self.colorDataBuffer = [[AGLKVertexAttribArrayBuffer alloc] initWithAttribStride:COLOR_SIZE
                                                                    numberOfVertices:self.numVertices
                                                                               bytes:colorData.bytes
                                                                               usage:GL_STATIC_DRAW
                                                                              target:GL_ARRAY_BUFFER];
    [self.colorDataBuffer enableAttribute:attrib[ATTRIB_COLOR]];
    
    
    self.wireframeColorDataBuffer = [[AGLKVertexAttribArrayBuffer alloc] initWithAttribStride:COLOR_SIZE
                                                                             numberOfVertices:self.numVertices
                                                                                        bytes:wireframeColorData.bytes
                                                                                        usage:GL_STATIC_DRAW
                                                                                       target:GL_ARRAY_BUFFER];
    [self.wireframeColorDataBuffer enableAttribute:attrib[ATTRIB_COLOR]];
    
    
    //Buffer index data
    self.numIndices = indexData.length / INDEX_SIZE;
    self.indexDataBuffer = [[AGLKVertexAttribArrayBuffer alloc] initWithAttribStride:INDEX_SIZE
                                                                    numberOfVertices:self.numIndices
                                                                               bytes:indexData.bytes
                                                                               usage:GL_STATIC_DRAW
                                                                              target:GL_ELEMENT_ARRAY_BUFFER];
    
    //Buffer index data
    self.wireframeNumOfIndicies = wireframeIndexData.length / INDEX_SIZE;
    self.wireframeIndexBuffer = [[AGLKVertexAttribArrayBuffer alloc] initWithAttribStride:INDEX_SIZE
                                                                         numberOfVertices:self.wireframeNumOfIndicies
                                                                                    bytes:wireframeIndexData.bytes
                                                                                    usage:GL_STATIC_DRAW
                                                                                   target:GL_ELEMENT_ARRAY_BUFFER];
    
    _edgeInfo = trace_spine_edges(_manifold);

}

//Triangulate manifold for display in case it has quads. GLES doesnt handle quads.
-(void)triangulateManifold:(HMesh::Manifold&)mani
            vertexPosition:(NSMutableData**)vertexPosition
              vertexNormal:(NSMutableData**)vertexNormal
               vertexColor:(NSMutableData**)vertexColor
                 indexData:(NSMutableData**)indexData
        wireframeColorData:(NSMutableData**)wireframeColor
        wireframeIndexData:(NSMutableData**)wireframeIndexData
{
    Vec4uc color(200,200,200,255);
    Vec4uc wColor(0, 0, 0, 255);
    
    for (VertexIDIterator vid = mani.vertices_begin(); vid != mani.vertices_end(); ++vid) {
        assert((*vid).index < mani.no_vertices());
        
        Vecf positionf = mani.posf(*vid);
        Vecf normalf = HMesh::normalf(_manifold, *vid);
        
        [*vertexPosition appendBytes:positionf.get() length:VERTEX_SIZE];
        [*vertexNormal appendBytes:normalf.get() length:VERTEX_SIZE];
        [*vertexColor appendBytes:color.get() length:COLOR_SIZE];
        [*wireframeColor appendBytes:wColor.get() length:COLOR_SIZE];
    }
    
    for (FaceIDIterator fid = mani.faces_begin(); fid != mani.faces_end(); ++fid) {
        int vertexNum = 0;
        unsigned int facet[4];
  
        //iterate over every vertex of the face
        for(Walker w = mani.walker(*fid); !w.full_circle(); w = w.circulate_face_ccw()) {
            //add vertex to the data array
            VertexID vID = w.vertex();
            unsigned int index = vID.index;
            
            assert(index < mani.no_vertices());
 
            facet[vertexNum] = index;
            vertexNum++;
            
            if (vertexNum == 4) {
                //Create a second triangle
                [*indexData appendBytes:&facet[0] length:INDEX_SIZE];
                [*indexData appendBytes:&facet[2] length:INDEX_SIZE];
            }
            [*indexData appendBytes:&index length:INDEX_SIZE];
        }
        
        //add wireframe data

        if (vertexNum == 3 || vertexNum == 4)
        {
            [*wireframeIndexData appendBytes:&facet[0] length:INDEX_SIZE];
            [*wireframeIndexData appendBytes:&facet[1] length:INDEX_SIZE];
            [*wireframeIndexData appendBytes:&facet[1] length:INDEX_SIZE];
            [*wireframeIndexData appendBytes:&facet[2] length:INDEX_SIZE];

            if (vertexNum == 3)
            {
                [*wireframeIndexData appendBytes:&facet[2] length:INDEX_SIZE];
                [*wireframeIndexData appendBytes:&facet[0] length:INDEX_SIZE];
            }
            else if (vertexNum == 4)
            {
                [*wireframeIndexData appendBytes:&facet[2] length:INDEX_SIZE];
                [*wireframeIndexData appendBytes:&facet[3] length:INDEX_SIZE];
                [*wireframeIndexData appendBytes:&facet[3] length:INDEX_SIZE];
                [*wireframeIndexData appendBytes:&facet[0] length:INDEX_SIZE];
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

-(void)undo {
    _manifold = undoMani;
}
#pragma mark - FIND VERTEX/FACE NEAR TOUCH POINT

-(VertexID)closestVertexID_2D:(GLKVector3)touchPoint {
    float distance = FLT_MAX;
    HMesh::VertexID closestVertex;
    
    //touchPoint to world coordinates
    touchPoint = [Utilities matrix4:self.viewMatrix multiplyVector3:touchPoint];
    GLKVector2 touchPoint2D = GLKVector2Make(touchPoint.x, touchPoint.y);
    
    for (VertexIDIterator vID = _manifold.vertices_begin(); vID != _manifold.vertices_end(); vID++) {
        Vec vertexPos = _manifold.pos(*vID);
        
        GLKVector4 glkVertextPos = GLKVector4Make(vertexPos[0], vertexPos[1], vertexPos[2], 1.0f);
        GLKVector4 glkVertextPosModelView = GLKMatrix4MultiplyVector4(self.modelViewMatrix, glkVertextPos);
        GLKVector2 glkVertextPosModelView_2 = GLKVector2Make(glkVertextPosModelView.x, glkVertextPosModelView.y);
        float cur_distance = GLKVector2Distance(touchPoint2D, glkVertextPosModelView_2);
        
        if (cur_distance < distance) {
            distance = cur_distance;
            closestVertex = *vID;
        }
    }
    return closestVertex;
}

-(VertexID)closestVertexID_3D:(GLKVector3)touchPoint {
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

-(FaceID)closestFaceForRayOrigin:(GLKVector3)rayOrigin direction:(GLKVector3)rayDirection didHitModel:(BOOL*)didHitModel
{
    FaceID closestFace;
    float closestFaceDistance = FLT_MAX;
    
    vector<FaceID> hitFaces;
    
    //Bring ray to the world space
    rayOrigin = [Utilities matrix4:self.viewMatrix multiplyVector3:rayOrigin];
    
    //rayDirection in View coordinates is pointing down the z axis. Original rayDirection doesnt preserve translation
    rayDirection = GLKVector3Make(0, 0, -1);
    
    //Iterate over every face and see if ray hits any
    for (FaceIDIterator fid = _manifold.faces_begin(); fid != _manifold.faces_end(); ++fid) {
        GLKVector3 faceVerticies[4];
        GLKVector3 centroid = GLKVector3Make(0, 0, 0);
        int num_edges = 0;

        for(Walker w = _manifold.walker(*fid); !w.full_circle(); w = w.circulate_face_cw()) {
            Vec v = _manifold.pos(w.vertex());
            //bring manifold vertex coordinates to world space
            GLKVector3 glV_world = [Utilities matrix4:self.modelViewMatrix multiplyVector3:GLKVector3Make(v[0], v[1], v[2])];

            centroid = GLKVector3Add(centroid, glV_world);
            faceVerticies[num_edges] = glV_world;
            num_edges++;
        }
        centroid = GLKVector3DivideScalar(centroid, num_edges);
        
        //Find the closest vertex based on centroid in 2D porjection
        float cur_distance = GLKVector2Distance(GLKVector2Make(rayOrigin.x, rayOrigin.y),
                                                GLKVector2Make(centroid.x, centroid.y));
        
        if  (cur_distance < closestFaceDistance) {
            closestFaceDistance = cur_distance;
            closestFace = *fid;
        }
        
        BOOL hit = NO;
        if (num_edges == 3) {
            hit = [Utilities hitTestTriangle:faceVerticies withRayStart:rayOrigin rayDirection:rayDirection];
        } else { //quad
            hit = [Utilities hitTestQuad:faceVerticies withRayStart:rayOrigin rayDirection:rayDirection];
        }
        
        if (hit) {
            hitFaces.push_back(*fid);
        }
    }
    
    if (hitFaces.size() == 0) {
        //Didn't hit any faces, so return the closest face
        if (didHitModel!=NULL)
            *didHitModel = NO;
        return closestFace;
    } else if (hitFaces.size() == 1) { //hit just one
        if (didHitModel!=NULL)
            *didHitModel = YES;
        return hitFaces[0];
    } else {
        if (didHitModel!=NULL)
            *didHitModel = YES;
        //sort the faces by depth. Return the closest to the viewer
        float farvestFaceDist = -1*FLT_MAX;
        FaceID farvestFaceID;
        for (FaceID fid: hitFaces) {
            Walker w = _manifold.walker(fid);
            Vec v = _manifold.pos(w.vertex());
            //bring manifold vertex coordinates to world space
            GLKVector3 glV_world = [Utilities matrix4:self.modelViewMatrix multiplyVector3:GLKVector3Make(v[0], v[1], v[2])];
            if  (glV_world.z >= farvestFaceDist ) {
                farvestFaceDist = glV_world.z;
                farvestFaceID = fid;
            }
        }
        
        return farvestFaceID;
    }
}


#pragma mark - BRANCH CREATION METHODS

//Create branch at a given vertex. Return VertexID of newly created pole.
-(BOOL)createBranchAtVertex:(VertexID)vID width:(int)width vertexID:(VertexID*)newPoleID {
    [self saveState];
    
    //Do not add branhes at poles
    if (is_pole(_manifold, vID)) {
        NSLog(@"[WARNING]Tried to create a branch at a pole");
        return NO;
    }
    
    //Find rib halfedge that points to a given vertex
    Walker walker = _manifold.walker(vID);
    if (_edgeInfo[walker.halfedge()].edge_type == SPINE) {
        walker = walker.prev();
    }
    assert(_edgeInfo[walker.halfedge()].edge_type == RIB); //its a rib
    assert(walker.vertex() == vID); //points to a given vertex
    
    //Check that rib ring has enough verticeis to accomodate branch width
    int num_of_rib_verticies = 0;
    for (Walker ribWalker = _manifold.walker(walker.halfedge());
         !ribWalker.full_circle();
         ribWalker = ribWalker.next().opp().next(), num_of_rib_verticies++);

    if (num_of_rib_verticies < 2*width + 1) {
        NSLog(@"[WARNING]Not enough points to create branh");
        return NO;
    }
    
    VertexAttributeVector<int> vs(_manifold.no_vertices(), 0);
    vs[vID] = 1;
    
    vector<VertexID> ribs;

    //walk right
    int num_rib_found = 0;
    for (Walker ribWalker = walker.next().opp().next();
         num_rib_found < width;
         ribWalker = ribWalker.next().opp().next(), num_rib_found++)
    {
        ribs.push_back(ribWalker.vertex());
    }
    
    //walk left
    num_rib_found = 0;
    for (Walker ribWalker = walker.opp();
         num_rib_found < width;
         ribWalker = ribWalker.next().opp().next(), num_rib_found++)
    {
        ribs.push_back(ribWalker.vertex());
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

#pragma mark - TOUCHES: BRANCH CREATION ONE FINGER

-(void)startCreateBranch:(GLKVector3)touchPoint {
    _touchPoints.clear();
    _touchPoints.push_back(touchPoint);
    _initialTouch = touchPoint;
}

-(void)continueCreateBranch:(GLKVector3)touchPoint {
    _touchPoints.push_back(touchPoint);
}

-(void)endCreateBranch:(GLKVector3)touchPoint touchedModel:(BOOL)touchedModel{
    [self saveState];
 
    VertexID touchedVID;
    if (touchedModel) {
        //closest vertex in 3D space
        touchedVID = [self closestVertexID_3D:_initialTouch];
    } else {
        //closest vertex in 2D space
        touchedVID = [self closestVertexID_2D:_initialTouch];
    }

    Vec norm = HMesh::normal(_manifold, touchedVID);
    float displace = GLKVector3Length(GLKVector3Subtract(touchPoint, _initialTouch));
    NSLog(@"displace %f", displace);
    Vec displace3d =  displace * norm ;
    
    VertexID newPoleID;
    BOOL result = [self createBranchAtVertex:touchedVID width:self.branchWidth vertexID:&newPoleID];
    if (result) {
        //add rib araound the pole
        add_rib(_manifold, _manifold.walker(newPoleID).halfedge(), _edgeInfo);
        
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

#pragma mark - TOUCHES: BRANCH CREATION TWO FINGERS

-(void)startCreateBranchFinger1:(GLKVector3)touchPoint1 finger2:(GLKVector3)touchPoint2 {
    _touchPoints.clear();
    _touchPoints.push_back(touchPoint1);
    _touchPoints.push_back(touchPoint2);
}

-(void)continueCreateBranchFinger1:(GLKVector3)touchPoint1 finger2:(GLKVector3)touchPoint2 {
    _touchPoints.push_back(touchPoint1);
    _touchPoints.push_back(touchPoint2);
}

-(std::vector<GLKVector3>)endCreateBranchTwoFingers {
    
    //TODO NOT DONE YET
    [self saveState];
    
    if (_touchPoints.size() < 8) {
        NSLog(@"[PolarAnnularMesh][WARNING] Not enough touch points given");
    }
    
    //closest to the first centroid between two fingers vertex in 2D space
    GLKVector3 firstCentroid = GLKVector3Lerp(_touchPoints[0], _touchPoints[1], 0.5f);
    VertexID touchedVID = [self closestVertexID_2D:firstCentroid];
    Vecf touchedV = _manifold.posf(touchedVID);
    GLKVector3 touchedV_world = [Utilities matrix4:self.modelViewMatrix
                                   multiplyVector3:GLKVector3Make(touchedV[0], touchedV[1], touchedV[2])];
    
    assert(_touchPoints.size()%2 == 0);
    
    float sampleLen = 0.2f; //TODO:Should be base on current bbox
    float accumLen = 0.0f;
    GLKVector3 lastCentroid = firstCentroid;
    vector<GLKVector3> skeleton;
    vector<float> skeletonWidth;
    
    //Add first centroid
    GLKVector3 centroid_world = [Utilities matrix4:self.viewMatrix multiplyVector3:firstCentroid];
    centroid_world.z = touchedV_world.z;
    GLKVector3 centroid_model = [Utilities invertVector3:centroid_world withMatrix:self.modelViewMatrix];
    skeleton.push_back(centroid_model);
    skeletonWidth.push_back(0.5f * GLKVector3Distance(_touchPoints[0], _touchPoints[1]));
    
    //Add all other centroids
    for (int i = 2; i < _touchPoints.size(); i +=2) {
        GLKVector3 centroid = GLKVector3Lerp(_touchPoints[i], _touchPoints[i+1], 0.5f);
        float curLen = GLKVector3Distance(lastCentroid, centroid);
        accumLen += curLen;
        if (accumLen >= sampleLen) {
            centroid_world = [Utilities matrix4:self.viewMatrix multiplyVector3:centroid];
            centroid_world.z = touchedV_world.z;
            centroid_model = [Utilities invertVector3:centroid_world withMatrix:self.modelViewMatrix];
            skeleton.push_back(centroid_model);
            skeletonWidth.push_back(0.5f * GLKVector3Distance(_touchPoints[i], _touchPoints[i+1]));
            
            accumLen = 0;
            lastCentroid = centroid;
        }
    }
    
    return skeleton;
}


-(std::vector<vector<GLKVector3>>)endCreateNewBodyTwoFingers {
    
    if (_touchPoints.size() < 8) {
        NSLog(@"[PolarAnnularMesh][WARNING] Not enough touch points given");
    }
    
    [self saveState];
    
    //closest to the first centroid between two fingers vertex in 2D space
    GLKVector3 firstCentroid = GLKVector3Lerp(_touchPoints[0], _touchPoints[1], 0.5f);
    assert(_touchPoints.size()%2 == 0);
    
    float sampleLen = 0.4f;
    float accumLen = 0.0f;
    GLKVector3 lastCentroid = firstCentroid;
    vector<GLKVector3> skeleton;
    vector<GLKVector3> skeletonWorld;
    vector<float> skeletonWidth;
    
    //Add first centroid
    GLKVector3 centroid_world = [Utilities matrix4:self.viewMatrix multiplyVector3:firstCentroid];
    centroid_world.z = 0;
    GLKVector3 centroid_model = [Utilities invertVector3:centroid_world withMatrix:self.modelViewMatrix];
    skeleton.push_back(centroid_model);
    skeletonWorld.push_back(centroid_world);
    skeletonWidth.push_back(0.5f * GLKVector3Distance(_touchPoints[0], _touchPoints[1]));
    
    //Add all other centroids
    for (int i = 2; i < _touchPoints.size(); i +=2) {
        GLKVector3 centroid = GLKVector3Lerp(_touchPoints[i], _touchPoints[i+1], 0.5f);
        float curLen = GLKVector3Distance(lastCentroid, centroid);
        accumLen += curLen;

        if (accumLen >= sampleLen) {
            centroid_world = [Utilities matrix4:self.viewMatrix multiplyVector3:centroid];
            centroid_world.z = 0;
            centroid_model = [Utilities invertVector3:centroid_world withMatrix:self.modelViewMatrix];
            skeleton.push_back(centroid_model);
            skeletonWorld.push_back(centroid_world);
            skeletonWidth.push_back(0.5f * GLKVector3Distance(_touchPoints[i], _touchPoints[i+1]));
            
            accumLen = 0;
            lastCentroid = centroid;
        }
    }
    
    if (skeleton.size() < 4 ) {
        NSLog(@"[PolarAnnularMesh][WARNING] Not enough controids");
    }
    
    //Parse new skeleton and create ribs
    //Ingore first and last centroids since they are poles
    int numSpines = 10;
    vector<vector<GLKVector3>> allRibs(skeleton.size());
    vector<GLKVector3> firstPole;
    firstPole.push_back(skeleton[0]);
    allRibs[0] = firstPole;
    BOOL isFirstLeft = YES;
    for (int i = 1; i < skeleton.size() - 1; i++) {
        GLKVector3 tangent = GLKVector3Subtract(skeleton[i+1], skeleton[i-1]); //i-1
        GLKVector3 firstHalf = GLKVector3Subtract(skeleton[i], skeleton[i-1]); //i-1
        GLKVector3 proj = [Utilities projectVector:firstHalf ontoLine:tangent]; //i-1
        GLKVector3 norm = GLKVector3Normalize(GLKVector3Subtract(proj, firstHalf)); //i
        
        //Make sure than norm points to the left
        {
            GLKVector3 tangentWolrd = GLKVector3Subtract(skeletonWorld[i+1], skeletonWorld[i-1]);
            GLKVector3 firstHalfWorld = GLKVector3Subtract(skeletonWorld[i], skeletonWorld[i-1]); //i-1
            BOOL isLeft = ((tangentWolrd.x)*(firstHalfWorld.y) - (tangentWolrd.y)*(firstHalfWorld.x)) > 0;

            if (isFirstLeft != isLeft) {
                norm = GLKVector3MultiplyScalar(norm, -1);
            }
        }
        
        float ribWidth = skeletonWidth[i];

        vector<GLKVector3> ribs(numSpines);
        float rot_step = 360.0f/numSpines;
        for (int j = 0; j < numSpines; j++) {
            float angle = j * rot_step;
            GLKQuaternion quat = GLKQuaternionMakeWithAngleAndVector3Axis(GLKMathDegreesToRadians(angle), GLKVector3Normalize(tangent));
            GLKVector3 newNorm = GLKQuaternionRotateVector3(quat, norm);
            GLKVector3 newRibPoint = GLKVector3Add(GLKVector3MultiplyScalar(newNorm, ribWidth), skeleton[i]);
            ribs[j] = newRibPoint;
        }
        allRibs[i] = ribs;
    }
    vector<GLKVector3> secondPole;
    secondPole.push_back(skeleton[skeleton.size() - 1]);
    allRibs[skeleton.size() - 1] = secondPole;
    allRibs.push_back(skeleton);
    
    return allRibs;
}

#pragma mark - TOUCHES: FACE PICKING

-(void)endSelectFaceWithRay:(GLKVector3)rayOrigin rayDirection:(GLKVector3)rayDir
{
    BOOL didHitModel;
    FaceID fid = [self closestFaceForRayOrigin:rayOrigin direction:rayDir didHitModel:&didHitModel];
    if (didHitModel) {
        [self changeFaceColorToSelected:fid toSelected:YES];
    }
}


#pragma mark - TOUCHES: SCALING
-(void)startScalingRibsWithRayOrigin1:(GLKVector3)rayOrigin1
                           rayOrigin2:(GLKVector3)rayOrigin2
                        rayDirection1:(GLKVector3)rayDir1
                        rayDirection2:(GLKVector3)rayDir2
                                scale:(float)scale
{
    _scaleRibFace1 = [self closestFaceForRayOrigin:rayOrigin1 direction:rayDir1 didHitModel:NULL];
    _scaleRibFace2 = [self closestFaceForRayOrigin:rayOrigin2 direction:rayDir2 didHitModel:NULL];
    
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

    _edges_to_scale.clear();
    _all_vector_vid.clear();

    while (!lie_on_same_rib(_manifold, w1.next().halfedge(), finalRib, _edgeInfo)) {
        _edges_to_scale.push_back(w1.next().halfedge());
        vector<VertexID> vector_vid = verticies_along_the_rib(_manifold, w1.next().halfedge(), _edgeInfo);
        _all_vector_vid.insert(_all_vector_vid.end(), vector_vid.begin(), vector_vid.end());
        w1 =  w1.next().opp().next();
    }
    _edges_to_scale.push_back(w1.next().halfedge());
    vector<VertexID> vector_vid = verticies_along_the_rib(_manifold, w1.next().halfedge(), _edgeInfo); //last one
    _all_vector_vid.insert(_all_vector_vid.end(), vector_vid.begin(), vector_vid.end());

    _current_scale_position = VertexAttributeVector<Vecf>(_manifold.no_vertices());
    
    _scaleFactor = scale;
    
    //Calculate centroids and gaussian weights
    _centroids = centroid_for_ribs(_manifold, _edges_to_scale, _edgeInfo);
    Vec3f base;
    if (_centroids.size() % 2 == 0) {
        Vec3f b1 = _centroids[_centroids.size()/2 -1];
        Vec3f b2 = _centroids[_centroids.size()/2];
        base = 0.5*(b1 + b2);
    } else {
        base = _centroids[_centroids.size()/2];
    }
    
    
    _scale_weight_vector.clear();
    if (_centroids.size() == 1) {
        _scale_weight_vector.push_back(1.0f);
    } else {
        float r = (base - _centroids[0]).length();
        for(int i = 0; i < _centroids.size(); i++)
        {
            CGLA::Vec3f c = _centroids[i];
            float l = sqr_length(base - c);
            _scale_weight_vector.push_back(exp(-l/(2*r*r)));
        }
    }
    


    
    modState = MODIFICATION_SCALING;
    [self changeFacesColor:_all_vector_vid toSelected:YES];
    
    NSLog(@"Finished calling begin scalling funtion");
}

-(void)changeScalingRibsWithScaleFactor:(float)scale {
    _scaleFactor = scale;
}

-(void)endScalingRibsWithScaleFactor:(float)scale {
    
    for (int i = 0; i < _edges_to_scale.size(); i++) {
        change_rib_radius(_manifold, _edges_to_scale[i], _centroids[i], _edgeInfo, 1 + (_scaleFactor - 1)*_scale_weight_vector[i]); //update _manifold
    }

    [self changeFacesColor:_all_vector_vid toSelected:NO];
    
    modState = MODIFICATION_NONE;

    _edges_to_scale.clear();
    _all_vector_vid.clear();
    
    [self rebuffer];
}
 
#pragma mark - SELECTION
-(void)changeFacesColor:(vector<HMesh::VertexID>) vertecies toSelected:(BOOL)isSelected {
    
    Vec4uc selectColor;
    if (isSelected) {
        selectColor = Vec4uc(240, 0, 0, 255);
    } else {
        selectColor = Vec4uc(0,0,0,255);
    }
    
    [self.wireframeColorDataBuffer bind];
    unsigned char* temp = (unsigned char*) glMapBufferOES(GL_ARRAY_BUFFER, GL_WRITE_ONLY_OES);
    for (VertexID vid: vertecies) {
        int index = vid.index;
        memcpy(temp + index*COLOR_SIZE, selectColor.get(), COLOR_SIZE);
    }
    glUnmapBufferOES(GL_ARRAY_BUFFER);
    glBindBuffer(GL_ARRAY_BUFFER, 0);
}


-(void)changeFaceColorToSelected:(FaceID)fid  toSelected:(BOOL)isSelected {

    vector<int> indicies;
    for(Walker w = _manifold.walker(fid); !w.full_circle(); w = w.circulate_face_cw()) {
        VertexID vid = w.vertex();
        int index = vid.index;
        indicies.push_back(index);
    }
    
    Vec4uc selectColor;
    if (isSelected) {
        selectColor =  Vec4uc(240, 0, 0, 255);
    } else {
        selectColor = Vec4uc(200,200,200,255);
    }
    
    [self.wireframeColorDataBuffer bind];
    unsigned char* temp = (unsigned char*) glMapBufferOES(GL_ARRAY_BUFFER, GL_WRITE_ONLY_OES);
    for (int index: indicies) {
        memcpy(temp + index*COLOR_SIZE, selectColor.get(), COLOR_SIZE);
    }
    glUnmapBufferOES(GL_ARRAY_BUFFER);
    glBindBuffer(GL_ARRAY_BUFFER, 0);
}

#pragma mark - DRAWING
-(void)updateMesh {
    if (modState == MODIFICATION_SCALING) {
        
        for (int i = 0; i < _edges_to_scale.size(); i ++) {
            scaled_pos_for_rib(_manifold,
                               _edges_to_scale[i],
                               _centroids[i],
                               _edgeInfo,
                               1 + (_scaleFactor - 1)*_scale_weight_vector[i],
                               _current_scale_position);
        }
        
        [self.vertexDataBuffer bind];
//        glBufferData(GL_ARRAY_BUFFER, self.numVertices*VERTEX_SIZE, NULL, GL_DYNAMIC_DRAW);
        unsigned char* temp = (unsigned char*) glMapBufferOES(GL_ARRAY_BUFFER, GL_WRITE_ONLY_OES);
        for (VertexID vid: _all_vector_vid) {
            Vecf pos = _current_scale_position[vid];
            int index = vid.index;
            memcpy(temp + index*VERTEX_SIZE, pos.get(), VERTEX_SIZE);
        }
        glUnmapBufferOES(GL_ARRAY_BUFFER);
        glBindBuffer(GL_ARRAY_BUFFER, 0);
    }
}

-(void)draw {
    
    [self updateMesh];
    
    glUseProgram(self.drawShaderProgram.program);
    glUniformMatrix4fv(uniforms[UNIFORM_MODELVIEWPROJECTION_MATRIX], 1, 0, self.modelViewProjectionMatrix.m);
    glUniformMatrix3fv(uniforms[UNIFORM_NORMAL_MATRIX], 1, 0, self.normalMatrix.m);

    [self.vertexDataBuffer bind];    
    [self.vertexDataBuffer prepareToDrawWithAttrib:attrib[ATTRIB_POSITION]
                               numberOfCoordinates:3
                                      attribOffset:0
                                          dataType:GL_FLOAT
                                         normalize:GL_FALSE];
    [self.normalDataBuffer bind];
    [self.normalDataBuffer prepareToDrawWithAttrib:attrib[ATTRIB_NORMAL]
                               numberOfCoordinates:3
                                      attribOffset:0
                                          dataType:GL_FLOAT
                                         normalize:GL_FALSE];
    
    [self.colorDataBuffer bind];
    [self.colorDataBuffer prepareToDrawWithAttrib:attrib[ATTRIB_COLOR]
                               numberOfCoordinates:4
                                      attribOffset:0
                                          dataType:GL_UNSIGNED_BYTE
                                         normalize:GL_TRUE];    
    
    glEnable(GL_POLYGON_OFFSET_FILL);
    glPolygonOffset(2.0f, 2.0f);
    
    [self.indexDataBuffer bind];
    [AGLKVertexAttribArrayBuffer drawPreparedArraysWithMode:GL_TRIANGLES
                                                   dataType:GL_UNSIGNED_INT
                                                 indexCount:self.numIndices];
    
    [self.wireframeColorDataBuffer bind];
    [self.wireframeColorDataBuffer prepareToDrawWithAttrib:attrib[ATTRIB_COLOR]
                                       numberOfCoordinates:4
                                              attribOffset:0
                                                  dataType:GL_UNSIGNED_BYTE
                                                 normalize:GL_TRUE];
    
    glDisable(GL_POLYGON_OFFSET_FILL);
    [self.wireframeIndexBuffer bind];
    [AGLKVertexAttribArrayBuffer drawPreparedArraysWithMode:GL_LINES
                                                   dataType:GL_UNSIGNED_INT
                                                 indexCount:self.wireframeNumOfIndicies];
    
    glBindBuffer(GL_ARRAY_BUFFER, 0);
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, 0);
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
    
    [self.indexDataBuffer bind];
    [AGLKVertexAttribArrayBuffer drawPreparedArraysWithMode:GL_TRIANGLES
                                                   dataType:GL_UNSIGNED_INT
                                                 indexCount:self.numIndices];
}


@end
