//
//  PAMUtilities.h
//  PAM
//
//  Created by Rinat Abdrashitov on 2013-11-27.
//  Copyright (c) 2013 Rinat Abdrashitov. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <GLKit/GLKMath.h>
#include <vector>

@interface PAMUtilities : NSObject

-(std::vector<GLKVector3>)sampleBranch:(std::vector<GLKVector3>)inBranch;

@end
