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
    contentView = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    contentView.autoresizingMask=UIViewAutoresizingFlexibleHeight|UIViewAutoresizingFlexibleWidth;

    [self.view addSubview:contentView];
    self.view.backgroundColor = [UIColor whiteColor];
    contentView.backgroundColor = [UIColor whiteColor];
    
    int nextY = 10;
    UILabel* skeletonLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, nextY, 100, 30)];
    [skeletonLabel setText:@"Skeleton"];
    [contentView addSubview:skeletonLabel];
    
    _skeletonSwitch = [[UISwitch alloc] initWithFrame:CGRectMake(145, nextY, 30, 20)];
    [_skeletonSwitch addTarget:self action:@selector(skeletonSwitchClicked:) forControlEvents:UIControlEventValueChanged];
    [contentView addSubview:_skeletonSwitch];
    
//    nextY = CGRectGetMaxY(skeletonLabel.frame);
//    UILabel* transformLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, nextY + 10, 100, 30)];
//    [transformLabel setText:@"Transform"];
//    [contentView addSubview:transformLabel];
    
//    _transformSwitch = [[UISwitch alloc] initWithFrame:CGRectMake(145, nextY + 10, 30, 20)];
//    [_transformSwitch addTarget:self action:@selector(transformSwitchClicked:) forControlEvents:UIControlEventValueChanged];
//    [contentView addSubview:_transformSwitch];
    
    nextY = CGRectGetMaxY(skeletonLabel.frame);
    _clearModelBtn = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    [_clearModelBtn setFrame:CGRectMake(15, nextY + 10, 100, 30)];
    [_clearModelBtn setContentHorizontalAlignment:UIControlContentHorizontalAlignmentLeft];
    [_clearModelBtn addTarget:self action:@selector(clearModelButton:) forControlEvents:UIControlEventTouchUpInside];
    [_clearModelBtn setTitle:@"Clear Model" forState:UIControlStateNormal];
    [contentView addSubview:_clearModelBtn];
    
    nextY = CGRectGetMaxY(_clearModelBtn.frame);
    _resetBtn = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    [_resetBtn setContentHorizontalAlignment:UIControlContentHorizontalAlignmentLeft];
    [_resetBtn setTitle:@"Reset" forState:UIControlStateNormal];
    [_resetBtn addTarget:self action:@selector(resetButton:) forControlEvents:UIControlEventTouchUpInside];
    [_resetBtn setFrame:CGRectMake(15, nextY + 10, 100, 30)];
    [contentView addSubview:_resetBtn];
    
    nextY = CGRectGetMaxY(_resetBtn.frame);
    _showRibJunctionsBtn = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    [_showRibJunctionsBtn setContentHorizontalAlignment:UIControlContentHorizontalAlignmentLeft];
    [_showRibJunctionsBtn setTitle:@"Show Rib Junctions" forState:UIControlStateNormal];
    [_showRibJunctionsBtn addTarget:self action:@selector(showRibJunctions:) forControlEvents:UIControlEventTouchUpInside];
    [_showRibJunctionsBtn setFrame:CGRectMake(15, nextY + 10, 200, 30)];
    [contentView addSubview:_showRibJunctionsBtn];
    
    nextY = CGRectGetMaxY(_showRibJunctionsBtn.frame);
    _loadArmadillo = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    [_loadArmadillo setContentHorizontalAlignment:UIControlContentHorizontalAlignmentLeft];
    [_loadArmadillo setTitle:@"Load Armadillo" forState:UIControlStateNormal];
    [_loadArmadillo addTarget:self action:@selector(loadArmadillo:) forControlEvents:UIControlEventTouchUpInside];
    [_loadArmadillo setFrame:CGRectMake(15, nextY + 10, 200, 30)];
    [contentView addSubview:_loadArmadillo];
    
    nextY = CGRectGetMaxY(_loadArmadillo.frame);
    _subdivide = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    [_subdivide setContentHorizontalAlignment:UIControlContentHorizontalAlignmentLeft];
    [_subdivide setTitle:@"Subdivide" forState:UIControlStateNormal];
    [_subdivide addTarget:self action:@selector(subdivide:) forControlEvents:UIControlEventTouchUpInside];
    [_subdivide setFrame:CGRectMake(15, nextY + 10, 200, 30)];
    [contentView addSubview:_subdivide];
    
    
    nextY = CGRectGetMaxY(_subdivide.frame);
    _saveObjFile = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    [_saveObjFile setContentHorizontalAlignment:UIControlContentHorizontalAlignmentLeft];
    [_saveObjFile setTitle:@"Save and email obj" forState:UIControlStateNormal];
    [_saveObjFile addTarget:self action:@selector(emailObj:) forControlEvents:UIControlEventTouchUpInside];
    [_saveObjFile setFrame:CGRectMake(15, nextY + 10, 200, 30)];
    [contentView addSubview:_saveObjFile];
    
    /*
     * BRANCH CREATION
     */
    
    nextY = CGRectGetMaxY(_saveObjFile.frame);
    UILabel* branchCreationHeader = [[UILabel alloc] initWithFrame:CGRectMake(15, nextY + 10, 300, 30)];
    [branchCreationHeader setText:@"BRANCH CREATION SETTINGS"];
    branchCreationHeader.font = [UIFont boldSystemFontOfSize:15.0f];
    branchCreationHeader.adjustsFontSizeToFitWidth = YES;
    branchCreationHeader.textAlignment = NSTextAlignmentCenter;
    [contentView addSubview:branchCreationHeader];

    /******/
    nextY = CGRectGetMaxY(branchCreationHeader.frame);
    UILabel* spineSmoothinLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, nextY, 200, 30)];
    [spineSmoothinLabel setText:@"Spine smoothing"];
    [contentView addSubview:spineSmoothinLabel];
    
    nextY = CGRectGetMaxY(branchCreationHeader.frame);
    _spineSmoothing = [[UISwitch alloc] initWithFrame:CGRectMake(200, nextY, 30, 20)];
    [_spineSmoothing addTarget:self action:@selector(spineSmoothing:) forControlEvents:UIControlEventValueChanged];
    [contentView addSubview:_spineSmoothing];
    
    /******/
    nextY = CGRectGetMaxY(_spineSmoothing.frame) + 10;
    UILabel* poleSmoothing = [[UILabel alloc] initWithFrame:CGRectMake(15, nextY, 200, 30)];
    [poleSmoothing setText:@"Smooth Poles"];
    [contentView addSubview:poleSmoothing];
    
    nextY = CGRectGetMaxY(_spineSmoothing.frame) + 10;
    _poleSmoothing = [[UISwitch alloc] initWithFrame:CGRectMake(200, nextY, 30, 20)];
    [_poleSmoothing addTarget:self action:@selector(poleSmoothing:) forControlEvents:UIControlEventValueChanged];
    [contentView addSubview:_poleSmoothing];
    
    /*****/
    nextY = CGRectGetMaxY(_poleSmoothing.frame);
    UILabel* smoothingBrushSize = [[UILabel alloc] initWithFrame:CGRectMake(15, nextY + 10, 300, 30)];
    [smoothingBrushSize setText:@"Base smoothing multiplier of radius 0.5-2"];
    smoothingBrushSize.adjustsFontSizeToFitWidth = YES;
    [contentView addSubview:smoothingBrushSize];
    
    nextY = CGRectGetMaxY(smoothingBrushSize.frame);
    _smoothingSlider = [[UISlider alloc] init];
    _smoothingSlider.minimumValue = 0.5;
    _smoothingSlider.maximumValue = 2.0;
    [_smoothingSlider addTarget:self action:@selector(smoothingBrushSize:) forControlEvents:UIControlEventValueChanged];
    [_smoothingSlider setFrame:CGRectMake(15, nextY + 10, 200, 30)];
    [contentView addSubview:_smoothingSlider];
    
    nextY = CGRectGetMaxY(_smoothingSlider.frame);
    UILabel* baseSmoothingIterations = [[UILabel alloc] initWithFrame:CGRectMake(15, nextY + 10, 300, 30)];
    [baseSmoothingIterations setText:@"Base smoothing iterations 0-30"];
    baseSmoothingIterations.adjustsFontSizeToFitWidth = YES;
    [contentView addSubview:baseSmoothingIterations];
    
    nextY = CGRectGetMaxY(baseSmoothingIterations.frame);
    _baseSmoothingIterationsSlider = [[UISlider alloc] init];
    _baseSmoothingIterationsSlider.minimumValue = 0;
    _baseSmoothingIterationsSlider.maximumValue = 30;
    [_baseSmoothingIterationsSlider addTarget:self action:@selector(baseSmoothingIterations:) forControlEvents:UIControlEventValueChanged];
    [_baseSmoothingIterationsSlider setFrame:CGRectMake(15, nextY + 10, 200, 30)];
    [contentView addSubview:_baseSmoothingIterationsSlider];
    
    nextY = CGRectGetMaxY(_baseSmoothingIterationsSlider.frame);
    UILabel* thinBranchWidthSizeLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, nextY + 10, 300, 30)];
    [thinBranchWidthSizeLabel setText:@"Small branch width 0-100 degress"];
    thinBranchWidthSizeLabel.adjustsFontSizeToFitWidth = YES;
    [contentView addSubview:thinBranchWidthSizeLabel];
    
    nextY = CGRectGetMaxY(thinBranchWidthSizeLabel.frame);
    _thinBranchWidth = [[UISlider alloc] init];
    _thinBranchWidth.minimumValue = 0;
    _thinBranchWidth.maximumValue = 100;
    [_thinBranchWidth addTarget:self action:@selector(thinBranchWidth:) forControlEvents:UIControlEventValueChanged];
    [_thinBranchWidth setFrame:CGRectMake(15, nextY + 10, 200, 30)];
    [contentView addSubview:_thinBranchWidth];
    
    nextY = CGRectGetMaxY(_thinBranchWidth.frame);
    UILabel* mediumBranchWidthLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, nextY + 10, 300, 30)];
    [mediumBranchWidthLabel setText:@"Medium branch width 0-100 degress"];
    mediumBranchWidthLabel.adjustsFontSizeToFitWidth = YES;
    [contentView addSubview:mediumBranchWidthLabel];
    
    nextY = CGRectGetMaxY(mediumBranchWidthLabel.frame);
    _mediumBranchWidth = [[UISlider alloc] init];
    _mediumBranchWidth.minimumValue = 0;
    _mediumBranchWidth.maximumValue = 100;
    [_mediumBranchWidth addTarget:self action:@selector(mediumBranchWidth:) forControlEvents:UIControlEventValueChanged];
    [_mediumBranchWidth setFrame:CGRectMake(15, nextY + 10, 200, 30)];
    [contentView addSubview:_mediumBranchWidth];
    
    nextY = CGRectGetMaxY(_mediumBranchWidth.frame);
    UILabel* largeBranchWidthLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, nextY + 10, 300, 30)];
    [largeBranchWidthLabel setText:@"Large branch width 0-100 degress"];
    largeBranchWidthLabel.adjustsFontSizeToFitWidth = YES;
    [contentView addSubview:largeBranchWidthLabel];
    
    nextY = CGRectGetMaxY(largeBranchWidthLabel.frame);
    _largeBranchWidth = [[UISlider alloc] init];
    _largeBranchWidth.minimumValue = 0;
    _largeBranchWidth.maximumValue = 100;
    [_largeBranchWidth addTarget:self action:@selector(largeBranchWidth:) forControlEvents:UIControlEventValueChanged];
    [_largeBranchWidth setFrame:CGRectMake(15, nextY + 10, 200, 30)];
    [contentView addSubview:_largeBranchWidth];
    
    
    /*
     * SCULPTING
     */
    
