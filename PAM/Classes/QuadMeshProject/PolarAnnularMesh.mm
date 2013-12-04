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
#import "PAMUtilities.h"

#define kCENTROID_STEP 0.05f

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
        _manifold = HMesh::Manifold();
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
}

-(void)rebuffer{
    [self rebufferNoEdgetrace];
    _edgeInfo = trace_spine_edges(_manifold);

}

-(void)rebufferWithCleanup:(BOOL)shouldClean edgeTrace:(BOOL)shouldEdgeTrace {
    if (shouldClean) {
        _manifold.cleanup();
    }
    
    [self rebufferNoEdgetrace];

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
    [self rebuffer];
}

-(BOOL)manifoldIsLoaded {
    return _manifold.no_vertices() != 0;
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
                    width:(int)width
                 vertexID:(VertexID*)newPoleID
              branchWidth:(float*)bWidth
               holeCenter:(GLKVector3*)holeCenter
                 holeNorm:(GLKVector3*)holeNorm
{
    BOOL result = [self createBranchAtVertex:vID width:width vertexID:newPoleID branchWidth:bWidth];
    if (result) {
        Vecf vf = _manifold.posf(*newPoleID);
        Vec n = HMesh::normal(_manifold, *newPoleID);
        *holeCenter = GLKVector3Make(vf[0], vf[1], vf[2]);
        *holeNorm = GLKVector3Make(n[0], n[1], n[2]);
        _manifold.remove_vertex(*newPoleID);
        return YES;
    }
    return NO;
}


//Create branch at a given vertex. Return VertexID of newly created pole.
-(BOOL)createBranchAtVertex:(VertexID)vID
                      width:(int)width
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



#pragma mark - TOUCHES: BRANCH CREATION ONE FINGER

-(void)startCreateBranch:(GLKVector3)touchPoint {
    if (![self manifoldIsLoaded])
        return;
    
    _touchPoints.clear();
    _touchPoints.push_back(touchPoint);
}

-(void)continueCreateBranch:(GLKVector3)touchPoint {
    if (![self manifoldIsLoaded])
        return;
    
    _touchPoints.push_back(touchPoint);
}

-(void)endCreateBranch:(GLKVector3)touchPoint touchedModel:(BOOL)touchedModel{
    if(![self manifoldIsLoaded])
        return;
    
    [self saveState];
 
    VertexID touchedVID;
    if (touchedModel) {
        //closest vertex in 3D space
        touchedVID = [self closestVertexID_3D:_touchPoints[0]];
    } else {
        //closest vertex in 2D space
        touchedVID = [self closestVertexID_2D:_touchPoints[0]];
    }

    Vec norm = HMesh::normal(_manifold, touchedVID);
    float displace = GLKVector3Length(GLKVector3Subtract(touchPoint, _initialTouch));
    NSLog(@"displace %f", displace);
    Vec displace3d =  displace * norm ;
    
    VertexID newPoleID;
    float bWidth;
    BOOL result = [self createBranchAtVertex:touchedVID width:self.branchWidth vertexID:&newPoleID branchWidth:&bWidth];
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

-(void)endCreateBranchBended:(GLKVector3)touchPoint touchedModel:(BOOL)touchedModel {
    if(![self manifoldIsLoaded]) {
        return;
    }
    
    if (_touchPoints.size() < 4) {
        NSLog(@"[PolarAnnularMesh][WARNING] Garbage point data");
        return;
    }
    
    [self saveState];
    
    VertexID touchedVID;
    GLKVector3 firstCentroid = _touchPoints[0];
    if (touchedModel) {
        //closest vertex in 3D space
        touchedVID = [self closestVertexID_3D:firstCentroid];
    } else {
        //closest vertex in 2D space
        touchedVID = [self closestVertexID_2D:firstCentroid];
    }
    
    //Create new pole
    VertexID newPoleID;
    float bWidth;
    GLKVector3 holeCenter;
    GLKVector3 holeNorm;
    
    BOOL result = [self createHoleAtVertex:touchedVID
                                     width:self.branchWidth 
                                  vertexID:&newPoleID 
                               branchWidth:&bWidth
                                holeCenter:&holeCenter
                                  holeNorm:&holeNorm];
    
    if (!result) {
        return;
    }
    
    //closest to the first centroid between two fingers vertex in 2D space
    GLKVector3 touchedV_world = [Utilities matrix4:self.modelViewMatrix
                                   multiplyVector3:holeCenter];
    float zValueTouched = touchedV_world.z;
    
    //convert touch points to world space
    vector<GLKVector2> touchPointsWorld(_touchPoints.size());
    for (int i = 0; i < _touchPoints.size(); i++)
    {
        GLKVector3 worldSpace3 = [Utilities matrix4:self.viewMatrix multiplyVector3:_touchPoints[i]];
        touchPointsWorld[i] = GLKVector2Make(worldSpace3.x, worldSpace3.y);
    }
    
    //Get skeleton aka joint points
    vector<GLKVector2> rawSkeleton;
    float c_step = GLKVector3Length([Utilities matrix4:self.viewMatrix multiplyVector3:GLKVector3Make(kCENTROID_STEP, 0, 0)]);
    [PAMUtilities centroids:rawSkeleton forOneFingerTouchPoint:touchPointsWorld withNextCentroidStep:c_step];
    if (rawSkeleton.size() < 4) {
        NSLog(@"[PolarAnnularMesh][WARNING] Not enough controids");
        return;
    }
    
    //Smooth
    vector<GLKVector2> skeleton = [PAMUtilities laplacianSmoothing:rawSkeleton iterations:1];

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
    int numSpines = self.branchWidth * 4;
    vector<vector<GLKVector3>> allRibs(skeleton.size());
    vector<GLKVector3> skeletonModel;
    vector<GLKVector3> skeletonNormalsModel;
    
    for (int i = 0; i < skeleton.size(); i++) {
        GLKVector3 sModel = [Utilities invertVector3:GLKVector3Make(skeleton[i].x, skeleton[i].y, zValueTouched)
                                          withMatrix:self.modelViewMatrix];
        
        //dont preserve translation for norma and tangent
        float ribWidth = bWidth;
        GLKVector3 nModel = [Utilities invertVector4:GLKVector4Make(skeletonNormals[i].x, skeletonNormals[i].y, 0, 0)
                                          withMatrix:self.modelViewMatrix];
        nModel = GLKVector3MultiplyScalar(GLKVector3Normalize(nModel), ribWidth);
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


    [self populateNewLimb:allRibs];
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


-(std::vector<std::vector<GLKVector3>>)endCreateBranchTwoFingers {
    
    if (![self manifoldIsLoaded]) {
        return [self endCreateNewBodyTwoFingers];
    }
    
    if (_touchPoints.size() < 8 || _touchPoints.size() % 2 != 0) {
        NSLog(@"[PolarAnnularMesh][WARNING] Garbage point data");
        return vector<vector<GLKVector3>>();
    }
    
    [self saveState];
    
    //closest to the first centroid between two fingers vertex in 2D space
    GLKVector3 firstCentroid = GLKVector3Lerp(_touchPoints[0], _touchPoints[1], 0.5f);
    VertexID touchedVID = [self closestVertexID_2D:firstCentroid];
    Vecf touchedV = _manifold.posf(touchedVID);
    GLKVector3 touchedV_world = [Utilities matrix4:self.modelViewMatrix
                                   multiplyVector3:GLKVector3Make(touchedV[0], touchedV[1], touchedV[2])];
    float zValueTouched = touchedV_world.z;

    
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
    [PAMUtilities centroids:rawSkeleton ribWidth:skeletonWidth forTwoFingerTouchPoint:touchPointsWorld withNextCentroidStep:0.1f];
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
    
    //    //Get width for skeleton joints
    //    vector<float>skeletonWidth = [PAMUtilities ribWidthForSkeleton:skeleton
    //                                                           normals:skeletonNormals
    //                                                          tangents:skeletonTangents
    //                                                       touchPoints:touchPointsWorld];
    //
    
    //Parse new skeleton and create ribs
    //Ingore first and last centroids since they are poles
    int numSpines = 30;
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
    
    //    allRibs.push_back(skeletonModel);
    //    allRibs.push_back(skeletonNormalsModel);
    
    [self populateNewLimb:allRibs];
    
    return allRibs;
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
    float c_step = GLKVector3Length([Utilities matrix4:self.modelViewMatrix multiplyVector3:GLKVector3Make(kCENTROID_STEP, 0, 0)]);
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

//    //Get width for skeleton joints
//    vector<float>skeletonWidth = [PAMUtilities ribWidthForSkeleton:skeleton
//                                                           normals:skeletonNormals
//                                                          tangents:skeletonTangents
//                                                       touchPoints:touchPointsWorld];
//    
    //Parse new skeleton and create ribs
    //Ingore first and last centroids since they are poles
    int numSpines = 30;
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
    
//    allRibs.push_back(skeletonModel);
//    allRibs.push_back(skeletonNormalsModel);
    
    [self populateManifold:allRibs];
    
    return allRibs;
}

#pragma mark - CREATE BRANCH FROM MESH

-(void)populateNewLimb:(std::vector<vector<GLKVector3>>)allRibs {
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
        if (i == allRibs.size() - 2) { //pole 2
            vector<GLKVector3> pole = allRibs[i+1];
            vector<GLKVector3> rib = allRibs[i];
            int poleIndex = [self limbIndexForCentroid:i+1 rib:0 totalCentroid:allRibs.size() totalRib:rib.size()];
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
    
    
//    _manifold.clear();
    _manifold.build(vertices.size(),
                    reinterpret_cast<float*>(&vertices[0]),
                    faces.size(),
                    &faces[0],
                    &indices[0]);
    
//    _branchWidth = 1;
//    modState = MODIFICATION_NONE;
    
    //Calculate Bounding Box
//    Manifold::Vec pmin = Manifold::Vec();
//    Manifold::Vec pmax = Manifold::Vec();
//    HMesh::bbox(_manifold, pmin, pmax);
    
//    self.centerAtBoundingBox = YES;
//    _boundingBox.minBound = GLKVector3Make(pmin[0], pmin[1], pmin[2]);
//    _boundingBox.maxBound = GLKVector3Make(pmax[0], pmax[1], pmax[2]);
//    _boundingBox.center = GLKVector3MultiplyScalar(GLKVector3Add(_boundingBox.minBound, _boundingBox.maxBound), 0.5f);
//    
//    GLKVector3 mid = GLKVector3MultiplyScalar(GLKVector3Subtract(_boundingBox.maxBound, _boundingBox.minBound), 0.5f);
//    _boundingBox.radius = GLKVector3Length(mid);
//    _boundingBox.width = fabsf(_boundingBox.maxBound.x - _boundingBox.minBound.x);
//    _boundingBox.height = fabsf(_boundingBox.maxBound.y - _boundingBox.minBound.y);
//    _boundingBox.depth = fabsf(_boundingBox.maxBound.z - _boundingBox.minBound.z);
    
    [self rebufferWithCleanup:YES edgeTrace:NO];
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
    
    _branchWidth = 1;
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
    
    [self rebuffer];
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
    [self changeFacesColor:_all_vector_vid toSelected:YES];
    
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
