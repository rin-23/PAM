//
//  Utilities.m
//  Ossa
//
//  Created by Rinat Abdrashitov on 2013-02-13.
//  Copyright (c) 2013 Rinat Abdrashitov. All rights reserved.
//

#import "Utilities.h"
#include <stdlib.h>
#include <math.h>
#include <float.h>
#import "EulerAngles.h"
#import "GLStructures.h"

@implementation Utilities

+(CGPoint)invertY:(CGPoint)cocoaCoord forGLKView:(GLKView*)view {
    return CGPointMake(cocoaCoord.x, [view bounds].size.height - cocoaCoord.y);
}


//+(GLKVector3)rot:(GLKMatrix4)m{
//    float q1 = atan2(m.m12, m.m22);
//    float c2 = sqrt(m.m00*m.m00 + m.m01*m.m01);
//    float q2 = atan2(-1*m.m02, c2);
//    float q3 = atan2(m.m01, m.m00);
//    return GLKVector3Make(<#float x#>, <#float y#>, <#float z#>)
//    
//}

+(GLKVector3)rotationMatrixToEulerAngles:(GLKMatrix4)matrix{
    
    double y1,r1,p1;
//    double y2, r2, p2;
    
    if (matrix.m20 != 1.0f && matrix.m20 != -1.0f) {
        y1 = -asin(matrix.m20);
//        y2 = M_PI - y1;
        r1 = atan2(matrix.m21/cos(y1), matrix.m22/cos(y1));
//        r2 = atan2(matrix.m21/cos(y2), matrix.m22/cos(y2));
        p1 = atan2(matrix.m10/cos(y1), matrix.m00/cos(y1));
//        p2 = atan2(matrix.m10/cos(y2), matrix.m00/cos(y2));
        
        return GLKVector3Make(r1, y1, p1);
    } else {
        p1 = 0;
        if (matrix.m20 == -1.0f) {
            y1 = M_PI_2;
            r1 = p1 + atan2(matrix.m01, matrix.m02);
        } else {
            y1 = -M_PI_2;
            r1 = -p1 + atan2(-matrix.m01, -matrix.m02);
        }
        return GLKVector3Make(r1, y1, p1);
    }    
}

+(GLKVector3)rotationMatrixToEulerAnglesDegrees:(GLKMatrix4)matrix{
    GLKVector3 v = [Utilities rotationMatrixToEulerAngles:matrix];
    double toDeg = 180.0/M_PI;
    int y1 = [Utilities roundToNearestInt:v.x*toDeg];
    int r1 = [Utilities roundToNearestInt:v.y*toDeg];
    int p1 = [Utilities roundToNearestInt:v.z*toDeg];
    return GLKVector3Make(y1, r1, p1);
}


+(GLKVector3)quaternionToEulerAngles:(GLKQuaternion)quat{
    
    float* q = quat.q;

    double y = atan2(2*(q[0]*q[1] + q[2]*q[3]), 1-2*(q[1]*q[1] + q[2]*q[2]));
    double r = asin(2*(q[0]*q[2] - q[3]*q[1]));
    double p = atan2(2*(q[0]*q[3] + q[1]*q[2]), 1-2*(q[2]*q[2] + q[3]*q[3]));
    
    double toDeg = 180.0/M_PI;
    return GLKVector3Make(floor(r*toDeg), floor(p*toDeg), floor(y*toDeg));
}

+(int)roundToNearestInt:(float)num{
    if (num < 0) {
        return (int)(num - 0.5);
    }
    return (int)(num + 0.5);
}

+(void)printMatrix4:(GLKMatrix4)m{
    NSLog(@"*********");
    NSLog(@"|%0.3f %0.3f %0.3f %0.3f|", m.m00,m.m01,m.m02,m.m03);
    NSLog(@"|%0.3f %0.3f %0.3f %0.3f|", m.m10,m.m11,m.m12,m.m13);
    NSLog(@"|%0.3f %0.3f %0.3f %0.3f|", m.m20,m.m21,m.m22,m.m23);
    NSLog(@"|%0.3f %0.3f %0.3f %0.3f|", m.m30,m.m31,m.m32,m.m33);
    NSLog(@"*********");
    
}

