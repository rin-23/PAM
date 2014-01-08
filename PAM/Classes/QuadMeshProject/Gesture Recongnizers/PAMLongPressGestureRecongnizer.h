//
//  PAMLongPressGestureRecongnizer.h
//  PAM
//
//  Created by Rinat Abdrashitov on 2014-01-08.
//  Copyright (c) 2014 Rinat Abdrashitov. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <UIKit/UIGestureRecognizerSubclass.h>

@interface PAMLongPressGestureRecongnizer : UILongPressGestureRecognizer

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event;
- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event;
- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event;

-(NSArray*)touches;

@end
