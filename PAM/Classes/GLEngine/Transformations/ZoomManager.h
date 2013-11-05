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
@property (nonatomic, assign) GLKVector3 doubleTapZoomLocation;
@property (nonatomic, assign) BOOL isDoubleTapZoomed;

- (void)handlePinchGesture:(UIGestureRecognizer *)sender;
- (void)handleDoubleTapGesture:(UIGestureRecognizer *)sender;
- (void)handleTwoFingerTapGesture:(UIGestureRecognizer *)sender;
- (void)setScaleFactor:(GLfloat)value;
@end