+(int) glhProjectf:(GLKVector3)obj :(GLKMatrix4)glkModelViewProjection :(GLKVector4)glkViewport  :(GLKVector3*)windowCoordinate
{
    //Modelview transform
    GLKVector4 fV4 = GLKMatrix4MultiplyVector4(glkModelViewProjection, GLKVector4MakeWithVector3(obj, 1.0));
//    fV4 = GLKMatrix4MultiplyVector4(glkProjection, fV4);
    
    if (fV4.v[3] == 0.0) return 0;
    fV4.v[0] /= fV4.v[3];
    fV4.v[1] /= fV4.v[3];
    fV4.v[2] /= fV4.v[3];
    /* Map x, y and z to range 0-1 */
    fV4.v[0] = fV4.v[0] * 0.5 + 0.5;
    fV4.v[1] = fV4.v[1] * 0.5 + 0.5;
    fV4.v[2] = fV4.v[2] * 0.5 + 0.5;
    
    /* Map x,y to viewport */
    fV4.v[0] = fV4.v[0] * glkViewport.v[2] + glkViewport.v[0];
    fV4.v[1] = fV4.v[1] * glkViewport.v[3] + glkViewport.v[1];
    
    windowCoordinate->v[0] = fV4.v[0];
    windowCoordinate->v[1] = fV4.v[1];
    windowCoordinate->v[2] = fV4.v[2];
    return 1;
}

+(int) gluUnProjectf:(GLKVector3)win :(GLKMatrix4)modelviewProjection :(GLKVector4)viewport :(GLKVector3*)objectCoordinate
{
    //Transformation matrices
    GLKMatrix4 modelviewProjectionInverse;
    GLKVector4 inVec;
    GLKVector4 outVec;
    
    //Now compute the inverse of matrix A
    bool isInvertable;
    modelviewProjectionInverse = GLKMatrix4Invert(modelviewProjection, &isInvertable);
    if(!isInvertable)
        return 0;
    
    //Transformation of normalized coordinates between -1 and 1
    inVec.v[0]=(win.x-(float)viewport.v[0])/(float)viewport.v[2]*2.0-1.0;
    inVec.v[1]=(win.y-(float)viewport.v[1])/(float)viewport.v[3]*2.0-1.0;
    inVec.v[2]=2.0*win.z-1.0;
    inVec.v[3]=1.0;
    //Objects coordinates
    outVec = GLKMatrix4MultiplyVector4(modelviewProjectionInverse, inVec);
    
    if(outVec.v[3]==0.0)
        return 0;
    
    outVec.v[3]=1.0/outVec.v[3];
    objectCoordinate->v[0]=outVec.v[0]*outVec.v[3];
    objectCoordinate->v[1]=outVec.v[1]*outVec.v[3];
    objectCoordinate->v[2]=outVec.v[2]*outVec.v[3];
    return 1;
}

+(NSData*)convertGLKVecto3ToVertex:(NSData*)vectorData{
    GLKVector3* vectorArray = (GLKVector3*)vectorData.bytes;
    int vectorLen = vectorData.length/sizeof(GLKVector3);
    
    NSMutableData* vertexData = [[NSMutableData alloc] init];
    for (int i = 0; i < vectorLen; i++) {
        GLKVector3 vector = vectorArray[i];
        VertexRGBA vertex = {{vector.x, vector.y, vector.z},{255,0,0,255}};
        [vertexData appendBytes:&vertex length:sizeof(VertexRGBA)];
    }
    return vertexData;
}

/*
 * Perform linear interpolation between Point p0 and Point p1
 * and return the interpolated points as ArrayList<Point>
 */

+(NSMutableArray*)linearInterpolationWithStartPoint:(CGPoint)p0 endPoint:(CGPoint)p1 {
    NSMutableArray* extraPoints = [NSMutableArray new];
    
    int x0 = floorf(p0.x);
    int y0 = floorf(p0.y);
    int x1 = floorf(p1.x);
    int y1 = floorf(p1.y);
    
    // Check which orientation we should interpolate
    if (abs(x0-x1) > abs(y0-y1)) {
        // Interpolate over x
        if (x0 > x1) {
            for (int x = x0 - 1; x > x1; x--) {
                float y = (float)y0 + ((float)((x - x0) * y1 - (x - x0) * y0))/(float)(x1 - x0);
                CGPoint p = CGPointMake(x, roundf(round(y)));
                [extraPoints addObject:[NSValue valueWithCGPoint:p]];
            }
        } else {
            for (int x = x0 + 1; x < x1; x++) {
                float y = (float)y0 + ((float)((x - x0) * y1 - (x - x0) * y0))/(float)(x1 - x0);
                CGPoint p = CGPointMake(x, roundf(round(y)));
                [extraPoints addObject:[NSValue valueWithCGPoint:p]];
            }
        }
    } else {
        // Interpolate over y
        if (y0 > y1) {
            for (int y = y0 - 1; y > y1; y--) {
                float x = (float)x0 + ((float)((y - y0) * x1 - (y - y0) * x0))/(float)(y1 - y0);
                CGPoint p = CGPointMake(roundf(x), y);
                [extraPoints addObject:[NSValue valueWithCGPoint:p]];
            }
        } else {
            for (int y = y0 + 1; y < y1; y++) {
                float x = (float)x0 + ((float)((y - y0) * x1 - (y - y0) * x0))/(float)(y1 - y0);
                CGPoint p = CGPointMake(roundf(x), y);
                [extraPoints addObject:[NSValue valueWithCGPoint:p]];
            }
        }
    }
    return extraPoints;
}

