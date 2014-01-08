//
//  PAMLongPressGestureRecongnizer.m
//  PAM
//
//  Created by Rinat Abdrashitov on 2014-01-08.
//  Copyright (c) 2014 Rinat Abdrashitov. All rights reserved.
//

#import "PAMLongPressGestureRecongnizer.h"

@interface PAMLongPressGestureRecongnizer() {
    NSArray* _customTouches;
}
@property (nonatomic, strong) NSArray* customTouches;
@end

@implementation PAMLongPressGestureRecongnizer

-(void)reset {
    _customTouches = nil;
}

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

-(NSArray*)touches {
    return _customTouches;
}

@end
