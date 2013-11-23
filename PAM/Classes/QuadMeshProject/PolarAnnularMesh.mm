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

typedef CGLA::Vec3d Vec;
typedef CGLA::Vec3f Vecf;

using namespace HMesh;

@interface PolarAnnularMesh() {
    HMesh::Manifold _manifold;
    HMesh::HalfEdgeAttributeVector<EdgeInfo> _edgeInfo;
    BoundingBox _boundingBox;
    
    GLKVector3 _initialTouch;
    
    //Undo
    HMesh::Manifold undoMani;
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
    NSString* vShader = [[NSBundle mainBundle] pathForResource:@"Shader" ofType:@"vsh"];
    NSString* fShader = [[NSBundle mainBundle] pathForResource:@"Shader" ofType:@"fsh"];
    self.drawShaderProgram = [[ShaderProgram alloc] initWithVertexShader:vShader fragmentShader:fShader];

    attrib[ATTRIB_POSITION] = [self.drawShaderProgram attributeLocation:"position"];
    attrib[ATTRIB_NORMAL] = [self.drawShaderProgram attributeLocation:"normal"];
    attrib[ATTRIB_COLOR] = [self.drawShaderProgram attributeLocation:"color"];
    
    uniforms[UNIFORM_MODELVIEWPROJECTION_MATRIX] = [self.drawShaderProgram uniformLocation:"modelViewProjectionMatrix"];
    uniforms[UNIFORM_NORMAL_MATRIX] = [self.drawShaderProgram uniformLocation:"normalMatrix"];
    
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
    _edgeInfo = trace_spine_edges(_manifold);
}

-(BoundingBox)boundingBox {
    return _boundingBox;
}

-(void)saveState {
    undoMani = _manifold;
}

#pragma mark - FINE VERTEX NEAR TOUCH POINT

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

#pragma mark - BRANCH CREATION METHODS

//Create branch near touch point and refine
-(BOOL)createBranchAtTouchPointAndRefine:(GLKVector3)touchPoint {
    VertexID newPoleID;
    BOOL result = [self createBranchAtTouchPoint:touchPoint branchWidth:self.branchWidth vertexID:&newPoleID];
    if (result) {
        add_rib(_manifold, _manifold.walker(newPoleID).halfedge(), _edgeInfo);
        [self rebuffer];
    }
    return result;
}

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

//Create branch at a vertex near touch point. Return VertexID of newly created pole.
-(BOOL)createBranchAtTouchPoint:(GLKVector3)touchPoint
                    branchWidth:(int)width
                       vertexID:(VertexID*)newPoleID
{
    VertexID vID = [self closestVertexID:touchPoint];
    return [self createBranchAtVertex:vID width:width vertexID:newPoleID];
}

#pragma mark - HANDLE BRANCH CREATION TOUCHES OUTSIDE OF MODEL

-(void)startCreateBranch:(GLKVector3)touchPoint {
    _initialTouch = touchPoint;
}

-(void)endCreateBranch:(GLKVector3)touchPoint touchedModel:(BOOL)touchedModel{
    [self saveState];

    VertexID touchedVID;
    if (touchedModel) {
        //closest vertex in 3D space
        touchedVID = [self closestVertexID:_initialTouch];
    } else {
        //closest vertex in 2D space
        touchedVID = [self closestVertexID_2D:_initialTouch];
    }

    Vec norm = HMesh::normal(_manifold, touchedVID);
    float displace = GLKVector3Length(GLKVector3Subtract(touchPoint, _initialTouch));
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

#pragma mark - DRAWING

-(void)draw {
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
