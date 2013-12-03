//
//  Utilities.h
//  Ossa
//
//  Created by Rinat Abdrashitov on 2013-02-13.
//  Copyright (c) 2013 Rinat Abdrashitov. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <GLKit/GLKit.h>

@interface Utilities : NSObject


+(CGPoint)invertY:(CGPoint)cocoaCoord forGLKView:(GLKView*)view;
void gluPerspective(GLfloat fovy, GLfloat aspect, GLfloat zNear, GLfloat zFar);

void gluLookAt(GLfloat eyex, GLfloat eyey, GLfloat eyez, GLfloat centerx,
                  GLfloat centery, GLfloat centerz, GLfloat upx, GLfloat upy,
                  GLfloat upz);

void gluPickMatrix(GLfloat x, GLfloat y, GLfloat deltax, GLfloat deltay,
                   GLint viewport[4]);


+(GLKVector3)rotationMatrixToEulerAngles:(GLKMatrix4)matrix;
+(GLKVector3)rotationMatrixToEulerAnglesDegrees:(GLKMatrix4)matrix;
+(GLKVector3)quaternionToEulerAngles:(GLKQuaternion)matrix;

+(int)roundToNearestInt:(float)num;
+(void)printMatrix4:(GLKMatrix4)m;

+(GLKVector3)computeNormCCWForV1:(GLKVector3)v1 v2:(GLKVector3)v2 v3:(GLKVector3)v3;

+(int) glhProjectf:(GLKVector3)obj :(GLKMatrix4)glkModelViewProjection :(GLKVector4)glkViewport  :(GLKVector3*)windowCoordinate;
+(int) gluUnProjectf:(GLKVector3)win :(GLKMatrix4)modelviewProjection :(GLKVector4)viewport :(GLKVector3*)objectCoordinate;
+(NSMutableArray*)linearInterpolationWithStartPoint:(CGPoint)p0 endPoint:(CGPoint)p1;

double triangleAngleWithSides(double a, double b, double c);

+(NSData*)convertGLKVecto3ToVertex:(NSData*)vectorData;

+(BOOL)hitTestTriangle:(GLKVector3*)triangle
          withRayStart:(GLKVector3)rayStartPoint
          rayDirection:(GLKVector3)ray;

+(BOOL)hitTestQuad:(GLKVector3*)quad
      withRayStart:(GLKVector3)rayStartPoint
      rayDirection:(GLKVector3)ray;

+(BOOL)hitTestCircleWithRadius:(double)radius
                        center:(GLKVector3)center
             inscribedTriangle:(GLKVector3*)triangle
                  withRayStart:(GLKVector3)rayStartPoint
                  rayDirection:(GLKVector3)ray;

+(GLKVector3)invertVector3:(GLKVector3)vector3 withMatrix:(GLKMatrix4)matrix4;
+(GLKVector3)invertVector4:(GLKVector4)vector4 withMatrix:(GLKMatrix4)matrix4;

+(GLKVector3) matrix4:(GLKMatrix4)matrix multiplyVector3:(GLKVector3)vector3;
+(GLKVector3) matrix4:(GLKMatrix4)matrix multiplyVector4:(GLKVector4)vector4;

+(GLKVector2) GLKVector2MakeWithVector3:(GLKVector3) vector3;

+(GLKVector3)projectVector3:(GLKVector3)vec ontoLine:(GLKVector3)line;
+(GLKVector2)projectVector2:(GLKVector2)vec ontoLine:(GLKVector2)line;
+(float)signedAngleBetweenReferenceVector3:(GLKVector3)refVector andVector:(GLKVector3)vector;
@end
