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
        // Custom initialization
        UIBarButtonItem* resetItem = [[UIBarButtonItem alloc] initWithTitle:@"Reset" style:UIBarButtonItemStylePlain target:self action:@selector(resetClicked:)];
        [self.navigationItem setLeftBarButtonItems:@[resetItem]];
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view.

    GLKView* view = [[GLKView alloc] initWithFrame:CGRectMake(0, 20, self.view.frame.size.width, self.view.frame.size.height - 44)];
    view.multipleTouchEnabled = YES;
    view.drawableDepthFormat = GLKViewDrawableDepthFormat24;
    self.view = view;
    
    // Create an OpenGL ES 2.0 context and provide it to the view
    view.context = [[AGLKContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
    [AGLKContext setCurrentContext:view.context];
    
    ((AGLKContext *)view.context).clearColor = GLKVector4Make(1.0f, 1.0f, 1.0f, 1.0f);
    
    _activity = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    _activity.center =  CGPointMake(self.view.frame.size.width/2, self.view.frame.size.height/2);
    _activity.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin|UIViewAutoresizingFlexibleRightMargin|UIViewAutoresizingFlexibleTopMargin|UIViewAutoresizingFlexibleBottomMargin;

    _transformSwitch = [[UISwitch alloc] initWithFrame:CGRectMake(5, 75, 30, 20)];
    [view addSubview:_transformSwitch];
    
    _branchWidthSlider = [[UISlider alloc] initWithFrame:CGRectMake(65, 85, 130, 10)];
    [view addSubview:_branchWidthSlider];

    _skeletonSwitch = [[UISwitch alloc] initWithFrame:CGRectMake(200, 75, 30, 20)];    
    [view addSubview:_skeletonSwitch];
}

-(void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    _glWidth = ((GLKView*)self.view).drawableWidth;
    _glHeight = ((GLKView*)self.view).drawableHeight;
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

-(void)resetClicked:(id)sender {
    //overwrite
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
