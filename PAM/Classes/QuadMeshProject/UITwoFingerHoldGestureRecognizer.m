//
//  UITwoFingerHoldGestureRecognizer.m
//  PAM
//
//  Created by Rinat Abdrashitov on 2013-11-12.
//  Copyright (c) 2013 Rinat Abdrashitov. All rights reserved.
//

#import "UITwoFingerHoldGestureRecognizer.h"

@interface UITwoFingerHoldGestureRecognizer() {
    UITouch* t1;
    UITouch* t2;
}
@end

@implementation UITwoFingerHoldGestureRecognizer

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    [super touchesBegan:touches withEvent:event];
    if (self.state == UIGestureRecognizerStatePossible) { //ignore all other touches after gesture recognized
        NSArray* touchesArray = [touches allObjects];
        if ([touches count] == 2) {
            t1 = touchesArray[0];
            t2 = touchesArray[1];
            [self setState:UIGestureRecognizerStateBegan];
        } else if ([touches count] == 1) {
            if (t1 == nil && t2 == nil) {
                t1 = touchesArray[0];
                [self setState:UIGestureRecognizerStatePossible];
            } else if (t2 == nil && t1 != nil) {
                t2 = touchesArray[0];
                [self setState:UIGestureRecognizerStateBegan];
            }
        } else {
            [self setState:UIGestureRecognizerStateFailed];
        }
    }
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event {
    [super touchesMoved:touches withEvent:event];
    if (self.state == UIGestureRecognizerStateFailed) return;
    if (self.state != UIGestureRecognizerStateBegan && self.state != UIGestureRecognizerStateChanged) return;
    
//    if (t1 != nil && t2 != nil) {
//        for (UITouch* t in [touches allObjects]) {
//            if (t == t1 || t == t2) {
////                self.state = UIGestureRecognizerStateChanged;
//            }
//        }
//    }
    
    if (t1 == nil && t2 == nil) {
        [self setState:UIGestureRecognizerStateCancelled];
    }
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    [super touchesEnded:touches withEvent:event];
    if (self.state == UIGestureRecognizerStateChanged) {
        if (t1 != nil && t2 != nil) {
            for (UITouch* t in [touches allObjects]) {
                if (t == t1 || t == t2) {
//                    t1 = nil;
//                    t2 = nil;
                    [self setState:UIGestureRecognizerStateEnded];
                    return;
                }
            }
        }
    }
    
//    if ([touches containsObject:t1]) {
//        t1 = nil;
//    }
//    
//    if ([touches containsObject:t2]) {
//        t2 = nil;
//    }
    
    if (t1 == nil || t2 == nil) {
        [self setState:UIGestureRecognizerStateCancelled];
    }

}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event {
    [super touchesCancelled:touches withEvent:event];
    [self setState:UIGestureRecognizerStateFailed];
}

-(CGPoint)locationInView:(UIView*)view
{
    if (t1 == nil || t2 ==nil) {
        NSLog(@"[ERROR][UITwoFingerHoldGestureRecognizer][locationInView] Touch is nil");
        return CGPointMake(0, 0);
    }
    CGPoint t1Location = [t1 locationInView:view];
    CGPoint t2Location = [t2 locationInView:view];
    CGPoint centroid = CGPointMake((t1Location.x + t2Location.x)/2 , (t1Location.y + t2Location.y)/2);
    return centroid;
}

-(CGPoint)locationOfTouch:(NSUInteger)touchIndex inView:(UIView*)view {
    UITouch* t;
    if (touchIndex == 0) {
        t = t1;
    } else if (touchIndex == 1) {
        t = t2;
    }
    
    if (t == nil) {
        NSLog(@"[ERROR][UITwoFingerHoldGestureRecognizer][locationOfTouch:inView:] Touch is nil");
        return CGPointMake(0, 0);
    } else {
        return [t locationInView:view];
    }
}

-(void)reset{
    [super reset];
    t1 = nil;
    t2 = nil;
}

-(BOOL)needsMoreTouch {
    return t1 == nil || t2 == nil;
}


@end
