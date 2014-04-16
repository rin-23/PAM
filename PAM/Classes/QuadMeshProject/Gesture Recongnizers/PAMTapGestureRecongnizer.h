//
//  PAMTapGestureRecongnizer.h
//  PAM
//
//  Created by Rinat Abdrashitov on 2014-04-16.
//  Copyright (c) 2014 Rinat Abdrashitov. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <UIKit/UIGestureRecognizerSubclass.h>
@interface PAMTapGestureRecongnizer : UITapGestureRecognizer

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event;
- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event;
- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event;

-(float)touchSize;

@end
