//
//  Mesh.m
//  Ossa
//
//  Created by Rinat Abdrashitov on 2013-07-31.
//  Copyright (c) 2013 Rinat Abdrashitov. All rights reserved.
//

#import "Mesh.h"
#import "ShaderProgram.h"
#import "RotationManager.h"

@implementation Mesh

@synthesize modelMatrix = _modelMatrix, normalMatrix = _normalMatrix;

-(id)init {
    self = [super init];
    if (self) {
        _modelMatrix = GLKMatrix4Identity;
        _viewMatrix = GLKMatrix4Identity;
        _projectionMatrix = GLKMatrix4Identity;
        _normalMatrix = GLKMatrix3Identity;
        _rotationManager = [[RotationManager alloc] init];
        _translationManager = [[TranslationManager alloc] init];
        _centroid = GLKVector3Make(0, 0, 0);
    }
    return self;
}

-(void)draw{
    //overwrite
}

-(void)drawToDepthBuffer {
    //overwrite
}

-(GLKMatrix4)modelViewProjectionMatrix {
    return GLKMatrix4Multiply(self.projectionMatrix, self.modelViewMatrix);
}

-(GLKMatrix4)modelViewMatrix {
    return GLKMatrix4Multiply(self.viewMatrix, self.modelMatrix);
}

-(GLKMatrix4)modelMatrix {
    GLKMatrix4 modelMatrix = GLKMatrix4Identity;
    
    modelMatrix = GLKMatrix4Multiply(modelMatrix, self.translationManager.translationMatrix);
    
    modelMatrix = GLKMatrix4TranslateWithVector3(modelMatrix, self.centroid);
    modelMatrix = GLKMatrix4Multiply(modelMatrix, self.rotationManager.rotationMatrix);
    modelMatrix = GLKMatrix4TranslateWithVector3(modelMatrix, GLKVector3MultiplyScalar(self.centroid, -1));
    
    return modelMatrix;
}

-(GLKMatrix3)normalMatrix {
    bool isInvert;
    GLKMatrix3 mvpInverseMatrix =  GLKMatrix3Invert(GLKMatrix4GetMatrix3(self.modelViewMatrix), &isInvert);
    if (isInvert) {
        GLKMatrix3 mvpInverseTransposeMatrix = GLKMatrix3Transpose(mvpInverseMatrix);
        return mvpInverseTransposeMatrix;
    }
    return GLKMatrix3Identity;
}

@end
