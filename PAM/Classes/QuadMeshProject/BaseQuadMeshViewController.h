//
//  QuadMeshViewController.h
//  Ossa
//
//  Created by Rinat Abdrashitov on 2013-10-14.
//  Copyright (c) 2013 Rinat Abdrashitov. All rights reserved.
//

#import <GLKit/GLKit.h>

@interface BaseQuadMeshViewController : GLKViewController  {
    UIActivityIndicatorView* _activity;
    GLsizei _glWidth;
    GLsizei _glHeight;
    UISwitch* _transformSwitch;
}

-(void)showLoadingIndicator;
-(void)hideLoadingIndicator;

@end
