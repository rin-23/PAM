//
//  PanManager.m
//  Pelvic-iOS
//
//  Created by Rinat Abdrashitov on 2012-10-25.
//
//

#import "TranslationManager.h"
#import "RotationManager.h"

@interface TranslationManager() {
    GLKMatrix4 accumulatedTranslation;
}
@end

@implementation TranslationManager

-(id)init {
    self = [super init];
    if (self) {
        self.translationMatrix = GLKMatrix4Identity;
        accumulatedTranslation = GLKMatrix4Identity;
        _scaleFactor = 1.0;
    }
    return self;
} 

- (void)handlePanGesture:(UIGestureRecognizer *)sender withViewMatrix:(GLKMatrix4)viewMatrix {
    UIPanGestureRecognizer* pan = (UIPanGestureRecognizer*)sender;

    CGPoint point = [pan translationInView:pan.view];
    
    GLfloat ratio = pan.view.frame.size.height/pan.view.frame.size.width;
    GLfloat x_ndc = point.x/pan.view.frame.size.width;
    GLfloat y_ndc = -1*(point.y/pan.view.frame.size.height)*ratio;
   
    if (sender.state == UIGestureRecognizerStateBegan){
//        NSLog(@"Pan Began");
    } else if (sender.state == UIGestureRecognizerStateChanged) {
//        NSLog(@"Pan Changed");
        bool isInvertible;
        GLKVector3 axis = GLKMatrix4MultiplyVector3(GLKMatrix4Invert(viewMatrix, &isInvertible),
                                                     GLKVector3Make(x_ndc*_scaleFactor, y_ndc*_scaleFactor, 0));
        
        self.translationMatrix = GLKMatrix4TranslateWithVector3(accumulatedTranslation, axis);
    } else if (sender.state == UIGestureRecognizerStateEnded) {
//        NSLog(@"Pan Ended");
        accumulatedTranslation = self.translationMatrix;
    }

//    NSLog(@"Pan: %f/%f",  x_ndc, y_ndc);
}

-(void)reset {
    _translationMatrix = GLKMatrix4Identity;
    accumulatedTranslation = GLKMatrix4Identity;
}




@end
