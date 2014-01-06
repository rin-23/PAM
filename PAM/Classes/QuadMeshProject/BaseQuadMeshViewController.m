//
//  QuadMeshViewController.m
//  Ossa
//
//  Created by Rinat Abdrashitov on 2013-10-14.
//  Copyright (c) 2013 Rinat Abdrashitov. All rights reserved.
//

#import "BaseQuadMeshViewController.h"
#import "AGLKContext.h"


@interface BaseQuadMeshViewController ()

@end

@implementation BaseQuadMeshViewController

- (id)init
{
    self = [super init];
    if (self) {
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view.
    self.navigationController.navigationBarHidden = YES;

    GLKView* view = [[GLKView alloc] initWithFrame:CGRectMake(0, 0, self.view.frame.size.width, self.view.frame.size.height)];
    view.multipleTouchEnabled = YES;
//    view.contentScaleFactor = 1.0f;
    view.drawableDepthFormat = GLKViewDrawableDepthFormat16;
    
    // Create an OpenGL ES 2.0 context and provide it to the view
    view.context = [[AGLKContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
    [AGLKContext setCurrentContext:view.context];
    
    ((AGLKContext *)view.context).clearColor = GLKVector4Make(1.0f, 1.0f, 1.0f, 1.0f);
    
    _activity = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    _activity.center =  CGPointMake(self.view.frame.size.width/2, self.view.frame.size.height/2);
    _activity.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin|UIViewAutoresizingFlexibleRightMargin|UIViewAutoresizingFlexibleTopMargin|UIViewAutoresizingFlexibleBottomMargin;

    UIButton* settingsIcon = [UIButton buttonWithType:UIButtonTypeInfoDark];
    [settingsIcon setFrame:CGRectMake(10, 10, 30, 30)];
    [settingsIcon addTarget:self action:@selector(settingsButtonClicked:) forControlEvents:UIControlEventTouchUpInside];
    [view addSubview:settingsIcon];
    
    
    SettingsViewController* contentViewContoller = [[SettingsViewController alloc] init];
    contentViewContoller.delegate = self;
    
    if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        _settingsPopover = [[UIPopoverController alloc] initWithContentViewController:contentViewContoller];
    } else {
        _settingsController = contentViewContoller;
    }
    
    _transformModeLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 150, 30)];
    _transformModeLabel.textColor = [UIColor blackColor];
    _transformModeLabel.textAlignment = NSTextAlignmentCenter;
    _transformModeLabel.center = CGPointMake(self.view.frame.size.width/2, _transformModeLabel.frame.size.height/2);
    _transformModeLabel.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin|UIViewAutoresizingFlexibleRightMargin;
    _transformModeLabel.alpha = 0.0f;
    [view addSubview:_transformModeLabel];
    
    self.view = view;
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation {
    _glWidth = ((GLKView*)self.view).drawableWidth;
    _glHeight = ((GLKView*)self.view).drawableHeight;
}

-(void)settingsButtonClicked:(UIButton*)btn {
    if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        if (_settingsPopover.isPopoverVisible) {
            [_settingsPopover dismissPopoverAnimated:YES];
        } else {
            [_settingsPopover presentPopoverFromRect:CGRectMake(10, 10, 30, 30)
                                              inView:self.view
                            permittedArrowDirections:UIPopoverArrowDirectionAny animated:YES];
        }
    } else {
        
        [self presentViewController:_settingsController animated:YES completion:^{}];
    }
}

-(void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    _glWidth = ((GLKView*)self.view).drawableWidth;
    _glHeight = ((GLKView*)self.view).drawableHeight;

    // We must be the first responder to receive shake events for undo.
	[self becomeFirstResponder];
}

-(void)viewWillDisappear:(BOOL)animated {
    
    // You should resign first responder status when exiting the screen.
	[self resignFirstResponder];
    [super viewWillDisappear:animated];
}

-(BOOL)canBecomeFirstResponder {
	return YES;
}

-(void)showLoadingIndicator {
    if (_activity) {
        [self.view addSubview:_activity];
        [self.view bringSubviewToFront:_activity];
    }
    [_activity startAnimating];
}

-(void)hideLoadingIndicator {
    [_activity stopAnimating];
}

-(void)dismiss {
    [self dismissViewControllerAnimated:YES completion:nil];
}
@end