//    nextY = CGRectGetMaxY(_thinBranchWidth.frame);
//    UILabel* suclptingHeader = [[UILabel alloc] initWithFrame:CGRectMake(15, nextY + 10, 300, 30)];
//    [suclptingHeader setText:@"SCULPTING BRUSHES AND SETTINGS"];
//    suclptingHeader.font = [UIFont boldSystemFontOfSize:15.0f];
//    suclptingHeader.adjustsFontSizeToFitWidth = YES;
//    suclptingHeader.textAlignment = NSTextAlignmentCenter;
//    [contentView addSubview:suclptingHeader];
    
//    nextY = CGRectGetMaxY(suclptingHeader.frame);
//    UILabel* silhouetteScalingBrushSizeLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, nextY + 10, 300, 30)];
//    [silhouetteScalingBrushSizeLabel setText:@"Silhouette scalling arc 0-180 degress"];
//    silhouetteScalingBrushSizeLabel.adjustsFontSizeToFitWidth = YES;
//    [contentView addSubview:silhouetteScalingBrushSizeLabel];
//    
//    nextY = CGRectGetMaxY(silhouetteScalingBrushSizeLabel.frame);
//    _silhouetteScalingBrushSize = [[UISlider alloc] init];
//    _silhouetteScalingBrushSize.minimumValue = 0;
//    _silhouetteScalingBrushSize.maximumValue = 100;
//    [_silhouetteScalingBrushSize addTarget:self action:@selector(silhouetteScalingBrushSize:) forControlEvents:UIControlEventValueChanged];
//    [_silhouetteScalingBrushSize setFrame:CGRectMake(15, nextY + 10, 200, 30)];
//    [contentView addSubview:_silhouetteScalingBrushSize];
    
    
//    nextY = CGRectGetMaxY(suclptingHeader.frame);
//    _circularScalingSculpt = [UIButton buttonWithType:UIButtonTypeRoundedRect];
//    [_circularScalingSculpt setContentHorizontalAlignment:UIControlContentHorizontalAlignmentLeft];
//    [_circularScalingSculpt setTitle:@"Circular scaling" forState:UIControlStateNormal];
//    [_circularScalingSculpt addTarget:self action:@selector(scalingSculptTypeChanged:) forControlEvents:UIControlEventTouchUpInside];
//    [_circularScalingSculpt setFrame:CGRectMake(15, nextY + 10, 200, 30)];
//    [contentView addSubview:_circularScalingSculpt];
    
