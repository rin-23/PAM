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
        self.doubleTapZoomLocation = GLKVector3Make(0, 0, 0);
        self.isDoubleTapZoomed = NO;
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
//    NSLog(@"Scale %f Velocity %f", [pinch scale], [pinch velocity]);
    
    if (sender.state == UIGestureRecognizerStateBegan) {
        _curFactor = _scaleFactor;
    } else {
        _scaleFactor = _curFactor * [pinch scale];
    }
}

- (void)handleDoubleTapGesture:(UIGestureRecognizer *)sender {
    
    if (!self.isDoubleTapZoomed) {
        
        UITapGestureRecognizer* tap = (UITapGestureRecognizer*)sender;
        float aspectRatio=tap.view.frame.size.height/tap.view.frame.size.width;
        
        CGPoint touchLocation = [tap locationInView:tap.view];
        CGPoint center = tap.view.center;
        
        self.isDoubleTapZoomed = YES;
        self.doubleTapZoomLocation = GLKVector3Make(2*(touchLocation.x - center.x)/tap.view.frame.size.width,
                                                    -2*(touchLocation.y - center.y)*aspectRatio/tap.view.frame.size.height,
                                                    0);
    }
    
}

- (void)handleTwoFingerTapGesture:(UIGestureRecognizer *)sender {
    self.isDoubleTapZoomed = NO;
}

@end
