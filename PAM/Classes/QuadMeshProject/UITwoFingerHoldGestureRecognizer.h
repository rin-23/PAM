//
//  UITwoFingerHoldGestureRecognizer.h
//  PAM
//
//  Created by Rinat Abdrashitov on 2013-11-12.
//  Copyright (c) 2013 Rinat Abdrashitov. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <UIKit/UIGestureRecognizerSubclass.h>

@interface UITwoFingerHoldGestureRecognizer : UIGestureRecognizer

- (void)reset;
- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event;
- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event;
- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event;
- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event;

-(BOOL)needsMoreTouch; //should receive more touch events
-(CGPoint)locationInView:(UIView*)view; //centroid
-(CGPoint)locationOfTouch:(NSUInteger)touchIndex inView:(UIView*)view; // the location of a particular touch

@end
