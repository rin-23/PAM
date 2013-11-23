//
//  Util.h
//  PAM
//
//  Created by Rinat Abdrashitov on 11/22/2013.
//  Copyright (c) 2013 Rinat Abdrashitov. All rights reserved.
//

#ifndef PAM_Util_h
#define PAM_Util_h

#import <GLKit/GLKit.h>

GLKVector3 GLKMatrix4MultiplyVector3Custom(GLKMatrix4 matrix, GLKVector3 vector3) {
    GLKVector4 vector4 = GLKVector4MakeWithVector3(vector3, 1.0f);
    vector4 = GLKMatrix4MultiplyVector4(matrix, vector4);
    return GLKVector3Make(vector4.x, vector4.y, vector4.z);
}

GLKVector2 GLKVector2MakeWithVector3(GLKVector3 vector3) {
    return GLKVector2Make(vector3.x, vector3.y);
}


#endif
