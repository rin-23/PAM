//
//  SettingsManager.m
//  PAM
//
//  Created by Rinat Abdrashitov on 12/25/2013.
//  Copyright (c) 2013 Rinat Abdrashitov. All rights reserved.
//

#import "SettingsManager.h"

static SettingsManager* instance = nil;

@implementation SettingsManager

-(id)init {
    self = [super init];
    if (self) {
        _transform = NO;
        _showSkeleton = NO;
    }
    return self;
}

+(SettingsManager*)sharedInstance {
    if (instance == nil) {
        instance = [[SettingsManager alloc] init];
    }
    return instance;
}

@end
