//
//  ZoomManager.m
//  Pelvic-iOS
//
//  Created by Rinat Abdrashitov on 12-10-22.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import "ZoomManager.h"

@interface ZoomManager() {
    GLfloat _curFactor;
}
@end


@implementation ZoomManager

@synthesize scaleFactor = _scaleFactor;

-(id) init {
    self = [super init];
    if (self) {
        _scaleFactor = 1.0;
    }
    return self;
}

- (GLKMatrix4)scaleMatrix{
    if (_scaleFactor < 0) {
        _scaleFactor = 0;
    }
    //    NSLog(@"Scale Factor %f", _scaleFactor);
    return GLKMatrix4MakeScale(_scaleFactor, _scaleFactor, _scaleFactor);
}

- (void)setScaleMatrix:(GLKMatrix4)scaleMatrix{
    //Must be uniform scaling matrix for now
    _scaleFactor = scaleMatrix.m00;
}

- (void)setScaleFactor:(GLfloat)value{
    _scaleFactor = value;
}

- (void)handlePinchGesture:(UIGestureRecognizer *)sender {
    UIPinchGestureRecognizer* pinch = (UIPinchGestureRecognizer*) sender;
    NSLog(@"Scale %f Velocity %f", [pinch scale], [pinch velocity]);
    
    if (sender.state == UIGestureRecognizerStateBegan) {
        _curFactor = _scaleFactor;
    } else {
        _scaleFactor = _curFactor * [pinch scale];
    }
}


@end
