//
//  ArcBallRotationManager.h
//  Pelvic-iOS
//
//  Created by Rinat Abdrashitov on 12-10-22.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <GLKit/GLKit.h>

typedef enum {
    OrientationA,
    OrientationL,
    OrientationP,
    OrientationR,
    OrientationS,
    OrientationI
} Orientation;

@interface RotationManager : NSObject

//Rotation matrix that combines arcball rotation and rotation in the plane of the screen
@property (nonatomic, assign) GLKMatrix4 rotationMatrix;

-(void)setOrientation:(Orientation)orientation; //Force certain orientation

-(void)handlePanGesture:(UIGestureRecognizer*)sender withViewMatrix:(GLKMatrix4)viewMatrix isOrthogonal:(BOOL)isOrtho; //ArcBall Rotation
-(void)handleRotationGesture:(UIGestureRecognizer *)sender withViewMatrix:(GLKMatrix4)viewMatrix; //Rotation in the plane of the screen
-(void)reset;
@end