//    nextY = CGRectGetMaxY(suclptingHeader.frame);
//    _silhouetteScalingSculpt = [UIButton buttonWithType:UIButtonTypeRoundedRect];
//    [_silhouetteScalingSculpt setContentHorizontalAlignment:UIControlContentHorizontalAlignmentLeft];
//    [_silhouetteScalingSculpt setTitle:@"Silhouette scaling" forState:UIControlStateNormal];
//    [_silhouetteScalingSculpt addTarget:self action:@selector(scalingSculptTypeChanged:) forControlEvents:UIControlEventTouchUpInside];
//    [_silhouetteScalingSculpt setFrame:CGRectMake(CGRectGetMaxX(_circularScalingSculpt.frame), nextY + 10, 200, 30)];
//    [contentView addSubview:_silhouetteScalingSculpt];
    
    
    
    if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPhone) {
        UIButton* dismissButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
        [dismissButton setBackgroundColor:[UIColor lightGrayColor]];
        [dismissButton setFrame:CGRectMake(20, self.view.frame.size.height - 60, self.view.frame.size.width - 40, 40)];
        [dismissButton setAutoresizingMask:UIViewAutoresizingFlexibleTopMargin|UIViewAutoresizingFlexibleWidth];
        [dismissButton addTarget:self action:@selector(dismissButtonClicked:) forControlEvents:UIControlEventTouchUpInside];
        [dismissButton setTitle:@"OK" forState:UIControlStateNormal];
        [dismissButton.titleLabel setFont:[UIFont systemFontOfSize:15.0f]];
        [contentView addSubview:dismissButton];
    }
    contentView.contentSize = CGSizeMake(300, CGRectGetMaxY(contentView.frame));
}

