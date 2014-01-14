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
-(void)transformModeIsOn:(BOOL)isOn;
-(void)clearModel;
-(void)resetTransformations;
-(void)dismiss;
@end

@interface SettingsViewController : UIViewController {
    UISwitch* _transformSwitch;
    UISwitch* _skeletonSwitch;
    UIButton* _clearModelBtn;
    UIButton* _resetBtn;
    UIButton* _showRibJunctionsBtn;
    UIButton* _loadArmadillo;
}

@property (nonatomic, weak) id<SettingsViewControllerDelegate> delegate;

@end
