//
//  GyroRotationManager.m
//  Ossa
//
//  Created by Rinat Abdrashitov on 2013-09-14.
//  Copyright (c) 2013 Rinat Abdrashitov. All rights reserved.
//

#import "GyroRotationManager.h"
#import <CoreMotion/CoreMotion.h>

static GyroRotationManager* instance = nil;

@interface GyroRotationManager() {
    CMMotionManager* _motionManager;

    //Reference
    CMAttitude* _gyroReferenceAttitude;
    GLKMatrix4 _gyroReferenceMatrix;

    //Resulting vector and angle of rotation
    GLKVector3 _gyroVector;
    double _gyroAngle;
}

@end

@implementation GyroRotationManager

-(id)init {
    self = [super init];
    
    if (self) {
        _rotationMatrix = GLKMatrix4Identity;
        _gyroReferenceMatrix = GLKMatrix4Identity;
        _motionManager = [[CMMotionManager alloc] init];
        [self enableGyro];
    }
    
    return self;
}

+ (id)sharedInstance {
    if (!instance) {
        instance = [[GyroRotationManager alloc] init];
    }
    return instance;
}

-(void)captureReferenceAttitudeAndMatrix:(GLKMatrix4)referenceMatrix {
    _gyroReferenceAttitude = _motionManager.deviceMotion.attitude;
    _gyroReferenceMatrix = referenceMatrix;
}

-(GLKMatrix4)rotationMatrix {
    [self updateGyro];
    bool isInvertible;
    GLKVector3 axis = GLKMatrix4MultiplyVector3(GLKMatrix4Invert(_gyroReferenceMatrix, &isInvertible), _gyroVector);
    GLKMatrix4 rotationMatrix = GLKMatrix4RotateWithVector3(_gyroReferenceMatrix, _gyroAngle, axis);
    return rotationMatrix;
}
- (void)enableGyro {
    _motionManager.deviceMotionUpdateInterval = 1.0 / 60.0;
    if (_motionManager.isDeviceMotionAvailable) {
        [_motionManager startDeviceMotionUpdates];
    }
}

- (void)disableGyro {
    if (_motionManager.isDeviceMotionActive) {
        [_motionManager stopDeviceMotionUpdates];
    }
}
- (void)updateGyro {
    CMAttitude* gyroCurrentAttitude = _motionManager.deviceMotion.attitude;
    [gyroCurrentAttitude multiplyByInverseOfAttitude:_gyroReferenceAttitude];
    
    CMQuaternion cmQuat = gyroCurrentAttitude.quaternion;
    
    double thetaOver2 = acos(cmQuat.w);
    double x = cmQuat.x/sin(thetaOver2);
    double y = cmQuat.y/sin(thetaOver2);
    double z = cmQuat.z/sin(thetaOver2);
    
    if (UIInterfaceOrientationIsLandscape([[UIApplication sharedApplication] statusBarOrientation])) {
        _gyroVector  = GLKVector3Make(y, x, z);
    } else {
        _gyroVector  = GLKVector3Make(x, y, z);
    }
    
    _gyroAngle = 2*thetaOver2;
}

-(void)reset {
    _gyroReferenceMatrix = GLKMatrix4Identity;
    _gyroVector = GLKVector3Make(0,0,0);
    _gyroAngle = 0.0f;
}

@end
