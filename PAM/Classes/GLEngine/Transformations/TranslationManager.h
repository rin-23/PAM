//
//  PanManager.h
//  Pelvic-iOS
//
//  Created by Rinat Abdrashitov on 2012-10-25.
//
//

#import <Foundation/Foundation.h>
#import <GLKit/GLKit.h>

@interface TranslationManager : NSObject

@property (nonatomic, assign) GLKMatrix4 translationMatrix;
@property (nonatomic, assign) float scaleFactor;

- (void)handlePanGesture:(UIGestureRecognizer *)sender withViewMatrix:(GLKMatrix4)viewMatrix;
- (void)reset;
@end
