//
//  PAMPanGestureRecognizer.m
//  PAM
//
//  Created by Rinat Abdrashitov on 12/27/2013.
//  Copyright (c) 2013 Rinat Abdrashitov. All rights reserved.
//

#import "PAMPanGestureRecognizer.h"

@interface PAMPanGestureRecognizer() {
    NSArray* _customTouches;
}
@property (nonatomic, strong) NSArray* customTouches;
@end

@implementation PAMPanGestureRecognizer

@synthesize customTouches = _customTouches;

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    [super touchesBegan:touches withEvent:event];
    self.customTouches = [touches allObjects];
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event {
    [super touchesMoved:touches withEvent:event];
    self.customTouches = [touches allObjects];
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    [super touchesEnded:touches withEvent:event];
    self.customTouches = [touches allObjects];
}

-(float)touchSize {
    if (self.customTouches.count > 0) {
        UITouch* touch = [self.customTouches lastObject];
        float touchSize = [[touch valueForKey:@"pathMajorRadius"] floatValue];
        return touchSize;
    }
    NSLog(@"[WARNING][PAMPanGestureRecognizer] Zero touches");
    return 0;
}

@end
