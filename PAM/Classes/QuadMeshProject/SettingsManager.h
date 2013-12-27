//
//  SettingsManager.h
//  PAM
//
//  Created by Rinat Abdrashitov on 12/25/2013.
//  Copyright (c) 2013 Rinat Abdrashitov. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface SettingsManager : NSObject

+(SettingsManager*)sharedInstance;

@property (nonatomic, assign) BOOL transform;
@property (nonatomic, assign) BOOL showSkeleton;

@end