/*
 * Angle between a and b
 */
double triangleAngleWithSides(double a, double b, double c) {
    return acos((pow(a, 2) + pow(b, 2) - pow(c, 2))/(2 * a * b));
}

/*
 * Triangle ray hit test
 */
+(BOOL)hitTestTriangle:(GLKVector3*)triangle withRayStart:(GLKVector3)rayStartPoint rayDirection:(GLKVector3)ray  {
    
    GLKVector3 _p0 = triangle[0]; //left bottom vertex
    GLKVector3 _p1 = triangle[1]; //to the right of p0
    GLKVector3 _p2 = triangle[2]; //to the left of p0
    
    GLKVector3 norm = GLKVector3CrossProduct(GLKVector3Subtract(_p1, _p0), GLKVector3Subtract(_p2, _p0));
    norm = GLKVector3Normalize(norm);
    
    GLfloat d = GLKVector3DotProduct(norm, _p0);
    
    if (GLKVector3DotProduct(norm, ray) !=  0) {
        GLfloat t = (d - GLKVector3DotProduct(norm, rayStartPoint)) / GLKVector3DotProduct(norm, ray);
        GLKVector3 intersection = GLKVector3Add(rayStartPoint, GLKVector3MultiplyScalar(ray, t));
        
        BOOL check1 = GLKVector3DotProduct(GLKVector3CrossProduct(GLKVector3Subtract(_p1, _p0),
                                                                  GLKVector3Subtract(intersection, _p0)),
                                           norm) >= 0;
        BOOL check2 = GLKVector3DotProduct(GLKVector3CrossProduct(GLKVector3Subtract(_p2, _p1),
                                                                  GLKVector3Subtract(intersection, _p1)),
                                           norm) >= 0;
        BOOL check3 = GLKVector3DotProduct(GLKVector3CrossProduct(GLKVector3Subtract(_p0, _p2),
                                                                  GLKVector3Subtract(intersection, _p2)),
                                           norm) >= 0;
        
        if (check1 && check2 && check3) {
            //            NSLog(@"HIT");
            return YES;
        } else {
            //            NSLog(@"MISS");
            return NO;
        }
    } else {
        NSLog(@"Parallel");
        return NO;
    }
}


+(BOOL)hitTestCircleWithRadius:(double)radius
                        center:(GLKVector3)center
             inscribedTriangle:(GLKVector3*)triangle
                  withRayStart:(GLKVector3)rayStartPoint
                  rayDirection:(GLKVector3)ray
{
    
    GLKVector3 _p0 = triangle[0]; //left bottom vertex
    GLKVector3 _p1 = triangle[1]; //to the right of p0
    GLKVector3 _p2 = triangle[2]; //to the left of p0
    
    GLKVector3 norm = GLKVector3CrossProduct(GLKVector3Subtract(_p1, _p0), GLKVector3Subtract(_p2, _p0));
    norm = GLKVector3Normalize(norm);
    
    GLfloat d = GLKVector3DotProduct(norm, _p0);
    
    if (GLKVector3DotProduct(norm, ray) !=  0) {
        GLfloat t = (d - GLKVector3DotProduct(norm, rayStartPoint)) / GLKVector3DotProduct(norm, ray);
        GLKVector3 intersection = GLKVector3Add(rayStartPoint, GLKVector3MultiplyScalar(ray, t));
        double dist = GLKVector3Distance(center, intersection);
        if (dist <= radius) {
            return YES;
        }
    }
    return NO;
}

+(GLKVector3)computeNormCCWForV1:(GLKVector3)v1 v2:(GLKVector3)v2 v3:(GLKVector3)v3 {
    GLKVector3 s1 = GLKVector3Subtract(v2, v1);
    GLKVector3 s2 = GLKVector3Subtract(v3, v1);
    GLKVector3 cross = GLKVector3CrossProduct(s1, s2);
    GLKVector3 normCross = GLKVector3Normalize(cross);
    return normCross;
}

+(GLKVector3)invertVector4:(GLKVector4)vector4 withMatrix:(GLKMatrix4)matrix4 {
    bool isInvertable;
    vector4 = GLKMatrix4MultiplyVector4(GLKMatrix4Invert(matrix4, &isInvertable), vector4);
    GLKVector3 vector3 = GLKVector3Make(vector4.x, vector4.y, vector4.z);
    return vector3;
}

+(GLKVector3)invertVector3:(GLKVector3)vector3 withMatrix:(GLKMatrix4)matrix4 {
    GLKVector4 vector4 = GLKVector4MakeWithVector3(vector3, 1.0);
    return [self invertVector4:vector4 withMatrix:matrix4];
}


@end
