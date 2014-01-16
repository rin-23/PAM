//
//  SettingsViewController.m
//  PAM
//
//  Created by Rinat Abdrashitov on 12/25/2013.
//  Copyright (c) 2013 Rinat Abdrashitov. All rights reserved.
//

#import "SettingsViewController.h"
#import "SettingsManager.h"

@interface SettingsViewController ()

@end

@implementation SettingsViewController

- (id)init
{
    self = [super init];
    if (self) {
        // Custom initialization

    }
    return self;
}

-(void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view.
    
    self.view.backgroundColor = [UIColor whiteColor];
    
    int nextY = 10;
    UILabel* skeletonLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, nextY, 100, 30)];
    [skeletonLabel setText:@"Skeleton"];
    [self.view addSubview:skeletonLabel];
    
    _skeletonSwitch = [[UISwitch alloc] initWithFrame:CGRectMake(145, nextY, 30, 20)];
    [_skeletonSwitch addTarget:self action:@selector(skeletonSwitchClicked:) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:_skeletonSwitch];
    
    nextY = CGRectGetMaxY(skeletonLabel.frame);
    UILabel* transformLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, nextY + 10, 100, 30)];
    [transformLabel setText:@"Transform"];
    [self.view addSubview:transformLabel];
    
    _transformSwitch = [[UISwitch alloc] initWithFrame:CGRectMake(145, nextY + 10, 30, 20)];
    [_transformSwitch addTarget:self action:@selector(transformSwitchClicked:) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:_transformSwitch];
    
    nextY = CGRectGetMaxY(transformLabel.frame);
    _clearModelBtn = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    [_clearModelBtn setFrame:CGRectMake(15, nextY + 10, 100, 30)];
    [_clearModelBtn setContentHorizontalAlignment:UIControlContentHorizontalAlignmentLeft];
    [_clearModelBtn addTarget:self action:@selector(clearModelButton:) forControlEvents:UIControlEventTouchUpInside];
    [_clearModelBtn setTitle:@"Clear Model" forState:UIControlStateNormal];
    [self.view addSubview:_clearModelBtn];
    
    nextY = CGRectGetMaxY(_clearModelBtn.frame);
    _resetBtn = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    [_resetBtn setContentHorizontalAlignment:UIControlContentHorizontalAlignmentLeft];
    [_resetBtn setTitle:@"Reset" forState:UIControlStateNormal];
    [_resetBtn addTarget:self action:@selector(resetButton:) forControlEvents:UIControlEventTouchUpInside];
    [_resetBtn setFrame:CGRectMake(15, nextY + 10, 100, 30)];
    [self.view addSubview:_resetBtn];
    
    
    nextY = CGRectGetMaxY(_resetBtn.frame);
    _showRibJunctionsBtn = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    [_showRibJunctionsBtn setContentHorizontalAlignment:UIControlContentHorizontalAlignmentLeft];
    [_showRibJunctionsBtn setTitle:@"Show Rib Junctions" forState:UIControlStateNormal];
    [_showRibJunctionsBtn addTarget:self action:@selector(showRibJunctions:) forControlEvents:UIControlEventTouchUpInside];
    [_showRibJunctionsBtn setFrame:CGRectMake(15, nextY + 10, 200, 30)];
    [self.view addSubview:_showRibJunctionsBtn];
    
    nextY = CGRectGetMaxY(_showRibJunctionsBtn.frame);
    _loadArmadillo = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    [_loadArmadillo setContentHorizontalAlignment:UIControlContentHorizontalAlignmentLeft];
    [_loadArmadillo setTitle:@"Load Armadillo" forState:UIControlStateNormal];
    [_loadArmadillo addTarget:self action:@selector(loadArmadillo:) forControlEvents:UIControlEventTouchUpInside];
    [_loadArmadillo setFrame:CGRectMake(15, nextY + 10, 200, 30)];
    [self.view addSubview:_loadArmadillo];
    
    nextY = CGRectGetMaxY(_loadArmadillo.frame);
    _subdivide = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    [_subdivide setContentHorizontalAlignment:UIControlContentHorizontalAlignmentLeft];
    [_subdivide setTitle:@"Subdivide" forState:UIControlStateNormal];
    [_subdivide addTarget:self action:@selector(subdivide:) forControlEvents:UIControlEventTouchUpInside];
    [_subdivide setFrame:CGRectMake(15, nextY + 10, 200, 30)];
    [self.view addSubview:_subdivide];
    
    if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPhone) {
        UIButton* dismissButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
        [dismissButton setBackgroundColor:[UIColor lightGrayColor]];
        [dismissButton setFrame:CGRectMake(20, self.view.frame.size.height - 60, self.view.frame.size.width - 40, 40)];
        [dismissButton setAutoresizingMask:UIViewAutoresizingFlexibleTopMargin|UIViewAutoresizingFlexibleWidth];
        [dismissButton addTarget:self action:@selector(dismissButtonClicked:) forControlEvents:UIControlEventTouchUpInside];
        [dismissButton setTitle:@"OK" forState:UIControlStateNormal];
        [dismissButton.titleLabel setFont:[UIFont systemFontOfSize:15.0f]];
        [self.view addSubview:dismissButton];
    }
}

-(void)viewWillAppear:(BOOL)animated {
    [_transformSwitch setOn:[SettingsManager sharedInstance].transform];
    [_skeletonSwitch setOn:[SettingsManager sharedInstance].showSkeleton];
}

-(void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

-(void)skeletonSwitchClicked:(UIControl*)sender {
    [self.delegate showSkeleton:_skeletonSwitch.isOn];
}

-(void)transformSwitchClicked:(UIControl*)sender {
    [self.delegate transformModeIsOn:_transformSwitch.isOn];
}

-(void)clearModelButton:(UIControl*)sender {
    [self.delegate clearModel];
}

-(void)resetButton:(UIControl*)sender {
    [self.delegate resetTransformations];
}

-(void)showRibJunctions:(UIControl*)sender {
    [self.delegate showRibJunctions];
}

-(void)loadArmadillo:(UIControl*)sender {
    [self.delegate loadArmadillo];
}

-(void)subdivide:(UIControl*)sender {
    [self.delegate subdivide];
}
-(void)dismissButtonClicked:(UIControl*)sender {
    [self.delegate dismiss];
}


@end
