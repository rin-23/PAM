//
//  QuadMeshViewController.h
//  Ossa
//
//  Created by Rinat Abdrashitov on 2013-10-14.
//  Copyright (c) 2013 Rinat Abdrashitov. All rights reserved.
//

#import <GLKit/GLKit.h>
#import "SettingsViewController.h"

@interface BaseQuadMeshViewController : GLKViewController <SettingsViewControllerDelegate>  {
    UIActivityIndicatorView* _activity;
    GLsizei _glWidth;
    GLsizei _glHeight;

    UIViewController* _settingsController;
    UIPopoverController* _settingsPopover;
    
    UILabel* _transformModeLabel;
    UILabel* _hintLabel;
}

-(void)showLoadingIndicator;
-(void)hideLoadingIndicator;

@end
