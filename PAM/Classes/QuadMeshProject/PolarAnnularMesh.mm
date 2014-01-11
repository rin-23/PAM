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
#include "smooth.h"

#include <queue>
#import "Vec4uc.h"
#import <OpenGLES/ES2/gl.h>
#import <OpenGLES/ES2/glext.h>
#import "PAMUtilities.h"

#include "eigensolution.h"

#define kCENTROID_STEP 0.025f

static int VERTEX_SIZE =  3 * sizeof(float);
static int COLOR_SIZE =  4 * sizeof(unsigned char);
static int INDEX_SIZE  = sizeof(unsigned int);

typedef enum {
    MODIFICATION_NONE,
    MODIFICATION_SCALING,
    MODIFICATION_BRANCH_ROTATION,
    MODIFICATION_BRANCH_SCALING,
    MODIFICATION_BRANCH_TRANSLATION
} CurrentModification;

typedef CGLA::Vec3d Vec;
typedef CGLA::Vec3f Vecf;

using namespace HMesh;

@interface PolarAnnularMesh() {
    HMesh::Manifold _manifold;
    HMesh::Manifold _skeletonMani;
    HMesh::HalfEdgeAttributeVector<EdgeInfo> _edgeInfo;
    BoundingBox _boundingBox;

    GLKVector3 _initialTouch;
    
    //Scaling of Rings
    HMesh::FaceID _scaleRibFace1;
    HMesh::FaceID _scaleRibFace2;
    float _scaleFactor;
    vector<float> _scale_weight_vector;
    HMesh::VertexAttributeVector<Vecf> _current_scale_position;
    
    //Rotation
    HalfEdgeID _pinHalfEdgeID;
    HalfEdgeID _pivotHalfEdgeID;
    float _rotAngle;
    HMesh::VertexAttributeVector<Vecf> _current_rot_position;
    GLKVector3 _centerOfRotation;
    map<VertexID, int> _vertexToLoop;
    vector<int> _loopsToDeform;
    map<int, float> _ringToDeformValue;
    HMesh::HalfEdgeID _deformDirHalfEdge;
    
    //Translation
    GLKVector3 _translation;
    
    //Selection
    vector<HMesh::HalfEdgeID> _edges_to_scale;
    vector<HMesh::VertexID> _all_vector_vid;
    vector<CGLA::Vec3f> _centroids;
    vector<GLKVector3> _touchPoints;
    GLKVector3 _startPoint;
    
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
        _manifold = HMesh::Manifold();
    }
    return self;
}

-(void)setMeshFromObjFile:(NSString*)objFilePath {

//    _branchWidth = 1;
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
    
    [self rebufferWithCleanup:NO bufferData:YES edgeTrace:NO];
}


-(void)rebufferNoEdgetrace {
   
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
                                                                                usage:GL_STATIC_DRAW
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
}

-(void)rebufferWithCleanup:(BOOL)shouldClean bufferData:(BOOL)bufferData edgeTrace:(BOOL)shouldEdgeTrace {
    if (shouldClean) {
        _manifold.cleanup();
    }
    
    if (bufferData) {
        [self rebufferNoEdgetrace];
    }

    if (shouldEdgeTrace) {
        _edgeInfo = trace_spine_edges(_manifold);
    }
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
    Vec4uc wColor(180, 180, 180, 255);
    
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
    [self rebufferWithCleanup:NO bufferData:YES edgeTrace:YES];
}

-(void)showSkeleton:(BOOL)show {
    if (show) {
        _skeletonMani = _manifold; //TODO check memmory managment here
        skeleton_retract(_manifold, 1);
    } else {
        _manifold = _skeletonMani;
    }
    [self rebufferWithCleanup:NO bufferData:YES edgeTrace:NO];
}

-(void)showRibJunctions
{
    number_rib_edges(_manifold, _edgeInfo);
    vector<VertexID> verticies;
    for(HalfEdgeID hid : _manifold.halfedges())
    {
        if (_edgeInfo[hid].edge_type == RIB_JUNCTION) {
            Walker w = _manifold.walker(hid);
            verticies.push_back(w.vertex());
        }
    }
    [self changeWireFrameColor:verticies toSelected:YES];
    
}

-(BOOL)manifoldIsLoaded {
    return _manifold.no_vertices() != 0;
}

