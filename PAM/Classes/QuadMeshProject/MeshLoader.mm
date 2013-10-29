//
//  MeshLoader.m
//  Ossa
//
//  Created by Rinat Abdrashitov on 2013-10-14.
//  Copyright (c) 2013 Rinat Abdrashitov. All rights reserved.
//

#import "MeshLoader.h"

//GEL
#import "polygonize.h"
#import "MetaBalls.h"
#import "Implicit.h"
#import "triangulate.h"
#import "../HMesh/obj_load.h"

#import <GLKit/GLKMath.h>
#import "GLStructures.h"

static MeshLoader* instance = nil;

@implementation MeshLoader

+(NSMutableData *)meshData {
    CGLA::Vec3d llf = CGLA::Vec3d(25,20,26);
    CGLA::Vec3d urt = CGLA::Vec3d(37,37,42);
    GLKVector3 minBound = GLKVector3Make(25, 20, 26);
    GLKVector3 maxBound = GLKVector3Make(37, 37, 42);
    int DIM = 64;
    RGrid<float> grid(Vec3i(DIM),0);
    
    MetaBalls* implicit = new MetaBalls;
    
    XForm xform = grid_sample(*implicit, llf, urt, grid);
    
    HMesh::Manifold mani = HMesh::Manifold();
    
    float tau = 0.0;
    HMesh::volume_polygonize(xform, grid, mani, tau);
    
    //Triangulate
    shortest_edge_triangulate(mani);
    
    //extract verticies from faces
    NSMutableData* verticies = [[NSMutableData alloc] init]; //alocate space for verticies
    
    GLKVector3 mid = GLKVector3MultiplyScalar(GLKVector3Subtract(maxBound, minBound), 0.5f);
    float rad = GLKVector3Length(mid);
    
    //iterate over every face
    for(HMesh::FaceIDIterator fid = mani.faces_begin(); fid != mani.faces_end(); ++fid) {
        //iterate over every vertex of the face
        for(HMesh::Walker w = mani.walker(*fid); !w.full_circle(); w = w.circulate_face_ccw()) {
            //add vertex to the data array
            CGLA::Vec3d c = mani.pos(w.vertex());
            CGLA::Vec3d norm = HMesh::normal(mani, w.face());
            
            PositionXYZ positionDCM = {(GLfloat)c[0], (GLfloat)c[1], (GLfloat)c[2]};
            PositionXYZ normDCM = {(GLfloat)norm[0], (GLfloat)norm[1], (GLfloat)norm[2]};
            
            GLKVector3 positionDCMVector3 = GLKVector3Make(positionDCM.x, positionDCM.y, positionDCM.z);
            GLKVector3 positionGLVector3 = GLKVector3DivideScalar(GLKVector3Subtract(GLKVector3Subtract(positionDCMVector3, minBound), mid), rad);
            // convert Patient Coordinate System to OpenGL Coordinate system by flipping y and z coordinates
            positionGLVector3 = GLKVector3Multiply(positionGLVector3, GLKVector3Make(1, -1, -1));
            // rotate to anterior position based on current Patient Position
            PositionXYZ positionGL = {positionGLVector3.x, positionGLVector3.y, positionGLVector3.z};
            
            VertexNormRGBA vertexMono = {positionGL, normDCM, {200,200,200,255}};
            [verticies appendBytes:&vertexMono length:sizeof(VertexNormRGBA)];
        }
    }
    
    return verticies;
}

+(NSMutableData *)meshDataFromObjFile:(NSString *)objFilePath {
    HMesh::Manifold mani = HMesh::Manifold();
    HMesh::obj_load(objFilePath.UTF8String, mani);
    
    shortest_edge_triangulate(mani);
    
    HMesh::Manifold::Vec pmin = HMesh::Manifold::Vec();
    HMesh::Manifold::Vec pmax = HMesh::Manifold::Vec();
    HMesh::bbox(mani, pmin, pmax);
    
    GLKVector3 minBound = GLKVector3Make(pmin[0], pmin[1], pmin[2]);
    GLKVector3 maxBound = GLKVector3Make(pmax[0], pmax[1], pmax[2]);
    
    GLKVector3 mid = GLKVector3MultiplyScalar(GLKVector3Subtract(maxBound, minBound), 0.5f);
    float rad = GLKVector3Length(mid);
    
    NSMutableData* verticies = [[NSMutableData alloc] init]; //alocate space for verticies
    GLKMatrix3 rotateToAnterior = GLKMatrix3Identity;
    
    //iterate over every face
    for(HMesh::FaceIDIterator fid = mani.faces_begin(); fid != mani.faces_end(); ++fid) {
        //iterate over every vertex of the face
        CGLA::Vec3d norm = HMesh::normal(mani, *fid);
        for(HMesh::Walker w = mani.walker(*fid); !w.full_circle(); w = w.circulate_face_ccw()) {
            //add vertex to the data array
            CGLA::Vec3d c = mani.pos(w.vertex());
            
            PositionXYZ positionDCM = {(GLfloat)c[0], (GLfloat)c[1], (GLfloat)c[2]};
            PositionXYZ normDCM = {(GLfloat)norm[0], (GLfloat)norm[1], (GLfloat)norm[2]};
            
            GLKVector3 positionDCMVector3 = GLKVector3Make(positionDCM.x, positionDCM.y, positionDCM.z);
            GLKVector3 positionGLVector3 = GLKVector3DivideScalar(GLKVector3Subtract(GLKVector3Subtract(positionDCMVector3, minBound), mid), rad);
            // convert Patient Coordinate System to OpenGL Coordinate system by flipping y and z coordinates
            positionGLVector3 = GLKVector3Multiply(positionGLVector3, GLKVector3Make(1, -1, -1));
            // rotate to anterior position based on current Patient Position
            positionGLVector3 = GLKMatrix3MultiplyVector3(rotateToAnterior, positionGLVector3);
            PositionXYZ positionGL = {positionGLVector3.x, positionGLVector3.y, positionGLVector3.z};
            
            VertexNormRGBA vertexMono = {positionGL, normDCM, {200,200,200,255}};
            [verticies appendBytes:&vertexMono length:sizeof(VertexNormRGBA)];
        }
    }
    return verticies;
}

@end