-(void)viewWillAppear:(BOOL)animated {
    [_transformSwitch setOn:[SettingsManager sharedInstance].transform];
    [_skeletonSwitch setOn:[SettingsManager sharedInstance].showSkeleton];
    _smoothingSlider.value = [SettingsManager sharedInstance].smoothingBrushSize;
    _thinBranchWidth.value = [SettingsManager sharedInstance].thinBranchWidth;
    _mediumBranchWidth.value = [SettingsManager sharedInstance].mediumBranchWidth;
    _largeBranchWidth.value = [SettingsManager sharedInstance].largeBranchWidth;
    _baseSmoothingIterationsSlider.value = [SettingsManager sharedInstance].baseSmoothingIterations;
    [_spineSmoothing setOn:[SettingsManager sharedInstance].spineSmoothing];
    [_poleSmoothing setOn:[SettingsManager sharedInstance].poleSmoothing];
    _silhouetteScalingBrushSize.value = [SettingsManager sharedInstance].silhouetteScalingBrushSize;
}

-(void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

-(void)skeletonSwitchClicked:(UIControl*)sender {
    [self.delegate showSkeleton:_skeletonSwitch.isOn];
}

//-(void)transformSwitchClicked:(UIControl*)sender {
//    [self.delegate transformModeIsOn:_transformSwitch.isOn];
//}

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

-(void)emailObj:(UIControl*)sender {
    [self.delegate emailObj];
}

#pragma mark - BRANCH CREATION
-(void)spineSmoothing:(UISwitch*)sender {
    [self.delegate spineSmoothing:sender.isOn];
}

-(void)poleSmoothing:(UISwitch*)sender {
    [self.delegate poleSmoothing:sender.isOn];
}

-(void)smoothingBrushSize:(UIControl*)sender {
    UISlider* slider = (UISlider*)sender;
    [self.delegate smoothingBrushSize:slider.value];
}

-(void)baseSmoothingIterations:(UIControl*)sender {
    UISlider* slider = (UISlider*)sender;
    [self.delegate baseSmoothingIterations:slider.value];
}

-(void)thinBranchWidth:(UIControl*)sender {
    UISlider* slider = (UISlider*)sender;
    [self.delegate thinBranchWidth:slider.value];    
}

-(void)mediumBranchWidth:(UIControl*)sender {
    UISlider* slider = (UISlider*)sender;
    [self.delegate mediumBranchWidth:slider.value];
}

-(void)largeBranchWidth:(UIControl*)sender {
    UISlider* slider = (UISlider*)sender;
    [self.delegate largeBranchWidth:slider.value];
}

-(void)dismissButtonClicked:(UIControl*)sender {
    [self.delegate dismiss];
}

#pragma mark - SCULPTING
-(void)scalingSculptTypeChanged:(UIControl*)sender {
    if (sender == _silhouetteScalingSculpt) {
        [self.delegate scalingSculptTypeChanged:SilhouetteScaling];
    } else if (sender == _circularScalingSculpt) {
        [self.delegate scalingSculptTypeChanged:CircularScaling];
    }
}

-(void)silhouetteScalingBrushSize:(UIControl*)sender {
    UISlider* slider = (UISlider*)sender;
    [self.delegate silhouetteScalingBrushSize:slider.value];
}

@end
