//
//  GyroRotationManager.h
//  Ossa
//
//  Created by Rinat Abdrashitov on 2013-09-14.
//  Copyright (c) 2013 Rinat Abdrashitov. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <GLKit/GLKMath.h>

@interface GyroRotationManager : NSObject

+(id)sharedInstance;

@property (nonatomic, assign) GLKMatrix4 rotationMatrix;

- (void)enableGyro;
- (void)disableGyro;

-(void)captureReferenceAttitudeAndMatrix:(GLKMatrix4)referenceMatrix;
-(void)reset;

@end
