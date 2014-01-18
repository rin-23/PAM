//
//  SettingsViewController.h
//  PAM
//
//  Created by Rinat Abdrashitov on 12/25/2013.
//  Copyright (c) 2013 Rinat Abdrashitov. All rights reserved.
//

#import <UIKit/UIKit.h>

@protocol SettingsViewControllerDelegate <NSObject>
-(void)showRibJunctions;
-(void)showSkeleton:(BOOL)show;
//-(void)transformModeIsOn:(BOOL)isOn;
-(void)clearModel;
-(void)resetTransformations;
-(void)loadArmadillo;
-(void)dismiss;
-(void)subdivide;
-(void)emailObj;

//BRANCH CREATION
-(void)poleSmoothing:(BOOL)poleSmoothing;
-(void)spineSmoothing:(BOOL)spineSmoothing;
-(void)smoothingBrushSize:(float)brushSize;
-(void)thinBranchWidth:(float)width;
-(void)baseSmoothingIterations:(float)iter;
@end

@interface SettingsViewController : UIViewController <UIScrollViewDelegate> {
    UIScrollView* contentView;
    UISwitch* _transformSwitch;
    UISwitch* _skeletonSwitch;
    UIButton* _clearModelBtn;
    UIButton* _resetBtn;
    UIButton* _showRibJunctionsBtn;
    UIButton* _loadArmadillo;
    UIButton* _subdivide;
    UIButton* _saveObjFile;
    
    //Branch creation
    UISwitch* _spineSmoothing;
    UISwitch* _poleSmoothing;
    UISlider* _smoothingSlider;
    UISlider* _baseSmoothingIterationsSlider;
    UISlider* _thinBranchWidth;
    UISlider* _mediumBranchWidthSize;
    UISlider* _thickBranchWidthSize;
    
}

@property (nonatomic, weak) id<SettingsViewControllerDelegate> delegate;

@end
