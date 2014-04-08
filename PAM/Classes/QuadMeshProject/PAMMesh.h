//
//  PAMMesh.h
//  PAM
//
//  Created by Rinat Abdrashitov on 2014-04-07.
//  Copyright (c) 2014 Rinat Abdrashitov. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "Mesh.h"
#include "Mat4x4f.h"
#include "Mat3x3f.h"
#include "Vec3f.h"

@interface PAMMesh : Mesh {
    @protected
    CGLA::Mat4x4f _modelMatrixGEL;
    CGLA::Mat4x4f _normalMatrixGEL;
}
-(GLKMatrix4)modelViewMatrixGEL;
-(GLKMatrix4)modelViewProjectionMatrixGEL;

@property (nonatomic, assign) CGLA::Vec3f centroidGEL;

@property (nonatomic, assign, readonly) CGLA::Mat4x4f modelMatrixGEL;
@property (nonatomic, assign) CGLA::Mat4x4f viewMatrixGEL;
@property (nonatomic, assign) CGLA::Mat4x4f projectionMatrixGEL;
@property (nonatomic, assign, readonly) CGLA::Mat3x3f normalMatrixGEL;

@end
