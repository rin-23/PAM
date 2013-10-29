//
//  ArcBallRotationManager.m
//  Pelvic-iOS
//
//  Created by Rinat Abdrashitov on 12-10-22.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import "RotationManager.h"
#import "Utilities.h"

@interface RotationManager() {
    //Reference
    CGPoint lastLoc;
    float lastRot;

    //Resulting mmatrix
    GLKMatrix4 _manualRotationMatrix;
}
@end

@implementation RotationManager

- (id)init {
    self = [super init];
    if (self) {
        _manualRotationMatrix = GLKMatrix4Identity;
    }
    return self;
}

- (GLKMatrix4)rotationMatrix{
    return _manualRotationMatrix;
}

-(void)setRotationMatrix:(GLKMatrix4)rotationMatrix{
    _manualRotationMatrix = rotationMatrix;
}

#pragma mark - ARCBALL ROTATION
- (void)handlePanGesture:(UIGestureRecognizer*)sender withViewMatrix:(GLKMatrix4)viewMatrix isOrthogonal:(BOOL)isOrtho {
    UIPanGestureRecognizer* pan = (UIPanGestureRecognizer*)sender;
    
    if (pan.state == UIGestureRecognizerStateBegan) {
        lastLoc = [Utilities invertY:[pan locationInView:pan.view] forGLKView:(GLKView*)pan.view];
    } else if (pan.state == UIGestureRecognizerStateChanged) {
        CGPoint location = [Utilities invertY:[pan locationInView:pan.view] forGLKView:(GLKView*)pan.view];
        CGPoint diff = CGPointMake(location.x - lastLoc.x, location.y - lastLoc.y);
        float rotX =  -1*GLKMathDegreesToRadians(diff.y / 2.0f); //because positive angle is clockwise
        float rotY =  GLKMathDegreesToRadians(diff.x / 2.0f);
        
        bool isInvertible;
        
        GLKMatrix4 curModelView = GLKMatrix4Multiply(viewMatrix, _manualRotationMatrix);
        
        if (isOrtho)
        {
            //Calculate angle between positive X and rotation direction
            GLKVector3 positiveX = GLKVector3Make(1, 0, 0);
            GLKVector3 transVectorNormalized = GLKVector3Normalize(GLKVector3Make(diff.x, diff.y, 0));
            float angle = acosf(GLKVector3DotProduct(positiveX, transVectorNormalized));
            
            //            NSLog(@"V:(%f,%f) A:%f",transVectorNormalized.x, transVectorNormalized.y,GLKMathRadiansToDegrees(angle));
            
            if (angle<GLKMathDegreesToRadians(45.0) || angle>GLKMathDegreesToRadians(135.0) ) {
                GLKVector3 yAxis = GLKMatrix4MultiplyVector3(GLKMatrix4Invert(curModelView, &isInvertible),
                                                             GLKVector3Make(0, 1, 0));
                _manualRotationMatrix = GLKMatrix4RotateWithVector3(_manualRotationMatrix, rotY, yAxis);
                
                
            } else if (angle>GLKMathDegreesToRadians(45.0) && angle< GLKMathDegreesToRadians(135)) {
                GLKVector3 xAxis = GLKMatrix4MultiplyVector3(GLKMatrix4Invert(curModelView,&isInvertible),
                                                             GLKVector3Make(1, 0, 0));
                _manualRotationMatrix = GLKMatrix4RotateWithVector3(_manualRotationMatrix, rotX, xAxis);
            }
            
        }
        else
        {
            GLKVector3 xAxis = GLKMatrix4MultiplyVector3(GLKMatrix4Invert(curModelView,&isInvertible),
                                                         GLKVector3Make(1, 0, 0));
            _manualRotationMatrix = GLKMatrix4RotateWithVector3(_manualRotationMatrix, rotX, xAxis);
            GLKVector3 yAxis = GLKMatrix4MultiplyVector3(GLKMatrix4Invert(curModelView,&isInvertible),
                                                         GLKVector3Make(0, 1, 0));
            _manualRotationMatrix = GLKMatrix4RotateWithVector3(_manualRotationMatrix, rotY, yAxis);
        }
        
        lastLoc = location;
    }
}

#pragma mark - ROTATE IN THE SURFACE OF THE SCREEN
- (void)handleRotationGesture:(UIGestureRecognizer *)sender withViewMatrix:(GLKMatrix4)viewMatrix {
    GLKMatrix4 curModelView = GLKMatrix4Multiply(viewMatrix, _manualRotationMatrix);
    
    UIRotationGestureRecognizer* rotationGesture = (UIRotationGestureRecognizer*)sender;
    if (sender.state == UIGestureRecognizerStateBegan) {
        lastRot = rotationGesture.rotation;
    } else if (sender.state == UIGestureRecognizerStateChanged) {
        float rotation = rotationGesture.rotation;
        float rotZ = rotation-lastRot;

        bool isInvertable;
        GLKVector3 zAxis = GLKMatrix4MultiplyVector3(GLKMatrix4Invert(curModelView, &isInvertable),
                                                     GLKVector3Make(0, 0, -1));
        _manualRotationMatrix = GLKMatrix4RotateWithVector3(_manualRotationMatrix, rotZ, zAxis);
        lastRot = rotation;
    }
    
}

#pragma mark - FORCE ORIENTATION
- (void)setOrientation:(Orientation)orientation {
    bool isInv;
    if (orientation == OrientationA) {
        self.rotationMatrix = GLKMatrix4Identity;
    } else if(orientation == OrientationI) { //Inferior
        self.rotationMatrix  = GLKMatrix4MakeRotation(GLKMathDegreesToRadians(-90), 1, 0, 0);
    } else if(orientation == OrientationL) { //Left Lateral
        self.rotationMatrix  = GLKMatrix4MakeRotation(GLKMathDegreesToRadians(-90), 0, 1, 0);
        GLKVector3 zAxis = GLKMatrix4MultiplyVector3(GLKMatrix4Invert(self.rotationMatrix, &isInv), GLKVector3Make(0, 0, 1));
        self.rotationMatrix = GLKMatrix4RotateWithVector3(self.rotationMatrix, GLKMathDegreesToRadians(-90), zAxis);
    } else if(orientation == OrientationP) { //Posterior
        self.rotationMatrix = GLKMatrix4MakeRotation(GLKMathDegreesToRadians(-180), 0, 1, 0);
    } else if(orientation == OrientationR) { //Right Lateral
        self.rotationMatrix  = GLKMatrix4MakeRotation(GLKMathDegreesToRadians(90), 0, 1, 0);
        GLKVector3 zAxis = GLKMatrix4MultiplyVector3(GLKMatrix4Invert(self.rotationMatrix, &isInv), GLKVector3Make(0, 0, 1));
        self.rotationMatrix = GLKMatrix4RotateWithVector3(self.rotationMatrix, GLKMathDegreesToRadians(90), zAxis);
    } else if(orientation == OrientationS) { //Superior
        self.rotationMatrix  = GLKMatrix4MakeRotation(GLKMathDegreesToRadians(90), 1, 0, 0);
        GLKVector3 zAxis = GLKMatrix4MultiplyVector3(GLKMatrix4Invert(self.rotationMatrix, &isInv), GLKVector3Make(0, 0, 1));
        self.rotationMatrix = GLKMatrix4RotateWithVector3(self.rotationMatrix, GLKMathDegreesToRadians(180), zAxis);
    }
}

-(void)reset {
    _manualRotationMatrix = GLKMatrix4Identity;
}

@end
