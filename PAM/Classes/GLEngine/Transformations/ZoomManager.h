//
//  ZoomManager.h
//  Pelvic-iOS
//
//  Created by Rinat Abdrashitov on 12-10-22.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <GLKit/GLKit.h>

@interface ZoomManager : NSObject {
    GLfloat _scaleFactor;
}

@property (nonatomic, assign) GLfloat scaleFactor;
@property (nonatomic, assign) GLKMatrix4 scaleMatrix;

- (void)handlePinchGesture:(UIGestureRecognizer *)sender;
- (void)setScaleFactor:(GLfloat)value;
@end