-(void)clear {
    _manifold.clear();
    [self rebufferWithCleanup:NO bufferData:YES edgeTrace:YES];
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

//Create branch at a given vertex. Return VertexID of newly created pole.
-(BOOL)createHoleAtVertex:(VertexID)vID
              numOfSpines:(int)width
                 vertexID:(VertexID*)newPoleID
              branchWidth:(float*)bWidth
               holeCenter:(GLKVector3*)holeCenter
                 holeNorm:(GLKVector3*)holeNorm
         boundaryHalfEdge:(HalfEdgeID*)boundayHalfEdge
{
    BOOL result = [self createBranchAtVertex:vID numOfSpines:width vertexID:newPoleID branchWidth:bWidth];
    if (result) {
        Vecf vf = _manifold.posf(*newPoleID);
        Vec n = HMesh::normal(_manifold, *newPoleID);
        *holeCenter = GLKVector3Make(vf[0], vf[1], vf[2]);
        *holeNorm = GLKVector3Make(n[0], n[1], n[2]);
        
        Walker w = _manifold.walker(*newPoleID);
        w = w.next();
        *boundayHalfEdge = w.halfedge();
        
        NSLog(@"%i", valency(_manifold, w.vertex()));
        _manifold.remove_vertex(*newPoleID);
        
        return YES;
    }
    return NO;
}


//Create branch at a given vertex. Return VertexID of newly created pole.
-(BOOL)createBranchAtVertex:(VertexID)vID
                numOfSpines:(int)width
                   vertexID:(VertexID*)newPoleID
                branchWidth:(float*)bWidth
{
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
    refine_branch(_manifold, *newPoleID, *bWidth);
    
    return YES;
}


-(BOOL)createHoleAtVertex:(VertexID)vID
                    width:(float)width
                 vertexID:(VertexID*)newPoleID
              branchWidth:(float*)bWidth
               holeCenter:(GLKVector3*)holeCenter
                 holeNorm:(GLKVector3*)holeNorm
         boundaryHalfEdge:(HalfEdgeID*)boundayHalfEdge
              numOfSpines:(int*)numOfSpines
{
    BOOL result = [self createBranchAtVertex:vID width:width vertexID:newPoleID branchWidth:bWidth numOfSpines:numOfSpines];
    if (result) {
        Vecf vf = _manifold.posf(*newPoleID);
        Vec n = HMesh::normal(_manifold, *newPoleID);
        *holeCenter = GLKVector3Make(vf[0], vf[1], vf[2]);
        *holeNorm = GLKVector3Make(n[0], n[1], n[2]);
        
        Walker w = _manifold.walker(*newPoleID);
        w = w.next();
        *boundayHalfEdge = w.halfedge();
        
        NSLog(@"%i", valency(_manifold, w.vertex()));
        _manifold.remove_vertex(*newPoleID);
        
        return YES;
    }
    return NO;
}

//Create branch at a given vertex with width being distance between two fingers.
//Return VertexID of newly created pole and actual width if the branch.
-(BOOL)createBranchAtVertex:(VertexID)vID
                      width:(float)width
                   vertexID:(VertexID*)newPoleID
                branchWidth:(float*)bWidth
                numOfSpines:(int*)numOfSpines

{
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
    
    VertexAttributeVector<int> vs(_manifold.no_vertices(), 0);
    vs[vID] = 1;
    
    vector<VertexID> ribs;
    
    Walker ribWalkerRight = walker.next().opp().next();
    Walker ribWalkerLeft = walker.opp();
    
    while (true) {
        if (ribWalkerRight.vertex() == ribWalkerLeft.vertex()) {
            NSLog(@"[WARNING][PolarAnnularMesh] Width is too large");
            return NO;
        }
        Vec right_vertex = _manifold.pos(ribWalkerRight.vertex());
        Vec left_vertex = _manifold.pos(ribWalkerLeft.vertex());

        float walked_distance = (right_vertex - left_vertex).length();
        if (walked_distance > width) {
            break;
        }
        ribs.push_back(ribWalkerRight.vertex());
        ribs.push_back(ribWalkerLeft.vertex());
        ribWalkerRight = ribWalkerRight.next().opp().next();
        ribWalkerLeft = ribWalkerLeft.next().opp().next();
    }
    
    //Set all verticies to be branched out
    for (int i = 0; i < ribs.size(); i++) {
        VertexID cur_vID = ribs[i];
        vs[cur_vID] = 1;
    }
    *numOfSpines = ribs.size()/2;
    
    *newPoleID = polar_add_branch(_manifold, vs);
    refine_branch(_manifold, *newPoleID, *bWidth);
    
    return YES;
}


#pragma mark - SMOOTH
-(void)smoothAtPoint:(GLKVector3)touchPoint {
    HalfEdgeAttributeVector<EdgeInfo> edge_info(_manifold.allocated_halfedges());
    VertexID closestPoint = [self closestVertexID_3D:touchPoint];
    Vec originPos = _manifold.pos(closestPoint);

    queue<HalfEdgeID> hq;
    vector<VertexID> floodVerticies;
    vector<float> weights;
    
    floodVerticies.push_back(closestPoint);
    weights.push_back(1.0f);
    circulate_vertex_ccw(_manifold, closestPoint, [&](Walker w) {
        floodVerticies.push_back(w.vertex());
        weights.push_back(1.0f);
        edge_info[w.halfedge()] = EdgeInfo(SPINE, 0);
        edge_info[w.opp().halfedge()] = EdgeInfo(SPINE, 0);
        hq.push(w.opp().halfedge());
    });
    
    float brush_size = 0.1;

    while(!hq.empty())
    {
        HalfEdgeID h = hq.front();
        Walker w = _manifold.walker(h);
        hq.pop();

        for (;!w.full_circle(); w = w.circulate_vertex_ccw()) {
            if(edge_info[w.halfedge()].edge_type == UNKNOWN)
            {
                Vec pos = _manifold.pos(w.vertex());
                float d = (pos - originPos).length();
                if (d <= brush_size) {
                    floodVerticies.push_back(w.vertex());
                    weights.push_back(1.0f);

                    edge_info[w.halfedge()] = EdgeInfo(SPINE,0);
                    edge_info[w.opp().halfedge()] = EdgeInfo(SPINE,0);
                    
                    hq.push(w.opp().halfedge());
                }
            }
        }
    }
    
    laplacian_smooth_verticies(_manifold, floodVerticies, weights, 1);
//    laplacian_smooth_vertex(_manifold, floodVerticiesVector, _edgeInfo, 1);
    [self rebufferWithCleanup:NO bufferData:YES edgeTrace:NO];
//    [self changeVerticiesColor:floodVerticies toSelected:YES];
}


#pragma mark - TOUCHES: SCULPTING A SMALL BUMP 
-(void)createBumpAtPoint:(vector<GLKVector3>)tPoints
            touchedModel:(BOOL)touchedModel 
              touchSpeed:(float)touchSpeed 
               touchSize:(float)touchSize
{
    if (tPoints.size() < 2) {
        return;
    }
    
    float brushSize;

//    if (touchSize > 9.0f) {
//        brushSize = 2;
//    } else {
//        brushSize = 1;
//    }
    
    //make a small bump
    if (touchSpeed <= 500) {
        brushSize = 0.07;
    } else if (touchSpeed > 500  && touchSpeed <= 1000) {
        brushSize = 0.08;
    } else if (touchSpeed > 1000) {
        brushSize = 0.1;
    }
    
    [self saveState];
    
    VertexID touchedVID;
    if (touchedModel) {
        //closest vertex in 3D space
        touchedVID = [self closestVertexID_3D:_startPoint];
    } else {
        //closest vertex in 2D space
        touchedVID = [self closestVertexID_2D:_startPoint];
    }
    
//    Vec c;
//    float r;
//    bsphere(_manifold, c, r);
    Vec touchedPos = _manifold.pos(touchedVID);
    Vec norm = HMesh::normal(_manifold, touchedVID);
    Vec displace = 0.05*norm;
    
    //Decide if its a bump or dent, based on direction of the normal and a stoke in 2D
    GLKVector3 firstCentroidWorld = [Utilities matrix4:self.viewMatrix multiplyVector3:tPoints[0]];
    GLKVector3 lastCentroidWorld = [Utilities matrix4:self.viewMatrix multiplyVector3:tPoints[tPoints.size() - 1]];
    GLKVector3 strokeDirWorld = GLKVector3Subtract(lastCentroidWorld, firstCentroidWorld);
    GLKVector2 strokeDirWorld2D = GLKVector2Make(strokeDirWorld.x, strokeDirWorld.y);
    GLKVector3 normModel = GLKVector3Make(norm[0], norm[1], norm[2]);
    GLKVector3 normWorld = [Utilities matrix4:self.modelViewMatrix multiplyVector3:normModel];
    GLKVector2 normWorld2D = GLKVector2Make(normWorld.x, normWorld.y);

    float dotP = GLKVector2DotProduct(normWorld2D, strokeDirWorld2D);
    if (dotP < 0) {
        displace = -1*displace;
    }
    
    for (auto vid : _manifold.vertices())
    {
        double l = (touchedPos - _manifold.pos(vid)).length();
        float x = l/brushSize;
        if (x <= 1) {
            float weight = pow(pow(x,2)-1, 2);
            _manifold.pos(vid) = _manifold.pos(vid) + displace * weight;
        }

//        float l = (touchedPos - _manifold.pos(vid)).length();
//        if (l < brushSize) {
//            float x = l / brushSize;
//            float weight  = pow(pow(x, 2) - 1, 2);
//            _manifold.pos(vid) = _manifold.pos(vid) + displace * weight;
//        }
    }
    
    [self rebufferWithCleanup:NO bufferData:YES edgeTrace:NO];
}

#pragma mark - UTILITIES BRANCH CREATION

-(int)branchWidthForTouchSpeed:(float)touchSpeed touchPoint:(VertexID)vID{
    
    float angle = 0;
    if (touchSpeed <= 500) {
        angle = GLKMathDegreesToRadians(30);
    } else if (touchSpeed > 500  && touchSpeed <= 1100) {
        angle = GLKMathDegreesToRadians(70);
    } else if (touchSpeed > 1100) {
        angle = GLKMathDegreesToRadians(110);
    }
    
    Walker walker = _manifold.walker(vID);
    if (_edgeInfo[walker.halfedge()].is_spine()) {
        walker = walker.opp().next();
    }
    assert(_edgeInfo[walker.halfedge()].is_rib());
    
    Vecf centr = centroid_for_rib(_manifold, walker.halfedge(), _edgeInfo);
    Vecf v1 = _manifold.posf(vID) - centr;
    GLKVector3 v1glk = GLKVector3Make(v1[0], v1[1], v1[2]);
    
    float cur_angle = 0;
    int width = 0;
    while (cur_angle <= angle/2) {
        Vecf v2 = _manifold.posf(walker.vertex()) - centr;
        GLKVector3 v2glk = GLKVector3Make(v2[0], v2[1], v2[2]);
        cur_angle = [Utilities angleBetweenVector:v1glk andVector:v2glk];
        width += 1;
        walker = walker.next().opp().next();
    }
    
    return width;
}

#pragma mark - BRANCH CREATION ONE FINGER

-(void)startCreateBranch:(GLKVector3)touchPoint closestPoint:(GLKVector3)closestPoint {
    if (![self manifoldIsLoaded]) {
        return;
    }
    _startPoint = closestPoint;
    _touchPoints.clear();
    _touchPoints.push_back(touchPoint);
}

-(void)continueCreateBranch:(GLKVector3)touchPoint {
    if (![self manifoldIsLoaded])
        return;
    
    _touchPoints.push_back(touchPoint);
}

//-(void)endCreateBranch:(GLKVector3)touchPoint touchedModel:(BOOL)touchedModel{
//    if(![self manifoldIsLoaded])
//        return;
//    
//    [self saveState];
// 
//    VertexID touchedVID;
//    if (touchedModel) {
//        //closest vertex in 3D space
//        touchedVID = [self closestVertexID_3D:_touchPoints[0]];
//    } else {
//        //closest vertex in 2D space
//        touchedVID = [self closestVertexID_2D:_touchPoints[0]];
//    }
//
//    Vec norm = HMesh::normal(_manifold, touchedVID);
//    float displace = GLKVector3Length(GLKVector3Subtract(touchPoint, _initialTouch));
//    NSLog(@"displace %f", displace);
//    Vec displace3d =  displace * norm ;
//    
//    VertexID newPoleID;
//    float bWidth;
//    BOOL result = [self createBranchAtVertex:touchedVID width:self.branchWidth vertexID:&newPoleID branchWidth:&bWidth];
//    if (result) {
//        //add rib araound the pole
//        add_rib(_manifold, _manifold.walker(newPoleID).halfedge(), _edgeInfo);
//        
//        // Move pole
//        _manifold.pos(newPoleID) = _manifold.pos(newPoleID) + displace3d;
//        
//        // Move vertecies adjacent to pole
//        for (Walker walker = _manifold.walker(newPoleID); !walker.full_circle(); walker = walker.circulate_vertex_ccw()) {
//            _manifold.pos(walker.vertex()) = _manifold.pos(walker.vertex()) + displace3d*0.95f;
//        }
//        
//        //Add ribs for the new branch
//        Walker walker = _manifold.walker(newPoleID);
//        HalfEdgeID ID_1 = walker.next().opp().next().halfedge();
//        recursively_add_rib(_manifold, ID_1, 5, _edgeInfo);
//        
//        [self rebuffer];
//    }
//}

-(vector<vector<GLKVector3>>)endCreateBranchBended:(GLKVector3)touchPoint
                                        touchedModel:(BOOL)touchedModel
                                           touchSize:(float)touchSize
                                   averageTouchSpeed:(float)touchSpeed
{
    vector<vector<GLKVector3>> empty;
    
    if (![self manifoldIsLoaded]) {
        return empty;
    }
    
    if ( _touchPoints.size() < 8) {
        if (_touchPoints.size() >= 2) {
            [self createBumpAtPoint:_touchPoints touchedModel:touchedModel touchSpeed:touchSpeed touchSize:touchSize];
        } else {
            NSLog(@"[PolarAnnularMesh][WARNING] Garbage point data");
        }
        return empty;
    }
    
    //convert touch points to world space
    vector<GLKVector3> touchPointsWorld(_touchPoints.size());
    for (int i = 0; i < _touchPoints.size(); i++) {
        touchPointsWorld[i] = [Utilities matrix4:self.viewMatrix multiplyVector3:_touchPoints[i]];
    }
    
    //Get skeleton aka joint points
    vector<GLKVector3> rawSkeleton;
    GLKMatrix3 m = GLKMatrix4GetMatrix3(self.modelViewMatrix);
    float c_step = GLKVector3Length(GLKMatrix3MultiplyVector3(m, GLKVector3Make(kCENTROID_STEP, 0, 0)));
    [PAMUtilities centroids3D:rawSkeleton forOneFingerTouchPoint:touchPointsWorld withNextCentroidStep:c_step];
    if (rawSkeleton.size() < 8) {
        NSLog(@"[PolarAnnularMesh][WARNING] Not enough controids");
        [self createBumpAtPoint:_touchPoints touchedModel:touchedModel touchSpeed:touchSpeed touchSize:touchSize];
        return empty;
    }
    
    [self saveState];
    
    VertexID touchedVID;
    if (touchedModel) {
        touchedVID = [self closestVertexID_3D:_startPoint];
    } else {
        touchedVID = [self closestVertexID_2D:_startPoint];
    }
    
    //Create new pole
    VertexID newPoleID;
    float bWidth;
    GLKVector3 holeCenter, holeNorm;
    HalfEdgeID boundaryHalfEdge;

    int limbWidth = [self branchWidthForTouchSpeed:touchSpeed touchPoint:touchedVID];
    
    NSLog(@"Limb Width: %i", limbWidth);
    
    BOOL result = [self createHoleAtVertex:touchedVID
                               numOfSpines:limbWidth
                                  vertexID:&newPoleID
                               branchWidth:&bWidth
                                holeCenter:&holeCenter
                                  holeNorm:&holeNorm
                          boundaryHalfEdge:&boundaryHalfEdge];
    
    if (!result) {
        [self undo];
        return empty;
    }
    
    //closest to the first centroid between two fingers vertex in 2D space
    GLKVector3 touchedV_world = [Utilities matrix4:self.modelViewMatrix multiplyVector3:holeCenter];
    float zValueTouched = touchedV_world.z;
    
    //add depth to skeleton points
    for (int i = 0; i < rawSkeleton.size(); i++) {
        GLKVector3 tPoint = rawSkeleton[i];
        rawSkeleton[i] = GLKVector3Make(tPoint.x, tPoint.y, zValueTouched);
    }
    
    //Smooth
    vector<GLKVector3> skeleton = [PAMUtilities laplacianSmoothing3D:rawSkeleton iterations:3];
    
    //Skeleton should start from the branch point
    GLKVector3 translate = GLKVector3Subtract(touchedV_world, skeleton[0]);
    for (int i = 0; i < skeleton.size(); i++) {
        skeleton[i] = GLKVector3Add(skeleton[i], translate);
    }
    
    //Length
    float totalLength = 0;
    GLKVector3 lastSkelet = skeleton[0];
    for (int i = 1; i < skeleton.size(); i++) {
        totalLength += GLKVector3Distance(lastSkelet, skeleton[i]);
        lastSkelet = skeleton[i];
    }
    
    float deformLength = 0.2f * totalLength;
    int deformIndex;
    totalLength = 0;
    lastSkelet = skeleton[0];

    for (int i = 1; i < skeleton.size(); i++) {
        totalLength += GLKVector3Distance(lastSkelet, skeleton[i]);
        lastSkelet = skeleton[i];
        if (totalLength > deformLength) {
            deformIndex = i + 1;
            break;
        }
    }
    
    //Move branch by weighted norm
    GLKVector3 holeNormWorld = GLKVector3Normalize([Utilities matrix4:self.modelViewMatrix multiplyVector3NoTranslation:holeNorm]);
    holeNormWorld = GLKVector3MultiplyScalar(holeNormWorld, deformLength);
    for (int i = 0; i < skeleton.size(); i++) {
        if (i < deformIndex) {
            float x = (float)i/(float)deformIndex;
            float weight = sqrt(x);
            skeleton[i] = GLKVector3Add(skeleton[i], GLKVector3MultiplyScalar(holeNormWorld, weight));
        } else {
            skeleton[i] = GLKVector3Add(skeleton[i], holeNormWorld);
        }
    }
    
    skeleton = [PAMUtilities laplacianSmoothing3D:skeleton iterations:1];
    
    //Get norm vectors for skeleton joints
    vector<GLKVector3> skeletonTangents;
    vector<GLKVector3> skeletonNormals;
    [PAMUtilities  normals3D:skeletonNormals tangents3D:skeletonTangents forSkeleton:skeleton];
    
    //Parse new skeleton and create ribs
    //Ingore first and last centroids since they are poles
    int numSpines = limbWidth * 4;
    vector<vector<GLKVector3>> allRibs(skeleton.size());
    vector<GLKVector3> skeletonModel;
    vector<GLKVector3> skeletonNormalsModel;
    
    for (int i = 0; i < skeleton.size(); i++) {
        GLKVector3 sModel = [Utilities invertVector3:skeleton[i]
                                          withMatrix:self.modelViewMatrix];
        
        //dont preserve translation for norma and tangent
        float ribWidth = bWidth;
        GLKVector3 nModel = [Utilities invertVector4:GLKVector4Make(skeletonNormals[i].x, skeletonNormals[i].y, skeletonNormals[i].z, 0)
                                          withMatrix:self.modelViewMatrix];
        GLKVector3 tModel = [Utilities invertVector4:GLKVector4Make(skeletonTangents[i].x, skeletonTangents[i].y, skeletonTangents[i].z, 0)
                                          withMatrix:self.modelViewMatrix];
        
        tModel = GLKVector3MultiplyScalar(GLKVector3Normalize(tModel), ribWidth);
        nModel = GLKVector3MultiplyScalar(GLKVector3Normalize(nModel), ribWidth);
        
        skeletonModel.push_back(sModel);
        
//        vector<GLKVector3>norm;
//        norm.push_back(sModel);
//        norm.push_back(GLKVector3Add(sModel, nModel));
//        allRibs.push_back(norm);
//        
//        vector<GLKVector3>tangent;
//        tangent.push_back(sModel);
//        tangent.push_back(GLKVector3Add(sModel, tModel));
//        allRibs.push_back(tangent);
        
        if (i == skeleton.size() - 1) {
            vector<GLKVector3> secondPole;
            secondPole.push_back(sModel);
            allRibs[i] = secondPole;
        } else {
            vector<GLKVector3> ribs(numSpines);
            float rot_step = 360.0f/numSpines;
            GLKMatrix4 toOrigin = GLKMatrix4MakeTranslation(-sModel.x, -sModel.y, -sModel.z);
            GLKMatrix4 fromOrigin = GLKMatrix4MakeTranslation(sModel.x, sModel.y, sModel.z);
            
            for (int j = 0; j < numSpines; j++) {
                float angle = j * rot_step;
                
                GLKMatrix4 rotMatrix = GLKMatrix4MakeRotation(GLKMathDegreesToRadians(angle), tModel.x, tModel.y, tModel.z);
                GLKMatrix4 tMatrix = GLKMatrix4Multiply(GLKMatrix4Multiply(fromOrigin, rotMatrix), toOrigin);
                
                GLKVector3 startPosition = GLKVector3Add(sModel, nModel);
                startPosition =  [Utilities matrix4:tMatrix multiplyVector3:startPosition];
                ribs[j] = startPosition;
            }
            allRibs[i] = ribs;
        }
        
        
    }
//    
//    allRibs.push_back(skeletonModel);
//    allRibs.push_back(skeletonNormalsModel);
    
//    [self rebufferWithCleanup:YES edgeTrace:YES];
//    return allRibs;
    
    VertexID limbPole = [self populateNewLimb:allRibs];
    assert(is_pole(_manifold, limbPole));
    
    Walker wBase1 = _manifold.walker(limbPole);
    
    for (; valency(_manifold, wBase1.vertex()) != 3; wBase1 = wBase1.next().opp().next());

    HalfEdgeID limbOuterHalfEdge = wBase1.next().halfedge();
    HalfEdgeID limbBoundaryHalfEdge = wBase1.next().opp().halfedge();
    
    [self stitchBranch:boundaryHalfEdge toBody:limbBoundaryHalfEdge];
    [self rebufferWithCleanup:YES bufferData:NO edgeTrace:YES];
    number_rib_edges(_manifold, _edgeInfo);
    
    Walker toJunctionWalker = _manifold.walker(limbOuterHalfEdge);
    toJunctionWalker = toJunctionWalker.prev().opp();
    
    EdgeType t = _edgeInfo[toJunctionWalker.next().halfedge()].edge_type;
    
    while (t != RIB_JUNCTION) {
        toJunctionWalker = toJunctionWalker.next().opp().next();
        t = _edgeInfo[toJunctionWalker.next().halfedge()].edge_type;
    }
    
    vector<VertexID> floodVerticies;
    
    Walker boundaryWalker = _manifold.walker(toJunctionWalker.next().halfedge());

//    vector<float>weights;
    float brush_size = 0.2;
    
    HalfEdgeAttributeVector<EdgeInfo> edge_info(_manifold.allocated_halfedges());
    for (; !boundaryWalker.full_circle(); boundaryWalker = boundaryWalker.next().opp().next()) {

        VertexID closestPoint = boundaryWalker.vertex();
        Vec originPos = _manifold.pos(closestPoint);
        
        queue<HalfEdgeID> hq;
        circulate_vertex_ccw(_manifold, closestPoint, [&](Walker w) {
            floodVerticies.push_back(w.vertex());
//            Vec pos = _manifold.pos(w.vertex());
//            float d = (pos - originPos).length();
//            float x = d/brush_size;
//            float weight;
//            if (x <= 1) {
//                weight = pow(pow(x, 2) - 1, 2);
//            } else {
//                weight = 0;
//            }
//            weights.push_back(weight);

            edge_info[w.halfedge()] = EdgeInfo(SPINE, 0);
            edge_info[w.opp().halfedge()] = EdgeInfo(SPINE, 0);
            hq.push(w.opp().halfedge());
        });
        
        floodVerticies.push_back(closestPoint);
//        weights.push_back(1);
        while(!hq.empty())
        {
            HalfEdgeID h = hq.front();
            Walker w = _manifold.walker(h);
            hq.pop();
            
            for (;!w.full_circle(); w=w.circulate_vertex_ccw()) {
                if(edge_info[w.halfedge()].edge_type == UNKNOWN)
                {
                    Vec pos = _manifold.pos(w.vertex());
                    float d = (pos - originPos).length();
                    if (d <= brush_size) {
                        floodVerticies.push_back(w.vertex());
//                        float x = d/brush_size;
//                        float weight;
//                        if (x <= 1) {
//                            weight = pow(pow(x, 2) - 1, 2);
//                        } else {
//                            weight = 0;
//                        }
//                        weights.push_back(weight);
                        edge_info[w.halfedge()] = EdgeInfo(SPINE,0);
                        edge_info[w.opp().halfedge()] = EdgeInfo(SPINE,0);
                        
                        hq.push(w.opp().halfedge());
                    }
                }
            }
        }
    }
    
//    taubin_smooth(_manifold, 10);
//    _edgeInfo = trace_spine_edges(_manifold);
    laplacian_spine_smooth_verticies(_manifold, floodVerticies, _edgeInfo, 15);
//    laplacian_smooth_verticies(_manifold, floodVerticies, weights, 2);
    [self rebufferWithCleanup:NO bufferData:YES edgeTrace:NO];
    return allRibs;
}


#pragma mark - BRANCH CREATION TWO FINGERS

-(void)startCreateBranchFinger1:(GLKVector3)touchPoint1 finger2:(GLKVector3)touchPoint2 {
    _touchPoints.clear();
    _touchPoints.push_back(touchPoint1);
    _touchPoints.push_back(touchPoint2);
}

-(void)continueCreateBranchFinger1:(GLKVector3)touchPoint1 finger2:(GLKVector3)touchPoint2 {
    _touchPoints.push_back(touchPoint1);
    _touchPoints.push_back(touchPoint2);
}

-(std::vector<std::vector<GLKVector3>>)endCreateBranchTwoFingersWithTouchedModel:(BOOL)touchedModel {
    if (![self manifoldIsLoaded]) {
        return [self endCreateNewBodyTwoFingers];
    } else {
        std::vector<std::vector<GLKVector3>> empty;
        return empty;
    }
    
    if (_touchPoints.size() < 8 || _touchPoints.size() % 2 != 0) {
        NSLog(@"[PolarAnnularMesh][WARNING] Garbage point data");
        return vector<vector<GLKVector3>>();
    }
    
    //convert touch points to world space
    vector<GLKVector2> touchPointsWorld(_touchPoints.size());
    for (int i = 0; i < _touchPoints.size(); i++)
    {
        GLKVector3 worldSpace3 = [Utilities matrix4:self.viewMatrix multiplyVector3:_touchPoints[i]];
        touchPointsWorld[i] = GLKVector2Make(worldSpace3.x, worldSpace3.y);
    }
    
    //Get skeleton aka joint points
    vector<GLKVector2> rawSkeleton;
    vector<float> skeletonWidth;
    
    //Find scaled step
    GLKMatrix3 m = GLKMatrix4GetMatrix3(self.modelViewMatrix);
    float c_step = GLKVector3Length(GLKMatrix3MultiplyVector3(m, GLKVector3Make(kCENTROID_STEP, 0, 0)));
//    float c_step = GLKVector3Length([Utilities matrix4:self.viewMatrix multiplyVector4:GLKVector4Make(kCENTROID_STEP, 0, 0, 0)]);
    [PAMUtilities centroids:rawSkeleton ribWidth:skeletonWidth forTwoFingerTouchPoint:touchPointsWorld withNextCentroidStep:c_step];
    if (rawSkeleton.size() < 4) {
        NSLog(@"[PolarAnnularMesh][WARNING] Not enough controids");
        return vector<vector<GLKVector3>>();
    }
    
    [self saveState];
    
    //closest to the first centroid between two fingers vertex in 2D space
    VertexID touchedVID;
    GLKVector3 firstCentroid = GLKVector3Lerp(_touchPoints[0], _touchPoints[1], 0.5f);
    float baseWidth = GLKVector3Distance([Utilities invertVector3:_touchPoints[0] withMatrix:self.modelMatrix],
                                         [Utilities invertVector3:_touchPoints[1] withMatrix:self.modelMatrix]);
  
    if (touchedModel) {
        touchedVID = [self closestVertexID_3D:firstCentroid];
    } else {
        touchedVID = [self closestVertexID_2D:firstCentroid];
    }
    
    //Create new pole
    VertexID newPoleID;
    float bWidth;
    GLKVector3 holeCenter;
    GLKVector3 holeNorm;
    HalfEdgeID boundaryHalfEdge;
    int numOfSpines;
    
    BOOL result = [self createHoleAtVertex:touchedVID
                                     width:baseWidth
                                  vertexID:&newPoleID
                               branchWidth:&bWidth
                                holeCenter:&holeCenter
                                  holeNorm:&holeNorm
                          boundaryHalfEdge:&boundaryHalfEdge
                               numOfSpines:&numOfSpines];
    if (!result) {
        return vector<vector<GLKVector3>>();
    }

    //closest to the first centroid between two fingers vertex in 2D space
    GLKVector3 touchedV_world = [Utilities matrix4:self.modelViewMatrix
                                   multiplyVector3:holeCenter];
    float zValueTouched = touchedV_world.z;
    

    
    //Smooth
    vector<GLKVector2> skeleton = [PAMUtilities laplacianSmoothing:rawSkeleton iterations:3];
    
    //Skeleton should start from the branch point
    GLKVector2 translate = GLKVector2Subtract(GLKVector2Make(touchedV_world.x, touchedV_world.y), skeleton[0]);
    for (int i = 0; i < skeleton.size(); i++) {
        skeleton[i] = GLKVector2Add(skeleton[i], translate);
    }
    
    //Get norm vectors for skeleton joints
    vector<GLKVector2> skeletonNormals;
    vector<GLKVector2> skeletonTangents;
    [PAMUtilities normals:skeletonNormals tangents:skeletonTangents forSkeleton:skeleton];
    
    //Parse new skeleton and create ribs
    //Ingore first and last centroids since they are poles
    int numSpines = numOfSpines * 4;
    vector<vector<GLKVector3>> allRibs(skeleton.size());
    vector<GLKVector3> skeletonModel;
    vector<GLKVector3> skeletonNormalsModel;
    for (int i = 0; i < skeleton.size(); i++) {
        GLKVector3 sModel = [Utilities invertVector3:GLKVector3Make(skeleton[i].x, skeleton[i].y, zValueTouched)
                                          withMatrix:self.modelViewMatrix];
        
        //dont preserve translation for norma and tangent
        float ribWidth = skeletonWidth[i];
        GLKVector2 stretchedNorm = GLKVector2MultiplyScalar(skeletonNormals[i], ribWidth);
        GLKVector3 nModel = [Utilities invertVector4:GLKVector4Make(stretchedNorm.x, stretchedNorm.y, 0, 0)
                                          withMatrix:self.modelViewMatrix];
        GLKVector3 tModel = [Utilities invertVector4:GLKVector4Make(skeletonTangents[i].x, skeletonTangents[i].y, 0, 0)
                                          withMatrix:self.modelViewMatrix];
        
        if (i == skeleton.size() - 1) {
            vector<GLKVector3> secondPole;
            secondPole.push_back(sModel);
            allRibs[i] = secondPole;
        } else {
            vector<GLKVector3> ribs(numSpines);
            float rot_step = 360.0f/numSpines;
            for (int j = 0; j < numSpines; j++) {
                float angle = j * rot_step;
                GLKQuaternion quat = GLKQuaternionMakeWithAngleAndVector3Axis(GLKMathDegreesToRadians(angle), GLKVector3Normalize(tModel));
                GLKVector3 newNorm = GLKQuaternionRotateVector3(quat, nModel);
                GLKVector3 newRibPoint = GLKVector3Add(newNorm, sModel);
                ribs[j] = newRibPoint;
            }
            allRibs[i] = ribs;
        }
        
        skeletonModel.push_back(sModel);
        skeletonNormalsModel.push_back(nModel);
    }

    
    //Rotate the whole branch to go along norm vector of the point touched
    {
        GLKVector3 c1 = [Utilities invertVector3:GLKVector3Make(skeleton[0].x, skeleton[0].y, zValueTouched)
                                      withMatrix:self.modelViewMatrix];
        GLKVector3 c2 = [Utilities invertVector3:GLKVector3Make(skeleton[1].x, skeleton[1].y, zValueTouched)
                                      withMatrix:self.modelViewMatrix];
        GLKVector3 cur_dir = GLKVector3Subtract(c2, c1);
        GLKVector3 axisOfRotation = GLKVector3CrossProduct(cur_dir, holeNorm);
        
        float angle = [Utilities signedAngleBetweenReferenceVector3:cur_dir andVector:holeNorm];
        
        GLKQuaternion q_rotate = GLKQuaternionMakeWithAngleAndVector3Axis(angle, GLKVector3Normalize(axisOfRotation));
        
        for (int i = 0; i < allRibs.size(); i++) {
            vector<GLKVector3> ribs = allRibs[i];
            for (int j = 0; j < ribs.size(); j++) {
                GLKVector3 temp = GLKVector3Subtract(ribs[j], c1);
                temp = GLKQuaternionRotateVector3(q_rotate, temp);
                temp = GLKVector3Add(temp, c1);
                ribs[j] = temp;
            }
            allRibs[i] = ribs;
        }
    }
    
    VertexID limbPole = [self populateNewLimb:allRibs];
    assert(is_pole(_manifold, limbPole));
    
    Walker wBase1 = _manifold.walker(limbPole);
    
    for (; valency(_manifold, wBase1.vertex()) != 3; wBase1 = wBase1.next().opp().next());
    HalfEdgeID secondLastBoundary = wBase1.prev().halfedge();
    //    HalfEdgeID secondLastBoundary = wBase1.next().halfedge();
    wBase1 = wBase1.next().opp(); //halfedge of the boundary ring
    HalfEdgeID limbBoundaryHalfEdge = wBase1.halfedge();
    
    [self stitchBranch:boundaryHalfEdge toBody:limbBoundaryHalfEdge];
    
    //smooth
    Walker smoothWalker = _manifold.walker(secondLastBoundary);
    vector<VertexID> verteciesToSmooth;
    for (;!smoothWalker.full_circle(); smoothWalker = smoothWalker.next().opp().next()) {
        verteciesToSmooth.push_back(smoothWalker.next().vertex()); //boundary
        verteciesToSmooth.push_back(smoothWalker.vertex()); //second last boundary
        Walker ws = _manifold.walker(smoothWalker.next().halfedge());
        for (int s = 0; s < numOfSpines + 1; s++) {
            ws = ws.next().opp().next();
            verteciesToSmooth.push_back(ws.vertex());
        }
    }
    _edgeInfo = trace_spine_edges(_manifold);
    laplacian_smooth_vertex(_manifold, verteciesToSmooth, _edgeInfo, 5);
    
    [self rebufferWithCleanup:YES bufferData:YES edgeTrace:YES];

    return vector<vector<GLKVector3>>();
}

-(std::vector<vector<GLKVector3>>)endCreateNewBodyTwoFingers {
    
    if (_touchPoints.size() < 8 || _touchPoints.size() % 2 != 0) {
        NSLog(@"[PolarAnnularMesh][WARNING] Garbage point data");
        return vector<vector<GLKVector3>>();
    }
    
    [self saveState];
    
    //convert touch points to world space
    vector<GLKVector2> touchPointsWorld(_touchPoints.size());
    for (int i = 0; i < _touchPoints.size(); i++)
    {
        GLKVector3 worldSpace3 = [Utilities matrix4:self.viewMatrix multiplyVector3:_touchPoints[i]];
        touchPointsWorld[i] = GLKVector2Make(worldSpace3.x, worldSpace3.y);
    }
    
    //Get skeleton aka joint points
    vector<GLKVector2> rawSkeleton;
    vector<float> skeletonWidth;

    //Find scaled step
    float c_step = GLKVector3Length(GLKMatrix3MultiplyVector3(GLKMatrix4GetMatrix3(self.modelViewMatrix),
                                                              GLKVector3Make(kCENTROID_STEP, 0, 0)));
    [PAMUtilities centroids:rawSkeleton ribWidth:skeletonWidth forTwoFingerTouchPoint:touchPointsWorld withNextCentroidStep:c_step];
    if (rawSkeleton.size() < 4) {
        NSLog(@"[PolarAnnularMesh][WARNING] Not enough controids");
        return vector<vector<GLKVector3>>();
    }
    
    //Smooth
    vector<GLKVector2> skeleton = [PAMUtilities laplacianSmoothing:rawSkeleton iterations:3];

    //Get norm vectors for skeleton joints
    vector<GLKVector2> skeletonNormals;
    vector<GLKVector2> skeletonTangents;
    [PAMUtilities normals:skeletonNormals tangents:skeletonTangents forSkeleton:skeleton];
 
    //Parse new skeleton and create ribs
    //Ingore first and last centroids since they are poles
    int numSpines = 45;
    vector<vector<GLKVector3>> allRibs(skeleton.size());
    vector<GLKVector3> skeletonModel;
    vector<GLKVector3> skeletonNormalsModel;
    for (int i = 0; i < skeleton.size(); i++) {
        GLKVector3 sModel = [Utilities invertVector3:GLKVector3Make(skeleton[i].x, skeleton[i].y, 0)
                                          withMatrix:self.modelViewMatrix];
        
        //dont preserve translation for norma and tangent
        float ribWidth = skeletonWidth[i];
        GLKVector2 stretchedNorm = GLKVector2MultiplyScalar(skeletonNormals[i], ribWidth);
        GLKVector3 nModel = [Utilities invertVector4:GLKVector4Make(stretchedNorm.x, stretchedNorm.y, 0, 0)
                                          withMatrix:self.modelViewMatrix];
        GLKVector3 tModel = [Utilities invertVector4:GLKVector4Make(skeletonTangents[i].x, skeletonTangents[i].y, 0, 0)
                                          withMatrix:self.modelViewMatrix];

        
        if (i == 0) {
            vector<GLKVector3> firstPole;
            firstPole.push_back(sModel);
            allRibs[0] = firstPole;
        } else if (i == skeleton.size() - 1) {
            vector<GLKVector3> secondPole;
            secondPole.push_back(sModel);
            allRibs[i] = secondPole;
        } else {
            vector<GLKVector3> ribs(numSpines);
            float rot_step = 360.0f/numSpines;
            for (int j = 0; j < numSpines; j++) {
                float angle = j * rot_step;
                GLKQuaternion quat = GLKQuaternionMakeWithAngleAndVector3Axis(GLKMathDegreesToRadians(angle), GLKVector3Normalize(tModel));
                GLKVector3 newNorm = GLKQuaternionRotateVector3(quat, nModel);
                GLKVector3 newRibPoint = GLKVector3Add(newNorm, sModel);
                ribs[j] = newRibPoint;
            }
            allRibs[i] = ribs;
        }
        skeletonModel.push_back(sModel);
        skeletonNormalsModel.push_back(nModel);
    }
    
    
//    allRibs.push_back(skeletonNormalsModel);
    
    [self populateManifold:allRibs];
    allRibs.push_back(skeletonModel);
    
    return allRibs;
}

#pragma mark - BRANCH STICHING
-(void)stitchBranch:(HalfEdgeID)branchHID toBody:(HalfEdgeID)bodyHID {
    
    //Align edges
    Walker align1 = _manifold.walker(branchHID);
    VertexID vId1 = align1.vertex();
    Vecf vPos1 = _manifold.posf(vId1);
    
    HalfEdgeID closestHID;
    float closestDist = FLT_MAX;
    
    for (Walker align2 = _manifold.walker(bodyHID); !align2.next().full_circle(); align2 = align2.next()) {
        float cur_dist = (vPos1 - _manifold.posf(align2.vertex())).length();
        
        if (cur_dist < closestDist) {
            closestDist = cur_dist;
            closestHID = align2.halfedge();
        }
    }
    Walker temp = _manifold.walker(closestHID);
    closestHID = temp.next().halfedge();
    
    //Stich boundary edges
    vector<HalfEdgeID> bEdges1;
    vector<HalfEdgeID> bEdges2;
    for (Walker stitch1 = _manifold.walker(closestHID);!stitch1.full_circle(); stitch1 = stitch1.next())
    {
        bEdges1.push_back(stitch1.halfedge());
    }
    bEdges1.pop_back();
    
    for (Walker stitch2 = _manifold.walker(branchHID); !stitch2.full_circle(); stitch2 = stitch2.prev()) {
        bEdges2.push_back(stitch2.halfedge());
    }
    bEdges2.pop_back();
    
    assert(bEdges1.size() == bEdges2.size());
    
    for (int i = 0; i < bEdges1.size() ; i++) {
        BOOL didStich = _manifold.stitch_boundary_edges(bEdges1[i], bEdges2[i]);
        assert(didStich);
    }
    
}


#pragma mark - CREATE BRANCH FROM MESH

-(VertexID)populateNewLimb:(std::vector<vector<GLKVector3>>)allRibs {
    vector<Vecf> vertices;
    vector<int> faces;
    vector<int> indices;
    
    GLKVector3 poleVec;
    
    //Add all verticies
    for (int i = 0; i < allRibs.size(); i++) {
        vector<GLKVector3> rib = allRibs[i];
        for (int j = 0; j < rib.size(); j++) {
            GLKVector3 v = rib[j];
            vertices.push_back(Vecf(v.x, v.y, v.z));
        }
    }
    
    for (int i = 0; i < allRibs.size() - 1; i++) {
        if (i == allRibs.size() - 2) { //pole 2
            vector<GLKVector3> pole = allRibs[i+1];
            vector<GLKVector3> rib = allRibs[i];
            int poleIndex = [self limbIndexForCentroid:i+1 rib:0 totalCentroid:allRibs.size() totalRib:rib.size()];
            Vec3f pV = vertices[poleIndex];
            poleVec = GLKVector3Make(pV[0], pV[1], pV[2]);
            
            for (int j = 0; j < rib.size(); j++) {
                indices.push_back(poleIndex);
                if (j == rib.size() - 1) {
                    int index1 = [self limbIndexForCentroid:i rib:j totalCentroid:allRibs.size() totalRib:rib.size()];
                    int index2 = [self limbIndexForCentroid:i rib:0 totalCentroid:allRibs.size() totalRib:rib.size()];
                    indices.push_back(index1);
                    indices.push_back(index2);
                } else {
                    int index1 = [self limbIndexForCentroid:i rib:j totalCentroid:allRibs.size() totalRib:rib.size()];
                    int index2 = [self limbIndexForCentroid:i rib:j+1 totalCentroid:allRibs.size() totalRib:rib.size()];
                    indices.push_back(index1);
                    indices.push_back(index2);
                }
                faces.push_back(3);
            }
        } else {
            vector<GLKVector3> rib1 = allRibs[i];
            vector<GLKVector3> rib2 = allRibs[i+1];
            
            for (int j = 0; j < rib1.size(); j++) {
                if (j == rib1.size() - 1) {
                    int index1 = [self limbIndexForCentroid:i rib:j totalCentroid:allRibs.size() totalRib:rib1.size()];
                    int index2 = [self limbIndexForCentroid:i rib:0 totalCentroid:allRibs.size() totalRib:rib1.size()];
                    int index3 = [self limbIndexForCentroid:i+1 rib:0 totalCentroid:allRibs.size() totalRib:rib1.size()];
                    int index4 = [self limbIndexForCentroid:i+1 rib:j totalCentroid:allRibs.size() totalRib:rib1.size()];
                    indices.push_back(index1);
                    indices.push_back(index2);
                    indices.push_back(index3);
                    indices.push_back(index4);
                } else {
                    int index1 = [self limbIndexForCentroid:i rib:j totalCentroid:allRibs.size() totalRib:rib1.size()];
                    int index2 = [self limbIndexForCentroid:i rib:j+1 totalCentroid:allRibs.size() totalRib:rib1.size()];
                    int index3 = [self limbIndexForCentroid:i+1 rib:j+1 totalCentroid:allRibs.size() totalRib:rib1.size()];
                    int index4 = [self limbIndexForCentroid:i+1 rib:j totalCentroid:allRibs.size() totalRib:rib1.size()];
                    indices.push_back(index1);
                    indices.push_back(index2);
                    indices.push_back(index3);
                    indices.push_back(index4);
                }
                faces.push_back(4);
            }
        }
    }
    
    _manifold.build(vertices.size(),
                    reinterpret_cast<float*>(&vertices[0]),
                    faces.size(),
                    &faces[0],
                    &indices[0]);
    
    VertexID pole = [self closestVertexID_3D:[Utilities matrix4:self.modelMatrix multiplyVector3:poleVec]];
    assert(is_pole(_manifold, pole));
    
    return pole;
}


-(int)limbIndexForCentroid:(int)centeroid rib:(int)rib totalCentroid:(int)totalCentroid totalRib:(int)totalRib
{
    if (centeroid == totalCentroid - 1) {
        return (totalCentroid - 1)*totalRib + 1 - 1;
    } else {
        return centeroid*totalRib + rib;
    }
}


-(void)populateManifold:(std::vector<vector<GLKVector3>>)allRibs {
    vector<Vecf> vertices;
    vector<int> faces;
    vector<int> indices;
    
    //Add all verticies
    for (int i = 0; i < allRibs.size(); i++) {
        vector<GLKVector3> rib = allRibs[i];
        for (int j = 0; j < rib.size(); j++) {
            GLKVector3 v = rib[j];
            vertices.push_back(Vecf(v.x, v.y, v.z));
        }
    }
    
    for (int i = 0; i < allRibs.size() - 1; i++) {
        
        if (i == 0) { //pole 1
            vector<GLKVector3> pole = allRibs[i];
            vector<GLKVector3> rib = allRibs[i+1];
            int poleIndex = 0;
            for (int j = 0; j < rib.size(); j++) {
                indices.push_back(poleIndex);
                if (j == rib.size() - 1) {
                    int index1 = [self indexForCentroid:1 rib:j totalCentroid:allRibs.size() totalRib:rib.size()];
                    int index2 = [self indexForCentroid:1 rib:0 totalCentroid:allRibs.size() totalRib:rib.size()];
                    indices.push_back(index2);
                    indices.push_back(index1);
                } else {
                    int index1 = [self indexForCentroid:1 rib:j totalCentroid:allRibs.size() totalRib:rib.size()];
                    int index2 = [self indexForCentroid:1 rib:j+1 totalCentroid:allRibs.size() totalRib:rib.size()];
                    indices.push_back(index2);
                    indices.push_back(index1);
                }
                faces.push_back(3);
            }
        } else if (i == allRibs.size() - 2) { //pole 2
            vector<GLKVector3> pole = allRibs[i+1];
            vector<GLKVector3> rib = allRibs[i];
            int poleIndex = [self indexForCentroid:i+1 rib:0 totalCentroid:allRibs.size() totalRib:rib.size()];
            for (int j = 0; j < rib.size(); j++) {
                indices.push_back(poleIndex);
                if (j == rib.size() - 1) {
                    int index1 = [self indexForCentroid:i rib:j totalCentroid:allRibs.size() totalRib:rib.size()];
                    int index2 = [self indexForCentroid:i rib:0 totalCentroid:allRibs.size() totalRib:rib.size()];
                    indices.push_back(index1);
                    indices.push_back(index2);
                } else {
                    int index1 = [self indexForCentroid:i rib:j totalCentroid:allRibs.size() totalRib:rib.size()];
                    int index2 = [self indexForCentroid:i rib:j+1 totalCentroid:allRibs.size() totalRib:rib.size()];
                    indices.push_back(index1);
                    indices.push_back(index2);
                }
                faces.push_back(3);
            }
        } else {
            vector<GLKVector3> rib1 = allRibs[i];
            vector<GLKVector3> rib2 = allRibs[i+1];
            
            for (int j = 0; j < rib1.size(); j++) {
                if (j == rib1.size() - 1) {
                    int index1 = [self indexForCentroid:i rib:j totalCentroid:allRibs.size() totalRib:rib1.size()];
                    int index2 = [self indexForCentroid:i rib:0 totalCentroid:allRibs.size() totalRib:rib1.size()];
                    int index3 = [self indexForCentroid:i+1 rib:0 totalCentroid:allRibs.size() totalRib:rib1.size()];
                    int index4 = [self indexForCentroid:i+1 rib:j totalCentroid:allRibs.size() totalRib:rib1.size()];
                    indices.push_back(index1);
                    indices.push_back(index2);
                    indices.push_back(index3);
                    indices.push_back(index4);
                } else {
                    int index1 = [self indexForCentroid:i rib:j totalCentroid:allRibs.size() totalRib:rib1.size()];
                    int index2 = [self indexForCentroid:i rib:j+1 totalCentroid:allRibs.size() totalRib:rib1.size()];
                    int index3 = [self indexForCentroid:i+1 rib:j+1 totalCentroid:allRibs.size() totalRib:rib1.size()];
                    int index4 = [self indexForCentroid:i+1 rib:j totalCentroid:allRibs.size() totalRib:rib1.size()];
                    indices.push_back(index1);
                    indices.push_back(index2);
                    indices.push_back(index3);
                    indices.push_back(index4);
                }
                faces.push_back(4);
            }
        }
    }
    
    _manifold.clear();
    _manifold.build(vertices.size(),
                    reinterpret_cast<float*>(&vertices[0]),
                    faces.size(),
                    &faces[0],
                    &indices[0]);
    
    //    _branchWidth = 1;
    modState = MODIFICATION_NONE;
    
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
    
//    polar_subdivide(_manifold, 1);
//    taubin_smooth(_manifold, 10);
    laplacian_smooth(_manifold, 1.0, 3);
    [self rebufferWithCleanup:YES bufferData:YES edgeTrace:YES];
}

-(int)indexForCentroid:(int)centeroid rib:(int)rib totalCentroid:(int)totalCentroid totalRib:(int)totalRib
{
    if (centeroid == 0) {
        return 0;
    } else if (centeroid == totalCentroid - 1) {
        return (totalCentroid - 2)*totalRib + 2 - 1;
    } else {
        return 1 + (centeroid - 1)*totalRib + rib;
    }
}


#pragma mark - UTILITIES: COMMON BENDING FUCNTIONS
-(void)createPinPoint:(GLKVector3)touchPoint
{
    VertexID vID = [self closestVertexID_3D:touchPoint];
    
    Walker walker = _manifold.walker(vID).opp();
    while (_edgeInfo[walker.halfedge()].edge_type != RIB) {
        walker = walker.next();
    }
    
    assert(_edgeInfo[walker.halfedge()].edge_type == RIB);
    
    _pinHalfEdgeID = walker.halfedge();
    
    vector<VertexID> verticies;
    for (Walker ringWalker = _manifold.walker(walker.halfedge());
         !ringWalker.full_circle();
         ringWalker = ringWalker.next().opp().next())
    {
        verticies.push_back(ringWalker.vertex());
    }
    [self changeVerticiesColor:verticies toSelected:YES];
}

-(void)createPivotPoint:(GLKVector3)touchPoint
{
    VertexID vID = [self closestVertexID_3D:touchPoint];
    
    Walker walker = _manifold.walker(vID).opp();
    while (_edgeInfo[walker.halfedge()].edge_type != RIB) {
        walker = walker.next();
    }
    assert(_edgeInfo[walker.halfedge()].edge_type == RIB);
    
    _pivotHalfEdgeID = walker.halfedge();
    
    vector<VertexID> verticies;
    for (Walker ringWalker = _manifold.walker(walker.halfedge());
         !ringWalker.full_circle();
         ringWalker = ringWalker.next().opp().next())
    {
        verticies.push_back(ringWalker.vertex());
    }
    [self changeVerticiesColor:verticies toSelected:YES];
}

-(Walker)pivotDirection
{
    //    int pin_loop_id = _edgeInfo[_pinHalfEdgeID].id;
    int pivot_loop_id = _edgeInfo[_pivotHalfEdgeID].id;
    
    //find which way is the pivot
    Walker w1 = _manifold.walker(_pinHalfEdgeID).next();
    Walker w2 = w1.opp().next().opp().next();
    Walker sW = w1;
    Walker sW1 = w1;
    Walker sW2 = w2;
    
    while (true) {
        HalfEdgeID hID = w1.next().halfedge();
        HalfEdgeID hID2 = w2.next().halfedge();
        
        if (_edgeInfo[hID].id == pivot_loop_id) {
            sW = sW1;
            break;
        } else if (_edgeInfo[hID2].id == pivot_loop_id) {
            sW = sW2;
            break;
        }
        
        if (_edgeInfo[hID].edge_type != RIB_JUNCTION) {
            w1 = w1.next().opp().next();
        }
        
        if (_edgeInfo[hID2].edge_type != RIB_JUNCTION) {
            w2 = w2.next().opp().next();
        }
    }
    
    return sW;
}

-(void)setDeformableAreas {
    number_rib_edges(_manifold, _edgeInfo); // number rings
    Walker pivotDir = [self pivotDirection]; //spine towards the pivot
    _deformDirHalfEdge = pivotDir.halfedge();
    assert(_edgeInfo[pivotDir.halfedge()].is_spine());
    
    //    int pin_loop_id = _edgeInfo[_pinHalfEdgeID].id;
    int pivot_loop_id = _edgeInfo[_pivotHalfEdgeID].id;
    
    map<VertexID, int> vertexToLoop;
    vector<int> loopsToDeform;
    map<int, float> ringToDeformValue;
    
    //Go through transition area. Stop when pointing to the loop containing pivot.
    //Assigh loopID for every vertex along the way
    HalfEdgeID loopRib = pivotDir.next().halfedge();
    int loopID = _edgeInfo[loopRib].id;
    while (loopID != pivot_loop_id) {
        loopsToDeform.push_back(loopID);
        vector<VertexID> verticies = verticies_along_the_rib(_manifold, loopRib, _edgeInfo);
        for (VertexID vID: verticies) {
            vertexToLoop[vID] = loopID;
        }
        pivotDir = pivotDir.next().opp().next();
        loopRib = pivotDir.next().halfedge();
        loopID = _edgeInfo[loopRib].id;
    }
    
    //Get centroid for future rotation
    Vec3f centr = centroid_for_rib(_manifold, pivotDir.next().halfedge(), _edgeInfo);
    _centerOfRotation = GLKVector3Make(centr[0], centr[1], centr[2]);
    
    //Assign weight deformation for angle to the loops
    for (int i = 0; i < loopsToDeform.size(); i++) {
        
        int lID = loopsToDeform[i];
        
        //linear interpolation
        //        float weight = (float)i/loopsToDeform.size();
        //        ringToDeformValue[lID] = weight;
        
        //gaussian
//        float r = loopsToDeform.size();
//        float l = i*i;
//        float weight = exp(-l/(0.5*r*r));
//        ringToDeformValue[lID] = 1-weight;
        
        //karan's
        float r = loopsToDeform.size();
        float x = i/r;
        float weight = pow(pow(x, 2)-1, 2);
        ringToDeformValue[lID] = 1-weight;

    }
    
    _vertexToLoop = vertexToLoop;
    _loopsToDeform = loopsToDeform;
    _ringToDeformValue = ringToDeformValue;
    
    //Flood rotational area
    HalfEdgeAttributeVector<EdgeInfo> sEdgeInfo(_manifold.allocated_halfedges());
    Walker bWalker = _manifold.walker(pivotDir.next().halfedge()); //Walk along pivot boundary loop
    queue<HalfEdgeID> hq;
    
    for (;!bWalker.full_circle(); bWalker = bWalker.next().opp().next()) {
        HalfEdgeID hID = bWalker.next().halfedge();
        HalfEdgeID opp_hID = bWalker.next().opp().halfedge();
        sEdgeInfo[hID] = EdgeInfo(SPINE, 0);
        sEdgeInfo[opp_hID] = EdgeInfo(SPINE, 0);
        hq.push(hID);
    }
    
    set<VertexID> floodVerticiesSet;
    while(!hq.empty())
    {
        HalfEdgeID h = hq.front();
        Walker w = _manifold.walker(h);
        hq.pop();
        bool is_spine = _edgeInfo[h].edge_type == SPINE;
        for (;!w.full_circle(); w=w.circulate_vertex_ccw(),is_spine = !is_spine) {
            if(sEdgeInfo[w.halfedge()].edge_type == UNKNOWN)
            {
                EdgeInfo ei = is_spine ? EdgeInfo(SPINE,0) : EdgeInfo(RIB,0);
                
                floodVerticiesSet.insert(w.vertex());
                floodVerticiesSet.insert(w.opp().vertex());
                
                sEdgeInfo[w.halfedge()] = ei;
                sEdgeInfo[w.opp().halfedge()] = ei;
                hq.push(w.opp().halfedge());
            }
        }
    }
    
    vector<VertexID> floodVerticiesVector(floodVerticiesSet.begin(), floodVerticiesSet.end());
    _all_vector_vid = floodVerticiesVector;
    [self changeVerticiesColor:floodVerticiesVector toSelected:YES];
}
#pragma mark - TRANSLATION OF THE BRANCH TREE

-(void)startTranslatingBranchTreeWithTouchPoint:(GLKVector3)touchPoint
                                    translation:(GLKVector3)translation
{
    if (![self manifoldIsLoaded]) {
        return;
    }
    
    [self createPivotPoint:touchPoint];
    [self setDeformableAreas];
    
    _translation = translation;
    modState = MODIFICATION_BRANCH_TRANSLATION;
    _current_rot_position = VertexAttributeVector<Vecf>(_manifold.no_vertices());
    
}

-(void)continueTranslatingBranchTree:(GLKVector3)translation
{
    if (![self manifoldIsLoaded])
        return;
    
    _translation = translation;
}

-(void)endTranslatingBranchTree:(GLKVector3)translation
{
    if (![self manifoldIsLoaded])
        return;
    
    _translation = translation;
    
    GLKMatrix4 toOrigin = GLKMatrix4MakeTranslation(-_centerOfRotation.x, -_centerOfRotation.y, -_centerOfRotation.z);
    GLKMatrix4 fromOrigin = GLKMatrix4MakeTranslation(_centerOfRotation.x, _centerOfRotation.y, _centerOfRotation.z);
    GLKMatrix4 translationMatrix = GLKMatrix4MakeTranslation(_translation.x, _translation.y, _translation.z);
    GLKMatrix4 tMatrix = GLKMatrix4Multiply(GLKMatrix4Multiply(fromOrigin, translationMatrix), toOrigin);
    
    for (VertexID vID: _all_vector_vid) {
        Vec pos = _manifold.pos(vID);
        GLKVector3 posGLK = GLKVector3Make(pos[0], pos[1], pos[2]);
        GLKVector3 newPosGLK = [Utilities matrix4:tMatrix multiplyVector3:posGLK];
        Vec newPos = Vec(newPosGLK.x, newPosGLK.y, newPosGLK.z);
        _manifold.pos(vID) = newPos;
    }

    //deformable area
    map<int,GLKMatrix4> scaleMatricies;
    for (auto lid: _loopsToDeform) {
        float weight = _ringToDeformValue[lid];
        GLKVector3 t = GLKVector3MultiplyScalar(_translation, weight);
        GLKMatrix4 translatioMatrix = GLKMatrix4MakeTranslation(t.x, t.y, t.z);
        scaleMatricies[lid]= translatioMatrix;
    }
    
    for (auto it = _vertexToLoop.begin(); it!=_vertexToLoop.end(); ++it) {
        VertexID vid = it->first;
        int lid = it->second;
        
        GLKMatrix4 translationMatrix = scaleMatricies[lid];
        GLKMatrix4 tMatrix = GLKMatrix4Multiply(GLKMatrix4Multiply(fromOrigin, translationMatrix), toOrigin);
        
        Vec pos = _manifold.pos(vid);
        GLKVector3 posGLK = GLKVector3Make(pos[0], pos[1], pos[2]);
        GLKVector3 newPosGLK = [Utilities matrix4:tMatrix multiplyVector3:posGLK];
        Vec newPos = Vec(newPosGLK.x, newPosGLK.y, newPosGLK.z);
        
        _manifold.pos(vid) = newPos;
    }

    
    
    modState = MODIFICATION_NONE;
    _all_vector_vid.clear();
    
    [self rotateRingsFrom:_deformDirHalfEdge toRingID:_pivotHalfEdgeID];
    
    [self rebufferWithCleanup:NO bufferData:YES edgeTrace:NO];

}

#pragma mark - SCALING THE BRANCH TREE

-(void)startScalingBranchTreeWithTouchPoint:(GLKVector3)touchPoint scale:(float)scale {
    if (![self manifoldIsLoaded]) {
        return;
    }
    
    [self createPivotPoint:touchPoint];
    [self setDeformableAreas];
    
    _scaleFactor = scale;
    modState = MODIFICATION_BRANCH_SCALING;
    _current_rot_position = VertexAttributeVector<Vecf>(_manifold.no_vertices());
}

-(void)continueScalingBranchTreeWithScale:(float)scale {
    if (![self manifoldIsLoaded])
        return;
    
    _scaleFactor = scale;
}

-(void)endScalingBranchTreeWithScale:(float)scale {
    if (![self manifoldIsLoaded])
        return;
    
    _scaleFactor = scale;
    
    GLKMatrix4 toOrigin = GLKMatrix4MakeTranslation(-_centerOfRotation.x, -_centerOfRotation.y, -_centerOfRotation.z);
    GLKMatrix4 fromOrigin = GLKMatrix4MakeTranslation(_centerOfRotation.x, _centerOfRotation.y, _centerOfRotation.z);
    GLKMatrix4 scaleMatrix = GLKMatrix4MakeScale(_scaleFactor, _scaleFactor, _scaleFactor);
    GLKMatrix4 tMatrix = GLKMatrix4Multiply(GLKMatrix4Multiply(fromOrigin, scaleMatrix), toOrigin);
    
    for (VertexID vID: _all_vector_vid) {
        Vec pos = _manifold.pos(vID);
        GLKVector3 posGLK = GLKVector3Make(pos[0], pos[1], pos[2]);
        GLKVector3 newPosGLK = [Utilities matrix4:tMatrix multiplyVector3:posGLK];
        Vec newPos = Vec(newPosGLK.x, newPosGLK.y, newPosGLK.z);
        _manifold.pos(vID) = newPos;
    }
    
    //deformable area
    map<int,GLKMatrix4> scaleMatricies;
    for (auto lid: _loopsToDeform) {
        float weight = _ringToDeformValue[lid];
        float scale = 1 + (_scaleFactor - 1)*weight;
        GLKMatrix4 sMatrix = GLKMatrix4MakeScale(scale, scale, scale);
        scaleMatricies[lid]=sMatrix;
    }
    
    for (auto it = _vertexToLoop.begin(); it!=_vertexToLoop.end(); ++it) {
        VertexID vid = it->first;
        int lid = it->second;
        
        GLKMatrix4 scaleMatrix = scaleMatricies[lid];
        GLKMatrix4 tMatrix = GLKMatrix4Multiply(GLKMatrix4Multiply(fromOrigin, scaleMatrix), toOrigin);
        
        Vec pos = _manifold.pos(vid);
        GLKVector3 posGLK = GLKVector3Make(pos[0], pos[1], pos[2]);
        GLKVector3 newPosGLK = [Utilities matrix4:tMatrix multiplyVector3:posGLK];
        Vec newPos = Vec(newPosGLK.x, newPosGLK.y, newPosGLK.z);
        _manifold.pos(vid) = newPos;
    }
    
    modState = MODIFICATION_NONE;
    _all_vector_vid.clear();
    
    [self rebufferWithCleanup:NO bufferData:YES edgeTrace:NO];
}

#pragma mark - ROTATION THE BRANCH TREE

-(void)startBendingWithTouhcPoint:(GLKVector3)touchPoint angle:(float)angle {
    if (![self manifoldIsLoaded]) {
        return;
    }
    
    [self createPivotPoint:touchPoint];
    [self setDeformableAreas];
    
    _rotAngle = angle;
    modState = MODIFICATION_BRANCH_ROTATION;
    _current_rot_position = VertexAttributeVector<Vecf>(_manifold.no_vertices());
}

-(void)continueBendingWithWithAngle:(float)angle {
    if (![self manifoldIsLoaded])
        return;
    
    _rotAngle = angle;
}

-(void)endBendingWithAngle:(float)angle {
    if (![self manifoldIsLoaded])
        return;
    
    GLKVector3 zAxis = GLKMatrix4MultiplyVector3(GLKMatrix4Invert(self.viewMatrix, NULL), GLKVector3Make(0, 0, -1));
    GLKMatrix4 toOrigin = GLKMatrix4MakeTranslation(-_centerOfRotation.x, -_centerOfRotation.y, -_centerOfRotation.z);
    GLKMatrix4 rotMatrix = GLKMatrix4MakeRotation(angle, zAxis.x, zAxis.y, zAxis.z);
    GLKMatrix4 fromOrigin = GLKMatrix4MakeTranslation(_centerOfRotation.x, _centerOfRotation.y, _centerOfRotation.z);
    GLKMatrix4 tMatrix = GLKMatrix4Multiply(GLKMatrix4Multiply(fromOrigin, rotMatrix), toOrigin);
    
    for (VertexID vID: _all_vector_vid) {
        Vec pos = _manifold.pos(vID);
        GLKVector3 posGLK = GLKVector3Make(pos[0], pos[1], pos[2]);
        GLKVector3 newPosGLK = [Utilities matrix4:tMatrix multiplyVector3:posGLK];
        Vec newPos = Vec(newPosGLK.x, newPosGLK.y, newPosGLK.z);
        _manifold.pos(vID) = newPos;
    }
    
    //deformable area
    map<int,GLKMatrix4> rotMatricies;
    for (auto lid: _loopsToDeform) {
        float weight = _ringToDeformValue[lid];
        float angle = weight * _rotAngle;
        GLKMatrix4 rotMatrix = GLKMatrix4MakeRotation(angle, zAxis.x, zAxis.y, zAxis.z);
        GLKMatrix4 tMatrix = GLKMatrix4Multiply(GLKMatrix4Multiply(fromOrigin, rotMatrix), toOrigin);
        rotMatricies[lid]=tMatrix;
    }
    
    for (auto it = _vertexToLoop.begin(); it!=_vertexToLoop.end(); ++it) {
        VertexID vid = it->first;
        int lid = it->second;
        GLKMatrix4 tMatrix = rotMatricies[lid];
        
        Vec pos = _manifold.pos(vid);
        GLKVector3 posGLK = GLKVector3Make(pos[0], pos[1], pos[2]);
        GLKVector3 newPosGLK = [Utilities matrix4:tMatrix multiplyVector3:posGLK];
        Vec newPos = Vec(newPosGLK.x, newPosGLK.y, newPosGLK.z);
        _manifold.pos(vid) = newPos;
    }

    modState = MODIFICATION_NONE;
    _all_vector_vid.clear();
    
    [self rotateRingsFrom:_deformDirHalfEdge toRingID:_pivotHalfEdgeID];
    
    [self rebufferWithCleanup:NO bufferData:YES edgeTrace:NO];
}


-(void)rotateRingsFrom:(HalfEdgeID)pivotDirHID toRingID:(HalfEdgeID)pivotHalfEdge  {
    //Get all centroids
    vector<GLKVector3> centroids;
    vector<vector<VertexID>> allVerticies;
    vector<GLKVector3> currentNorms;
    vector<GLKVector3> desiredNorms;
    

    Walker pivotDir = _manifold.walker(pivotDirHID);
    
    //Get a centroid before the first one. For better quality
    Vec3f cOpp = centroid_for_rib(_manifold, pivotDir.opp().next().halfedge(), _edgeInfo);
    GLKVector3 centroidBeforeFirst = GLKVector3Make(cOpp[0], cOpp[1], cOpp[2]);
    
    HalfEdgeID loopRib = pivotDir.next().halfedge();
    int loopID = _edgeInfo[loopRib].id;
    int pivot_loop_id = _edgeInfo[_pivotHalfEdgeID].id;
    while (loopID != pivot_loop_id) {
        Vec3f c = centroid_for_rib(_manifold, loopRib, _edgeInfo);
        centroids.push_back(GLKVector3Make(c[0], c[1], c[2]));
        vector<VertexID> verticies = verticies_along_the_rib(_manifold, loopRib, _edgeInfo);
        allVerticies.push_back(verticies);

        Mat3x3d cov(0);
        for (int i = 0; i < verticies.size(); i++) {
            VertexID vID = verticies[i];
            Vec pos = _manifold.pos(vID);
            Vec d = pos - Vec(c);
            Mat3x3d m;
            outer_product(d,d,m);
            cov += m;
        }
        
        Mat3x3d Q, L;
        int sol = power_eigensolution(cov, Q, L);
        
        Vec3d n;
        assert(sol>=2);
        n = normalize(cross(Q[0],Q[1]));
        currentNorms.push_back(GLKVector3Make(n[0], n[1], n[2]));
        
        pivotDir = pivotDir.next().opp().next();
        loopRib = pivotDir.next().halfedge();
        loopID = _edgeInfo[loopRib].id;
    }
    
    //Get a centroid after the last one. For better quality
    Vec3f cLast = centroid_for_rib(_manifold, pivotDir.next().halfedge(), _edgeInfo);
    GLKVector3 centroidAfterLast = GLKVector3Make(cLast[0], cLast[1], cLast[2]);
    
    assert(centroids.size() == currentNorms.size());
    
    if (centroids.size() < 3) {
        NSLog(@"[WARNING][PolarAnnularMesh] Deformable area");
        return;
    }
    
    //Get desired norms
    for (int i = 0; i < centroids.size(); i++) {
        GLKVector3 v1, v2;
        if (i == 0) {
            v1 = GLKVector3Subtract(centroids[1], centroids[0]);
            v2 = GLKVector3Subtract(centroids[0], centroidBeforeFirst);
        } else if (i == (centroids.size() - 1)) {
            v1 = GLKVector3Subtract(centroidAfterLast, centroids[i]);
            v2 = GLKVector3Subtract(centroids[i], centroids[i-1]);
        } else {
            v1 = GLKVector3Subtract(centroids[i], centroids[i-1]);
            v2 = GLKVector3Subtract(centroids[i+1], centroids[i]);
        }
        GLKVector3 n = GLKVector3Lerp(v1, v2, 0.5f);
        desiredNorms.push_back(n);
    }
    
    assert(desiredNorms.size() == currentNorms.size());
    
    //Rotate norms
    NSLog(@"***");
    for (int i = 0; i < centroids.size(); i++) {
        GLKVector3 axisOfRotation = GLKVector3Normalize(GLKVector3CrossProduct(currentNorms[i], desiredNorms[i]));
        float angle = [Utilities signedAngleBetweenReferenceVector3:currentNorms[i]
                                                          andVector:desiredNorms[i]];
        
        if (angle > M_PI_2) {
            angle = -1*(M_PI - angle);
        }
        NSLog(@"Angle:%f", angle);
        
        
        GLKMatrix4 toOrigin = GLKMatrix4MakeTranslation(-centroids[i].x, -centroids[i].y, -centroids[i].z);
        GLKMatrix4 rotMatrix = GLKMatrix4MakeRotation(angle, axisOfRotation.x, axisOfRotation.y, axisOfRotation.z);
        GLKMatrix4 fromOrigin = GLKMatrix4MakeTranslation(centroids[i].x, centroids[i].y, centroids[i].z);
        GLKMatrix4 tMatrix = GLKMatrix4Multiply(GLKMatrix4Multiply(fromOrigin, rotMatrix), toOrigin);
        
        vector<VertexID> verticies = allVerticies[i];
        for (VertexID vid: verticies) {
            Vec pos = _manifold.pos(vid);
            GLKVector3 posGLK = GLKVector3Make(pos[0], pos[1], pos[2]);
            GLKVector3 newPosGLK = [Utilities matrix4:tMatrix multiplyVector3:posGLK];
            Vec newPos = Vec(newPosGLK.x, newPosGLK.y, newPosGLK.z);
            _manifold.pos(vid) = newPos;
        }
    }
}


#pragma mark - TOUCHES: FACE PICKING

-(void)endSelectFaceWithRay:(GLKVector3)rayOrigin rayDirection:(GLKVector3)rayDir
{
    BOOL didHitModel;
    FaceID fid = [self closestFaceForRayOrigin:rayOrigin direction:rayDir didHitModel:&didHitModel];
    if (didHitModel) {
//        [self changeFaceColorToSelected:fid toSelected:YES];
    }
}

#pragma mark - TOUCHES: SINGLE RING SCALING
//middlePoint - centroid between tow fingers of a pinch gesture
-(void)startScalingSingleRibWithTouchPoint1:(GLKVector3)touchPoint1
                                touchPoint2:(GLKVector3)touchPoint2
                                      scale:(float)scale
                                   velocity:(float)velocity
{
    if (![self manifoldIsLoaded]) {
        return;
    }
    
//    GLKVector3 middlePoint = GLKVector3Lerp(touchPoint1, touchPoint2, 0.5f);
    VertexID vID = [self closestVertexID_2D:touchPoint1];
    if (is_pole(_manifold, vID)) {
        return;
    }

    Walker ribWalker = _manifold.walker(vID);
    if (_edgeInfo[ribWalker.halfedge()].is_spine()) {
        ribWalker = ribWalker.opp().next();
    }
    assert(_edgeInfo[ribWalker.halfedge()].is_rib());
    
    [self saveState];
    
    _edges_to_scale.clear();
    _all_vector_vid.clear();
    
    Walker upWalker = _manifold.walker(ribWalker.next().halfedge());
    Walker downWalker = _manifold.walker(ribWalker.opp().next().halfedge());

    Vec origin = _manifold.pos(vID);
    float brushSize = 0.1;
    vector<float> allDistances;
    
    vector<VertexID> vector_vid;
    float distance = (origin - _manifold.pos(upWalker.vertex())).length();
    while (distance <= brushSize) {
        if (is_pole(_manifold, upWalker.vertex())) {
            break;
        }
        _edges_to_scale.push_back(upWalker.next().halfedge());
        vector_vid = verticies_along_the_rib(_manifold, upWalker.next().halfedge(), _edgeInfo);
        _all_vector_vid.insert(_all_vector_vid.end(), vector_vid.begin(), vector_vid.end());
        allDistances.push_back(distance);
        upWalker = upWalker.next().opp().next();
        distance = (origin - _manifold.pos(upWalker.vertex())).length();
    }

    distance = 0;
    allDistances.push_back(distance);
    _edges_to_scale.push_back(ribWalker.halfedge());
    vector_vid = verticies_along_the_rib(_manifold, ribWalker.halfedge(), _edgeInfo);
    _all_vector_vid.insert(_all_vector_vid.end(), vector_vid.begin(), vector_vid.end());
    
    distance = (origin - _manifold.pos(downWalker.vertex())).length();
    while (distance <= brushSize) {
        if (is_pole(_manifold, downWalker.vertex())) {
            break;
        }
        _edges_to_scale.push_back(downWalker.next().halfedge());
        vector_vid = verticies_along_the_rib(_manifold, downWalker.next().halfedge(), _edgeInfo);
        _all_vector_vid.insert(_all_vector_vid.end(), vector_vid.begin(), vector_vid.end());
        allDistances.push_back(distance);
        downWalker = downWalker.next().opp().next();
        distance = (origin - _manifold.pos(downWalker.vertex())).length();
    }
    
    _current_scale_position = VertexAttributeVector<Vecf>(_manifold.no_vertices());
    
    _scaleFactor = scale;
    
    //Calculate centroids and gaussian weights
    _centroids = centroid_for_ribs(_manifold, _edges_to_scale, _edgeInfo);
    assert(_centroids.size() == allDistances.size());

    _scale_weight_vector.clear();
    if (_centroids.size() == 1) {
        _scale_weight_vector.push_back(1.0f);
    } else {
        for(int i = 0; i < _centroids.size(); i++)
        {
            float distance = allDistances[i];
            float x = distance/brushSize;
            float weight;
            if (x <= 1) {
                weight = pow(pow(x, 2) - 1, 2);
            } else {
                weight = 0;
            }
            _scale_weight_vector.push_back(weight);
        }
    }
    
    modState = MODIFICATION_SCALING;
}

-(void)changeScalingSingleRibWithScaleFactor:(float)scale {
    if (![self manifoldIsLoaded])
        return;
    
    _scaleFactor = scale;
}

-(void)endScalingSingleRibWithScaleFactor:(float)scale {
    
    if (![self manifoldIsLoaded])
        return;
    
    for (int i = 0; i < _edges_to_scale.size(); i++) {
        change_rib_radius(_manifold, _edges_to_scale[i], _centroids[i], _edgeInfo, 1 + (_scaleFactor - 1)*_scale_weight_vector[i]); //update _manifold
    }
    
    modState = MODIFICATION_NONE;
    
    _edges_to_scale.clear();
    _all_vector_vid.clear();
    
    [self rebufferWithCleanup:NO bufferData:YES edgeTrace:NO];
}



#pragma mark - TOUCHES: MULTIPLE RING SCALING
-(void)startScalingRibsWithRayOrigin1:(GLKVector3)rayOrigin1
                           rayOrigin2:(GLKVector3)rayOrigin2
                        rayDirection1:(GLKVector3)rayDir1
                        rayDirection2:(GLKVector3)rayDir2
                                scale:(float)scale
{
    if (![self manifoldIsLoaded])
        return;
    
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
    [self changeVerticiesColor:_all_vector_vid toSelected:YES];
    
    NSLog(@"Finished calling begin scalling funtion");
}

-(void)changeScalingRibsWithScaleFactor:(float)scale {
    if (![self manifoldIsLoaded])
        return;
    
    _scaleFactor = scale;
}

-(void)endScalingRibsWithScaleFactor:(float)scale {
    
    if (![self manifoldIsLoaded])
        return;
    
    for (int i = 0; i < _edges_to_scale.size(); i++) {
        change_rib_radius(_manifold, _edges_to_scale[i], _centroids[i], _edgeInfo, 1 + (_scaleFactor - 1)*_scale_weight_vector[i]); //update _manifold
    }

    [self changeVerticiesColor:_all_vector_vid toSelected:NO];
    
    modState = MODIFICATION_NONE;

    _edges_to_scale.clear();
    _all_vector_vid.clear();
    
    [self rebufferWithCleanup:NO bufferData:YES edgeTrace:NO];
}
 
#pragma mark - SELECTION

-(void)changeWireFrameColor:(vector<HMesh::VertexID>)vertecies toSelected:(BOOL)isSelected {
    
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

-(void)changeVerticiesColor:(vector<HMesh::VertexID>) vertecies toSelected:(BOOL)isSelected {
    
    Vec4uc selectColor;
    if (isSelected) {
        selectColor = Vec4uc(240, 0, 0, 255);
    } else {
        selectColor = Vec4uc(0,0,0,255);
    }
    
    [self.colorDataBuffer bind];
    unsigned char* temp = (unsigned char*) glMapBufferOES(GL_ARRAY_BUFFER, GL_WRITE_ONLY_OES);
    for (VertexID vid: vertecies) {
        int index = vid.index;
        memcpy(temp + index*COLOR_SIZE, selectColor.get(), COLOR_SIZE);
    }
    glUnmapBufferOES(GL_ARRAY_BUFFER);
    glBindBuffer(GL_ARRAY_BUFFER, 0);
}



-(void)changeFacesColorToSelected:(vector<HMesh::FaceID>)fids toSelected:(BOOL)isSelected {
    vector<VertexID> vIDs;
    for (FaceID fid: fids) {
        for(Walker w = _manifold.walker(fid); !w.full_circle(); w = w.circulate_face_cw()) {
            VertexID vid = w.vertex();
            vIDs.push_back(vid);
        }
    }

    Vec4uc selectColor;
    if (isSelected) {
        selectColor = Vec4uc(240, 0, 0, 255);
    } else {
        selectColor = Vec4uc(0,0,0,255);
    }
    
    [self.colorDataBuffer bind];
    unsigned char* temp = (unsigned char*) glMapBufferOES(GL_ARRAY_BUFFER, GL_WRITE_ONLY_OES);
    for (VertexID vid: vIDs) {
        int index = vid.index;
        memcpy(temp + index*COLOR_SIZE, selectColor.get(), COLOR_SIZE);
    }
    glUnmapBufferOES(GL_ARRAY_BUFFER);
    glBindBuffer(GL_ARRAY_BUFFER, 0);
}

//-(void)changeFaceColorToSelected:(FaceID)fid toSelected:(BOOL)isSelected {
//
//    vector<int> indicies;
//    for(Walker w = _manifold.walker(fid); !w.full_circle(); w = w.circulate_face_cw()) {
//        VertexID vid = w.vertex();
//        int index = vid.index;
//        indicies.push_back(index);
//    }
//    
//    Vec4uc selectColor;
//    if (isSelected) {
//        selectColor =  Vec4uc(240, 0, 0, 255);
//    } else {
//        selectColor = Vec4uc(200,200,200,255);
//    }
//    
//    [self.wireframeColorDataBuffer bind];
//    unsigned char* temp = (unsigned char*) glMapBufferOES(GL_ARRAY_BUFFER, GL_WRITE_ONLY_OES);
//    for (int index: indicies) {
//        memcpy(temp + index*COLOR_SIZE, selectColor.get(), COLOR_SIZE);
//    }
//    glUnmapBufferOES(GL_ARRAY_BUFFER);
//    glBindBuffer(GL_ARRAY_BUFFER, 0);
//}

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
    else if (modState == MODIFICATION_BRANCH_ROTATION)
    {
        GLKVector3 zAxis = GLKMatrix4MultiplyVector3(GLKMatrix4Invert(self.viewMatrix, NULL), GLKVector3Make(0, 0, -1));
        GLKMatrix4 toOrigin = GLKMatrix4MakeTranslation(-_centerOfRotation.x, -_centerOfRotation.y, -_centerOfRotation.z);
        GLKMatrix4 rotMatrix = GLKMatrix4MakeRotation(_rotAngle, zAxis.x, zAxis.y, zAxis.z);
        GLKMatrix4 fromOrigin = GLKMatrix4MakeTranslation(_centerOfRotation.x, _centerOfRotation.y, _centerOfRotation.z);
        GLKMatrix4 tMatrix = GLKMatrix4Multiply(GLKMatrix4Multiply(fromOrigin, rotMatrix), toOrigin);

        for (VertexID vID: _all_vector_vid) {
            Vec pos = _manifold.pos(vID);
            GLKVector3 posGLK = GLKVector3Make(pos[0], pos[1], pos[2]);
            GLKVector3 newPosGLK = [Utilities matrix4:tMatrix multiplyVector3:posGLK];
            Vecf newPos = Vecf(newPosGLK.x, newPosGLK.y, newPosGLK.z);
            _current_rot_position[vID] = newPos;
        }
        
        [self.vertexDataBuffer bind];
        unsigned char* temp = (unsigned char*) glMapBufferOES(GL_ARRAY_BUFFER, GL_WRITE_ONLY_OES);
        for (VertexID vid: _all_vector_vid) {
            Vecf pos = _current_rot_position[vid];
            int index = vid.index;
            memcpy(temp + index*VERTEX_SIZE, pos.get(), VERTEX_SIZE);
        }
        
        //deformable area
        map<int,GLKMatrix4> rotMatricies;
        for (auto lid: _loopsToDeform) {
            float weight = _ringToDeformValue[lid];
            float angle = weight * _rotAngle;
            GLKMatrix4 rotMatrix = GLKMatrix4MakeRotation(angle, zAxis.x, zAxis.y, zAxis.z);
            GLKMatrix4 tMatrix = GLKMatrix4Multiply(GLKMatrix4Multiply(fromOrigin, rotMatrix), toOrigin);
            rotMatricies[lid]=tMatrix;
        }
        
        for (auto it = _vertexToLoop.begin(); it!=_vertexToLoop.end(); ++it) {
            VertexID vid = it->first;
            int lid = it->second;
            GLKMatrix4 tMatrix = rotMatricies[lid];
            
            Vec pos = _manifold.pos(vid);
            GLKVector3 posGLK = GLKVector3Make(pos[0], pos[1], pos[2]);
            GLKVector3 newPosGLK = [Utilities matrix4:tMatrix multiplyVector3:posGLK];
            Vecf newPos = Vecf(newPosGLK.x, newPosGLK.y, newPosGLK.z);
            
            int index = vid.index;
            memcpy(temp + index*VERTEX_SIZE, newPos.get(), VERTEX_SIZE);
        }
        
        glUnmapBufferOES(GL_ARRAY_BUFFER);
        glBindBuffer(GL_ARRAY_BUFFER, 0);
        
    }
    else if (modState == MODIFICATION_BRANCH_SCALING)
    {
        GLKMatrix4 toOrigin = GLKMatrix4MakeTranslation(-_centerOfRotation.x, -_centerOfRotation.y, -_centerOfRotation.z);
        GLKMatrix4 fromOrigin = GLKMatrix4MakeTranslation(_centerOfRotation.x, _centerOfRotation.y, _centerOfRotation.z);
        GLKMatrix4 scaleMatrix = GLKMatrix4MakeScale(_scaleFactor, _scaleFactor, _scaleFactor);
        GLKMatrix4 tMatrix = GLKMatrix4Multiply(GLKMatrix4Multiply(fromOrigin, scaleMatrix), toOrigin);
        
        for (VertexID vID: _all_vector_vid) {
            Vec pos = _manifold.pos(vID);
            GLKVector3 posGLK = GLKVector3Make(pos[0], pos[1], pos[2]);
            GLKVector3 newPosGLK = [Utilities matrix4:tMatrix multiplyVector3:posGLK];
            Vecf newPos = Vecf(newPosGLK.x, newPosGLK.y, newPosGLK.z);
            _current_rot_position[vID] = newPos;
        }
        
        [self.vertexDataBuffer bind];
        unsigned char* temp = (unsigned char*) glMapBufferOES(GL_ARRAY_BUFFER, GL_WRITE_ONLY_OES);
        for (VertexID vid: _all_vector_vid) {
            Vecf pos = _current_rot_position[vid];
            int index = vid.index;
            memcpy(temp + index*VERTEX_SIZE, pos.get(), VERTEX_SIZE);
        }
        
        //deformable area
        map<int,GLKMatrix4> scaleMatricies;
        for (auto lid: _loopsToDeform) {
            float weight = _ringToDeformValue[lid];
            float scale = 1 + (_scaleFactor - 1)*weight;
            GLKMatrix4 sMatrix = GLKMatrix4MakeScale(scale, scale, scale);
            scaleMatricies[lid]=sMatrix;
        }
        
        for (auto it = _vertexToLoop.begin(); it!=_vertexToLoop.end(); ++it) {
            VertexID vid = it->first;
            int lid = it->second;

            GLKMatrix4 scaleMatrix = scaleMatricies[lid];
            GLKMatrix4 tMatrix = GLKMatrix4Multiply(GLKMatrix4Multiply(fromOrigin, scaleMatrix), toOrigin);
            
            Vec pos = _manifold.pos(vid);
            GLKVector3 posGLK = GLKVector3Make(pos[0], pos[1], pos[2]);
            GLKVector3 newPosGLK = [Utilities matrix4:tMatrix multiplyVector3:posGLK];
            Vecf newPos = Vecf(newPosGLK.x, newPosGLK.y, newPosGLK.z);
            
            int index = vid.index;
            memcpy(temp + index*VERTEX_SIZE, newPos.get(), VERTEX_SIZE);
        }
        
        glUnmapBufferOES(GL_ARRAY_BUFFER);
        glBindBuffer(GL_ARRAY_BUFFER, 0);

    }
    else if (modState == MODIFICATION_BRANCH_TRANSLATION)
    {
        GLKMatrix4 toOrigin = GLKMatrix4MakeTranslation(-_centerOfRotation.x, -_centerOfRotation.y, -_centerOfRotation.z);
        GLKMatrix4 fromOrigin = GLKMatrix4MakeTranslation(_centerOfRotation.x, _centerOfRotation.y, _centerOfRotation.z);
        GLKMatrix4 translationMatrix = GLKMatrix4MakeTranslation(_translation.x, _translation.y, _translation.z);
        GLKMatrix4 tMatrix = GLKMatrix4Multiply(GLKMatrix4Multiply(fromOrigin, translationMatrix), toOrigin);
        
        for (VertexID vID: _all_vector_vid) {
            Vec pos = _manifold.pos(vID);
            GLKVector3 posGLK = GLKVector3Make(pos[0], pos[1], pos[2]);
            GLKVector3 newPosGLK = [Utilities matrix4:tMatrix multiplyVector3:posGLK];
            Vecf newPos = Vecf(newPosGLK.x, newPosGLK.y, newPosGLK.z);
            _current_rot_position[vID] = newPos;
        }
        
        [self.vertexDataBuffer bind];
        unsigned char* temp = (unsigned char*) glMapBufferOES(GL_ARRAY_BUFFER, GL_WRITE_ONLY_OES);
        for (VertexID vid: _all_vector_vid) {
            Vecf pos = _current_rot_position[vid];
            int index = vid.index;
            memcpy(temp + index*VERTEX_SIZE, pos.get(), VERTEX_SIZE);
        }
        
        //deformable area
        map<int,GLKMatrix4> scaleMatricies;
        for (auto lid: _loopsToDeform) {
            float weight = _ringToDeformValue[lid];
            GLKVector3 t = GLKVector3MultiplyScalar(_translation, weight);
            GLKMatrix4 translatioMatrix = GLKMatrix4MakeTranslation(t.x, t.y, t.z);
            scaleMatricies[lid]= translatioMatrix;
        }
        
        for (auto it = _vertexToLoop.begin(); it!=_vertexToLoop.end(); ++it) {
            VertexID vid = it->first;
            int lid = it->second;
            
            GLKMatrix4 translationMatrix = scaleMatricies[lid];
            GLKMatrix4 tMatrix = GLKMatrix4Multiply(GLKMatrix4Multiply(fromOrigin, translationMatrix), toOrigin);
            
            Vec pos = _manifold.pos(vid);
            GLKVector3 posGLK = GLKVector3Make(pos[0], pos[1], pos[2]);
            GLKVector3 newPosGLK = [Utilities matrix4:tMatrix multiplyVector3:posGLK];
            Vecf newPos = Vecf(newPosGLK.x, newPosGLK.y, newPosGLK.z);
            
            int index = vid.index;
            memcpy(temp + index*VERTEX_SIZE, newPos.get(), VERTEX_SIZE);
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
