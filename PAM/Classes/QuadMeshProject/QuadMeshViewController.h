//
//  QuadMeshViewController.h
//  Ossa
//
//  Created by Rinat Abdrashitov on 2013-10-14.
//  Copyright (c) 2013 Rinat Abdrashitov. All rights reserved.
//

#import "BaseQuadMeshViewController.h"

@class RotationManager, ZoomManager, TranslationManager;

@interface QuadMeshViewController : BaseQuadMeshViewController <UIAlertViewDelegate>

@property (nonatomic) RotationManager* rotationManager;
@property (nonatomic) ZoomManager* zoomManager;
@property (nonatomic) TranslationManager* translationManager;

@end
