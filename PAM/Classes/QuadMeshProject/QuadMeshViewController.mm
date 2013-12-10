//
//  QuadMeshViewController.m
//  Ossa
//
//  Created by Rinat Abdrashitov on 2013-10-14.
//  Copyright (c) 2013 Rinat Abdrashitov. All rights reserved.
//

#import "QuadMeshViewController.h"
#import "RotationManager.h"
#import "TranslationManager.h"
#import "ZoomManager.h"
//#import "QuadPolygonMesh.h"
#import "PolarAnnularMesh.h"
#import "AGLKContext.h"
#import "Utilities.h"
#import "MeshLoader.h"
#import "PlateStartPoint.h"
#import "UITwoFingerHoldGestureRecognizer.h"
#import "Line.h"
#include <vector>

typedef enum {
    TOUCHED_NONE,
    TOUCHED_MODEL,
    TOUCHED_BACKGROUND
} DrawingState;

@interface QuadMeshViewController () {
    //GL
    GLKMatrix4 viewMatrix;
    GLKMatrix4 projectionMatrix;
    GLKMatrix4 modelViewProjectionMatrix;
    
//    QuadPolygonMesh* _pMesh;
    PolarAnnularMesh* _pMesh;
    BoundingBox _bbox;
    
    //Off Screen framebuffers and renderbuffers
    GLuint _offScreenFrameBuffer;
    GLuint _offScreenColorBuffer;
    GLuint _offScreenDepthBuffer;
    
//    PlateStartPoint* _meshTouchPoint;
//    
//    BOOL isMovingPoint;
//    
//    NSMutableArray* _branchPoints;
    
    //Gestures
    UITwoFingerHoldGestureRecognizer* _twoFingerBending;
    UIPanGestureRecognizer* _oneFingerPanning;
    
    DrawingState _state;
    float _gaussianDepth;
    
    NSArray* _ingnoredViews;
    
    //Branch creation
    Line* _selectionLine;
    Line* _selectionLine2;
    Line* _selectionLine3;
    NSMutableArray* _ribsLines;
    std::vector<GLKVector3> _branchPoint;
}
@end

@implementation QuadMeshViewController

- (id)init
{
    self = [super init];
    if (self) {
        // Custom initialization
        _translationManager = [[TranslationManager alloc] init];
        _rotationManager = [[RotationManager alloc] init];
        _zoomManager = [[ZoomManager alloc] init];
//        isMovingPoint = NO;
//        _branchPoints = [[NSMutableArray alloc] init];
    }
    return self;
}

#pragma mark - View cycle and OpenGL setup

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view.
//    [self loadMeshData];
    [self loadEmptyWorspace];
    
    [self setupGL];
    [self addGestureRecognizersToView:self.view];
    
    _branchWidthSlider.minimumValue = 1.0f;
    _branchWidthSlider.maximumValue = 5.0f;
    [_branchWidthSlider addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
    
    [_transformSwitch addTarget:self action:@selector(transformSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    [_skeletonSwitch addTarget:self action:@selector(skeletonSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    
    _ingnoredViews = @[_transformSwitch, _branchWidthSlider, _skeletonSwitch];
}

- (void)viewDidUnload {
    [super viewDidUnload];
    
    // Stop using the context created in -viewDidLoad
    ((GLKView *)self.view).context = nil;
    [EAGLContext setCurrentContext:nil];
    
    glDeleteRenderbuffers(1, &_offScreenColorBuffer);
    glDeleteRenderbuffers(1, &_offScreenDepthBuffer);
    glDeleteFramebuffers(1, &_offScreenFrameBuffer);
}

-(void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
//    [self setPaused:YES]; //dont draw anything until model is chosen
    [self createOffScreenBuffer];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

-(void) createOffScreenBuffer {
    //Create additional Buffers
    //Create framebuffer and attach color/depth renderbuffers
    glGenFramebuffers(1, &_offScreenFrameBuffer);
    glBindFramebuffer(GL_FRAMEBUFFER, _offScreenFrameBuffer);
    
    glGenRenderbuffers(1, &_offScreenColorBuffer);
    glBindRenderbuffer(GL_RENDERBUFFER, _offScreenColorBuffer);
    glRenderbufferStorage(GL_RENDERBUFFER, GL_RGBA8_OES, _glWidth, _glHeight);
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, _offScreenColorBuffer);
    
    glGenRenderbuffers(1, &_offScreenDepthBuffer);
    glBindRenderbuffer(GL_RENDERBUFFER, _offScreenDepthBuffer);
    glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH_COMPONENT16, _glWidth, _glHeight);
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, _offScreenDepthBuffer);
    
    int status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
    if (status != GL_FRAMEBUFFER_COMPLETE) {
        NSLog(@"[ERROR] Couldnt create offscreen buffer");
    }
    
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
}

-(void)setupGL {
    glEnable(GL_DEPTH_TEST);
    glEnable(GL_CULL_FACE);

}

-(void)addGestureRecognizersToView:(UIView*)view {

    //Pinch To Zoom. Scaling along X,Y,Z
    UIPinchGestureRecognizer* pinchToZoom = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(handlePinchGesture:)];
    [view addGestureRecognizer:pinchToZoom];
    
    //Translation along X, Y
    UIPanGestureRecognizer* twoFingerTranslation = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleTwoFingerPanGesture:)];
    twoFingerTranslation.minimumNumberOfTouches = 2;
    twoFingerTranslation.maximumNumberOfTouches = 2;
    [view addGestureRecognizer:twoFingerTranslation];
    
    //3 finger pan
    UIPanGestureRecognizer* threeFingerPanning = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleThreeFingePanGesture:)];
    threeFingerPanning.minimumNumberOfTouches = 3;
    threeFingerPanning.maximumNumberOfTouches = 3;
    [view addGestureRecognizer:threeFingerPanning];
    
    //4 finger pan
    UIPanGestureRecognizer* fourFingerPanning = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleFourFingePanGesture:)];
    fourFingerPanning.minimumNumberOfTouches = 4;
    fourFingerPanning.maximumNumberOfTouches = 4;
    [view addGestureRecognizer:fourFingerPanning];
    
    //Rotate along Z-axis
    UIRotationGestureRecognizer* rotationInPlaneOfScreen = [[UIRotationGestureRecognizer alloc] initWithTarget:self action:@selector(handleRotationGesture:)];
    [view addGestureRecognizer:rotationInPlaneOfScreen];
    
    //ArcBall Rotation
    _oneFingerPanning = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleOneFingerPanGesture:)];
    _oneFingerPanning.delegate = self;
    _oneFingerPanning.maximumNumberOfTouches = 1;
    [view addGestureRecognizer:_oneFingerPanning];
    
    UITapGestureRecognizer* doubleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleDoubleTapGesture:)];
    doubleTap.numberOfTouchesRequired = 1;
    doubleTap.numberOfTapsRequired = 2;
    [view addGestureRecognizer:doubleTap];
    
//    UITapGestureRecognizer* singleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleSingleTapGesture:)];
//    singleTap.numberOfTapsRequired = 1;
//    singleTap.numberOfTouchesRequired = 1;
//    [singleTap requireGestureRecognizerToFail:doubleTap];
//    [view addGestureRecognizer:singleTap];
    
    _twoFingerBending = [[UITwoFingerHoldGestureRecognizer alloc] initWithTarget:self action:@selector(handleTwoFingerTapGesture:)];
    _twoFingerBending.delegate = self;
//    _twoFingerBending.numberOfTouchesRequired = 2;
//    _twoFingerBending.minimumPressDuration = 0.01;
    _twoFingerBending.enabled = NO;
//    [view addGestureRecognizer:_twoFingerBending];

//    UITapGestureRecognizer* tapWithFourFingers = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleFourFingerTapGesture:)];
//    tapWithTwoFingers.numberOfTouchesRequired = 4;
//    [view addGestureRecognizer:tapWithFourFingers];
}

#pragma mark - UIGestureRecognizerDelegate
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer
{
//    if (gestureRecognizer == _twoFingerBending && otherGestureRecognizer == _oneFingerPanning) {
//        return YES;
//    }
//    if (gestureRecognizer == _oneFingerPanning && otherGestureRecognizer == _twoFingerBending) {
//        return YES;
//    }
    return NO;
}

// called before touchesBegan:withEvent: is called on the gesture recognizer for a new touch. return NO to prevent the gesture recognizer from seeing this touch
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    CGPoint p = [touch locationInView:self.view];

    for(UIView* view in _ingnoredViews) {
        if (CGRectContainsPoint(view.frame, p)) {
            return NO;
        }
    }
    

    if (gestureRecognizer == _twoFingerBending) {
        BOOL flag = [_twoFingerBending needsMoreTouch];
        return flag;
    }
    
    return YES;
}

#pragma mark - Gesture recognizer selectors
-(void)handlePinchGesture:(UIGestureRecognizer*)sender {
    if (!_transformSwitch.isOn) {
        [_zoomManager handlePinchGesture:sender];
    } else {
        return;
        UIPinchGestureRecognizer* pinch = (UIPinchGestureRecognizer*) sender;
//        NSLog(@"Scale %f", pinch.scale);
        if (sender.state == UIGestureRecognizerStateBegan) {
            CGPoint touchPoint1 = [self scaleTouchPoint:[sender locationOfTouch:0 inView:(GLKView*)sender.view]
                                                 inView:(GLKView*)sender.view];
            CGPoint touchPoint2 = [self scaleTouchPoint:[sender locationOfTouch:1 inView:(GLKView*)sender.view]
                                                 inView:(GLKView*)sender.view];
            
            GLKVector3 rayOrigin1, rayDir1, rayOrigin2, rayDir2;
            BOOL result1 = [self rayOrigin:&rayOrigin1 rayDirection:&rayDir1 forTouchPoint:touchPoint1];
            BOOL result2 = [self rayOrigin:&rayOrigin2 rayDirection:&rayDir2 forTouchPoint:touchPoint2];
            if (!result1 || !result2) {
                NSLog(@"[WARNING] Couldn't determine touch area");
                return;
            }
            [_pMesh startScalingRibsWithRayOrigin1:rayOrigin1
                                        rayOrigin2:rayOrigin2
                                     rayDirection1:rayDir1 
                                     rayDirection2:rayDir2
                                             scale:pinch.scale];
            
        } else if (sender.state == UIGestureRecognizerStateChanged) {
            [_pMesh changeScalingRibsWithScaleFactor:pinch.scale];
        } else if (sender.state == UIGestureRecognizerStateEnded) {
            [_pMesh endScalingRibsWithScaleFactor:pinch.scale];
        }
    }
}

-(void)handleOneFingerPanGesture:(UIGestureRecognizer*)sender {
    
    if (!_transformSwitch.isOn) {
        [_rotationManager handlePanGesture:sender withViewMatrix:GLKMatrix4Identity];
    } else {
        
        if (sender.state == UIGestureRecognizerStateBegan)
        {
            CGPoint touchPoint = [self touchPointFromGesture:sender];
            _state = TOUCHED_NONE;
            //Add touch point to a line
            GLKVector3 rayOrigin, rayDirection;
            BOOL result = [self rayOrigin:&rayOrigin rayDirection:&rayDirection forTouchPoint:touchPoint];
            if (!result) {
                NSLog(@"[WARNING] Couldn't determine touch area");
                return;
            }
            rayOrigin = GLKVector3Add(rayOrigin, rayDirection);
            VertexRGBA vertex = {{rayOrigin.x, rayOrigin.y, rayOrigin.z}, {255,0,0,255}};
            NSMutableData* lineData = [[NSMutableData alloc] initWithBytes:&vertex length:sizeof(VertexRGBA)];
            _selectionLine = [[Line alloc] initWithVertexData:lineData];
            
            //Start branch creation
            NSMutableData* pixelData = [self renderToOffscreenDepthBuffer:@[_pMesh]];
            float depth = [self depthForPoint:touchPoint depthBuffer:pixelData];

            GLKVector3 modelCoord;
            if (depth < 0) { //clicked on background
                BOOL result = [self modelCoordinates:&modelCoord forTouchPoint:GLKVector3Make(touchPoint.x, touchPoint.y, 0)];
                if (!result) {
                    NSLog(@"[WARNING] Couldn't determine touch area");
                    return;
                }
                _state = TOUCHED_BACKGROUND;
            } else { //clicked on a model
                _gaussianDepth = depth;
                BOOL result = [self modelCoordinates:&modelCoord forTouchPoint:GLKVector3Make(touchPoint.x, touchPoint.y, _gaussianDepth)];
                if (!result) {
                    NSLog(@"[WARNING] Couldn't determine touch area");
                    return;
                }
                _state = TOUCHED_MODEL;
            }
            
            [_pMesh startCreateBranch:modelCoord];
        }
        else if (sender.state == UIGestureRecognizerStateChanged)
        {
            //Add touch point to a line
            CGPoint touchPoint = [self touchPointFromGesture:sender];
            GLKVector3 rayOrigin, rayDirection;
            BOOL result = [self rayOrigin:&rayOrigin rayDirection:&rayDirection forTouchPoint:touchPoint];
            if (!result) {
                NSLog(@"[WARNING] Couldn't determine touch area");
                return;
            }
            rayOrigin = GLKVector3Add(rayOrigin, rayDirection);

            [_selectionLine addVertex:rayOrigin];
            [_pMesh continueCreateBranch:rayOrigin];
        }
        else if (sender.state == UIGestureRecognizerStateEnded)
        {
            CGPoint touchPoint = [self touchPointFromGesture:sender];
            GLKVector3 modelCoord;
            if (_state == TOUCHED_MODEL) {
                BOOL result = [self modelCoordinates:&modelCoord forTouchPoint:GLKVector3Make(touchPoint.x, touchPoint.y, _gaussianDepth)];
                if (!result) {
                    NSLog(@"[WARNING] Couldn determine touch area");
                    return;
                }
                [_pMesh endCreateBranchBended:modelCoord touchedModel:YES];
            } else if (_state == TOUCHED_BACKGROUND){
                BOOL result = [self modelCoordinates:&modelCoord forTouchPoint:GLKVector3Make(touchPoint.x, touchPoint.y, 0)];
                if (!result) {
                    NSLog(@"[WARNING] Couldn't determine touch area");
                    return;
                }
                [_pMesh endCreateBranchBended:modelCoord touchedModel:NO];
            }
            _state = TOUCHED_NONE;
            _selectionLine = nil;
        }
    }
}

-(void)handleTwoFingerPanGesture:(UIGestureRecognizer*)sender {
    if (!_transformSwitch.isOn) {
        [_translationManager handlePanGesture:sender withViewMatrix:GLKMatrix4Identity];
    } else {   
        if (sender.state == UIGestureRecognizerStateBegan) {
            _selectionLine = nil;
            _selectionLine2 = nil;
            _selectionLine3 = nil;
            if (sender.numberOfTouches != 2) return;
            
            CGPoint touchPoint1 = [self scaleTouchPoint:[sender locationOfTouch:0 inView:(GLKView*)sender.view]
                                                 inView:(GLKView*)sender.view];
            CGPoint touchPoint2 = [self scaleTouchPoint:[sender locationOfTouch:1 inView:(GLKView*)sender.view]
                                                 inView:(GLKView*)sender.view];
            
            GLKVector3 rayOrigin1, rayDir1, rayOrigin2, rayDir2;
            BOOL result1 = [self rayOrigin:&rayOrigin1 rayDirection:&rayDir1 forTouchPoint:touchPoint1];
            BOOL result2 = [self rayOrigin:&rayOrigin2 rayDirection:&rayDir2 forTouchPoint:touchPoint2];
            if (!result1 || !result2) {
                NSLog(@"[WARNING] Couldn't determine touch area");
                return;
            }
            rayOrigin1 = GLKVector3Add(rayOrigin1, rayDir1);
            rayOrigin2 = GLKVector3Add(rayOrigin2, rayDir2);
            VertexRGBA vertex1 = {{rayOrigin1.x, rayOrigin1.y, rayOrigin1.z}, {255,0,0,255}};
            NSMutableData* lineData1 = [[NSMutableData alloc] initWithBytes:&vertex1 length:sizeof(VertexRGBA)];
            _selectionLine = [[Line alloc] initWithVertexData:lineData1];

            VertexRGBA vertex2 = {{rayOrigin2.x, rayOrigin2.y, rayOrigin2.z}, {255,0,0,255}};
            NSMutableData* lineData2 = [[NSMutableData alloc] initWithBytes:&vertex2 length:sizeof(VertexRGBA)];
            _selectionLine2 = [[Line alloc] initWithVertexData:lineData2];
            
            //Check if we touched the middle point
            CGPoint middlePoint = CGPointMake(floor((touchPoint1.x + touchPoint2.x)/2),
                                              floor((touchPoint1.y + touchPoint2.y)/2));
            NSMutableData* pixelData = [self renderToOffscreenDepthBuffer:@[_pMesh]];
            float depth = [self depthForPoint:middlePoint depthBuffer:pixelData];
            GLKVector3 modelCoord1;
            GLKVector3 modelCoord2;
            if (depth < 0) { //clicked on background
                _state = TOUCHED_BACKGROUND;
                [_pMesh startCreateBranchFinger1:rayOrigin1 finger2:rayOrigin2];
            } else { //clicked on a model
                _state = TOUCHED_MODEL;
                _gaussianDepth = depth;
                BOOL result1 = [self modelCoordinates:&modelCoord1 forTouchPoint:GLKVector3Make(touchPoint1.x, touchPoint1.y, _gaussianDepth)];
                BOOL result2 = [self modelCoordinates:&modelCoord2 forTouchPoint:GLKVector3Make(touchPoint2.x, touchPoint2.y, _gaussianDepth)];
                if (!(result1&&result2)) {
                    NSLog(@"[WARNING] Couldn't determine touch area");
                    return;
                }
                [_pMesh startCreateBranchFinger1:modelCoord1 finger2:modelCoord2];
            }
            
        } else if (sender.state == UIGestureRecognizerStateChanged) {
            if (sender.numberOfTouches!=2) {
                return;
            }
            CGPoint touchPoint1 = [self scaleTouchPoint:[sender locationOfTouch:0 inView:(GLKView*)sender.view]
                                                 inView:(GLKView*)sender.view];
            CGPoint touchPoint2 = [self scaleTouchPoint:[sender locationOfTouch:1 inView:(GLKView*)sender.view]
                                                 inView:(GLKView*)sender.view];
            
            GLKVector3 rayOrigin1, rayDir1, rayOrigin2, rayDir2;
            BOOL result1 = [self rayOrigin:&rayOrigin1 rayDirection:&rayDir1 forTouchPoint:touchPoint1];
            BOOL result2 = [self rayOrigin:&rayOrigin2 rayDirection:&rayDir2 forTouchPoint:touchPoint2];
            if (!result1 || !result2) {
                NSLog(@"[WARNING] Couldn't determine touch area");
                return;
            }
            rayOrigin1 = GLKVector3Add(rayOrigin1, rayDir1);
            rayOrigin2 = GLKVector3Add(rayOrigin2, rayDir2);
            [_selectionLine addVertex:rayOrigin1];
            [_selectionLine2 addVertex:rayOrigin2];

            [_pMesh continueCreateBranchFinger1:rayOrigin1 finger2:rayOrigin2];
        } else if (sender.state == UIGestureRecognizerStateEnded) {
            _selectionLine = nil;
            _selectionLine2 = nil;

            std::vector<std::vector<GLKVector3>> allRibs = [_pMesh endCreateBranchTwoFingersWithTouchedModel:(_state == TOUCHED_MODEL)];
            NSLog(@"FUCK");
        }
            
//            _ribsLines = [[NSMutableArray alloc] initWithCapacity:allRibs.size()];
//            for (int i = 0; i <allRibs.size();i++) {
//                std::vector<GLKVector3> rib = allRibs[i];
//                NSMutableData* vData = [[NSMutableData alloc] init];
////                for (GLKVector3 v: rib) {
//                
//                for (int j = 0; j < rib.size(); j++) {
//                    GLKVector3 v = rib[j];
//                    GLubyte b = 0;
//                    GLubyte r = 0;
////                                            GLubyte b = j * (255.0f/rib.size());
//                    if (j%2 ==0) {
//                        r = 255;
//                    } else {
//                        b = 255;
//                    }
//                    VertexRGBA vertex1 = {{v.x, v.y, v.z}, {r,b,0,255}};
//                    [vData appendBytes:&vertex1 length:sizeof(VertexRGBA)];
//                }
//                Line* line = [[Line alloc] initWithVertexData:vData];
//                [_ribsLines addObject:line];
//            }
            
//            _bbox = _pMesh.boundingBox;
//            _translationManager.scaleFactor = _bbox.radius;
        
    }
}

-(void)handleThreeFingePanGesture:(UIGestureRecognizer*)sender {
    [_rotationManager handlePanGesture:sender withViewMatrix:GLKMatrix4Identity];
}

-(void)handleFourFingePanGesture:(UIGestureRecognizer*)sender {
    [_translationManager handlePanGesture:sender withViewMatrix:GLKMatrix4Identity];
}

-(void)handleRotationGesture:(UIGestureRecognizer*)sender {
    [_rotationManager handleRotationGesture:sender withViewMatrix:GLKMatrix4Identity];
}

-(void)handleDoubleTapGesture:(UIGestureRecognizer*)sender {
    if (sender.state == UIGestureRecognizerStateEnded) {
        CGPoint touchPoint = [self touchPointFromGesture:sender];
        GLKVector3 rayOrgin, rayDir;
        BOOL result = [self rayOrigin:&rayOrgin rayDirection:&rayDir forTouchPoint:touchPoint];
        if (!result) {
            NSLog(@"[WARNING] Couldn determine touch area");
            return;
        }
        [_pMesh endSelectFaceWithRay:rayOrgin rayDirection:rayDir];
    }
    
    
//    NSMutableData* pixelData = [self renderToOffscreenDepthBuffer:@[_pMesh]];
//    CGPoint touchPoint = [self scaleTouchPoint:[sender locationInView:sender.view] inView:(GLKView*)sender.view];
//    GLKVector3 startPoint;
//    BOOL result = [self modelCoordinates:&startPoint forTouchPoint:touchPoint depthBuffer:pixelData];
//    
//    if (!result) {
//        NSLog(@"[WARNING] Couldn determine touch area");
//        return;
//    }
   
//    [_pMesh createBranchAtPointAndRefine:startPoint];

    
//    [_pMesh createNewRibAtPoint:startPoint];
//    [_pMesh createNewSpineAtPoint:startPoint];
//    GLKVector3* dataBytes = (GLKVector3*)data.bytes;
//    
//    for(int i = 0; i < data.length/sizeof(GLKVector3); i++) {
//        PlateStartPoint* chosenPoint = [[PlateStartPoint alloc] initWithPoint:dataBytes[i] color:GLKVector3Make(0, 0, 255)];
//        [_branchPoints addObject:chosenPoint];
//    }
    
//    GLKVector3 selectedVertex = [_pMesh closestVertexToMeshPoint:startPoint setAsCurrentID:NO];
//    PlateStartPoint* chosenPoint = [[PlateStartPoint alloc] initWithPoint:selectedVertex color:GLKVector3Make(0, 0, 255)];
//    [_branchPoints addObject:chosenPoint];
}

-(void)handleTwoFingerTapGesture:(UIGestureRecognizer*)sender {
    if(sender.state == UIGestureRecognizerStateBegan) {
        NSLog(@"Two finger bending Started");
        CGPoint touchPoint1 = [self scaleTouchPoint:[sender locationOfTouch:0 inView:(GLKView*)sender.view]
                                             inView:(GLKView*)sender.view];
        CGPoint touchPoint2 = [self scaleTouchPoint:[sender locationOfTouch:1 inView:(GLKView*)sender.view]
                                             inView:(GLKView*)sender.view];

        GLKVector3 rayOrgin, rayDir, touchPointViewCoord;
        BOOL result1 = [self rayOrigin:&rayOrgin rayDirection:&rayDir forTouchPoint:touchPoint1];
        BOOL result2 = [self modelCoordinates:&touchPointViewCoord forTouchPoint:GLKVector3Make(touchPoint2.x, touchPoint2.y, 0)];
        if (!result1 || !result2) {
            NSLog(@"[WARNING] Couldn't determine touch area");
            return;
        }
//        [_pMesh bendBranchBeginWithFirstTouchRayOrigin:rayOrgin rayDirection:rayDir secondTouchPoint:touchPointViewCoord];        
    } else if (sender.state == UIGestureRecognizerStateChanged) {
        NSLog(@"Two finger bending Changed");
    } else if (sender.state == UIGestureRecognizerStateEnded) {
        NSLog(@"Two finger bending Ended ");
        CGPoint touchPoint2 = [self scaleTouchPoint:[sender locationOfTouch:1 inView:(GLKView*)sender.view]
                                             inView:(GLKView*)sender.view];
        GLKVector3 touchPointViewCoord;
        BOOL result = [self modelCoordinates:&touchPointViewCoord forTouchPoint:GLKVector3Make(touchPoint2.x, touchPoint2.y, 0)];
        if (!result) {
            NSLog(@"[WARNING] Couldn't determine touch area");
            return;
        }
//        [_pMesh bendBranchEnd:touchPointViewCoord];
    } else if (sender.state == UIGestureRecognizerStateFailed) {
        NSLog(@"Two finger bending Failed ");
    } else {
        NSLog(@"Two finger bending Uknown State ");
    }
}

-(void)handleFourFingerTapGesture:(UIGestureRecognizer*)sender {
    if (sender.state == UIGestureRecognizerStateEnded) {
        NSLog(@"Ended tap");
        [_transformSwitch setOn:!_transformSwitch.isOn];
    }
}

#pragma mark - Helpers

//Respong to shake events in order to promit undo dialog
- (void)motionEnded:(UIEventSubtype)motion withEvent:(UIEvent *)event
{
    if (motion == UIEventSubtypeMotionShake)
    {
        // your code
        [[[UIAlertView alloc] initWithTitle:@"Undo?" message:nil delegate:self cancelButtonTitle:nil otherButtonTitles:@"Yes", @"No", nil] show];
    }
}

//Get scaled and flipped touch coordinates from touch gesture
-(CGPoint)touchPointFromGesture:(UIGestureRecognizer*)sender {
    return [self scaleTouchPoint:[sender locationInView:sender.view] inView:(GLKView*)sender.view];
}

//Get scaled and flipped touch coordinates from touch point coordinates in a view
-(CGPoint)scaleTouchPoint:(CGPoint)touchPoint inView:(GLKView*)view {
    CGFloat scale = view.contentScaleFactor;
    
    touchPoint.x = floorf(touchPoint.x * scale);
    touchPoint.y = floorf(touchPoint.y * scale);
    touchPoint.y = floorf(view.drawableHeight - touchPoint.y);
    
    return touchPoint;
}

#pragma mark - OpenGL Drawing

//Update camera matrix transformations
- (void)update {
    //Projection
    const GLfloat aspectRatio = (GLfloat)_glHeight / (GLfloat)_glWidth;
    
    projectionMatrix = GLKMatrix4MakeOrtho(-_bbox.width/2, _bbox.width/2,
                                           -(_bbox.height/2)*aspectRatio, (_bbox.height/2)*aspectRatio,
                                           -4*_bbox.depth, 4*_bbox.depth);
    
    viewMatrix = GLKMatrix4Identity;
    
    //View Translation
    viewMatrix = GLKMatrix4Multiply(viewMatrix, _translationManager.translationMatrix);
    
    //View Scaling
    viewMatrix = GLKMatrix4Multiply(viewMatrix, _zoomManager.scaleMatrix);
 
    //View Rotation
    viewMatrix = GLKMatrix4Multiply(viewMatrix, _rotationManager.rotationMatrix);
    
    modelViewProjectionMatrix = GLKMatrix4Multiply(projectionMatrix, viewMatrix);
}

//Draw callback
- (void)glkView:(GLKView *)view drawInRect:(CGRect)rect {

    [(AGLKContext *)view.context clear:GL_COLOR_BUFFER_BIT|GL_DEPTH_BUFFER_BIT];

    glLineWidth(1.0f);
    _pMesh.viewMatrix = viewMatrix;
    _pMesh.projectionMatrix = projectionMatrix;
    [_pMesh draw];
    
    glLineWidth(3.0f);
    _selectionLine.viewMatrix = viewMatrix;
    _selectionLine.projectionMatrix = projectionMatrix;
    [_selectionLine draw];
    
    _selectionLine2.viewMatrix = viewMatrix;
    _selectionLine2.projectionMatrix = projectionMatrix;
    [_selectionLine2 draw];
    
    _selectionLine3.viewMatrix = viewMatrix;
    _selectionLine3.projectionMatrix = projectionMatrix;
    [_selectionLine3 draw];
    
    for (Line* line in _ribsLines) {
        line.viewMatrix = viewMatrix;
        line.projectionMatrix = projectionMatrix;
        [line draw];
    }
    
//    _meshTouchPoint.viewMatrix = viewMatrix;
//    _meshTouchPoint.projectionMatrix = projectionMatrix;
//    [_meshTouchPoint draw];
//    
//    for (Mesh* bPoint in _branchPoints) {
//        bPoint.viewMatrix = viewMatrix;
//        bPoint.projectionMatrix = projectionMatrix;
//        [bPoint draw];
//    }
}

//Load initial mesh from OBJ file
-(void)loadMeshData {
    
    [self setPaused:YES]; //pause rendering
    
    //Reset all transformations. Remove all previous screws and plates
    [self resetClicked:nil];
    [self showLoadingIndicator];
    
    if (_pMesh == nil) {
        _pMesh = [[PolarAnnularMesh alloc] init];
    }

    //Load obj file
    NSString* objPath = [[NSBundle mainBundle] pathForResource:@"sphere_mid_res" ofType:@"obj"];
    [_pMesh setMeshFromObjFile:objPath];
    _bbox = _pMesh.boundingBox;
    _translationManager.scaleFactor = _bbox.radius;
    
    //Read vertex data from the file
    [self hideLoadingIndicator];
    [self setPaused:NO];
}

-(void)loadEmptyWorspace {
    [self setPaused:YES]; //pause rendering
    
    //Reset all transformations. Remove all previous screws and plates
    [self resetClicked:nil];
    [self showLoadingIndicator];
    
    if (_pMesh == nil) {
        _pMesh = [[PolarAnnularMesh alloc] init];
    }
    
    //Load obj file
    _bbox.minBound = GLKVector3Make(-1, -1, -1);
    _bbox.maxBound = GLKVector3Make(1, 1, 1);
    _bbox.center =  GLKVector3MultiplyScalar(GLKVector3Add(_bbox.minBound, _bbox.maxBound), 0.5f);
    
    GLKVector3 mid = GLKVector3MultiplyScalar(GLKVector3Subtract(_bbox.maxBound, _bbox.minBound), 0.5f);
    _bbox.radius = GLKVector3Length(mid);
    _bbox.width = fabsf(_bbox.maxBound.x - _bbox.minBound.x);
    _bbox.height = fabsf(_bbox.maxBound.y - _bbox.minBound.y);
    _bbox.depth = fabsf(_bbox.maxBound.z - _bbox.minBound.z);
    
    _translationManager.scaleFactor = _bbox.radius;
    
    //Read vertex data from the file
    [self hideLoadingIndicator];
    [self setPaused:NO];

}

#pragma mark - OffScreen depth buffer 

//Renders current scene(only bones) with all transformations applied into offscreen depth buffer.
//Depth buffer is imitated as a color buffer for glFragCoord.z value written into glFragColor in the fragment shader.
//Returns data from glReadPixel, i.e. depth values for each pixel
-(NSMutableData*)renderToOffscreenDepthBuffer:(NSArray*)meshesArray {
    //Preserve previous GL state
    GLboolean wasBlendEnabled;
    glGetBooleanv(GL_BLEND, &wasBlendEnabled);
    
    GLboolean wasDepthEnabled;
    glGetBooleanv(GL_DEPTH_TEST, &wasDepthEnabled);
    
    GLfloat clearColor[4];
    glGetFloatv(GL_COLOR_CLEAR_VALUE, clearColor);
    
    glBindFramebuffer(GL_FRAMEBUFFER, _offScreenFrameBuffer);
    
    NSMutableData* pixelData = nil;
    
    glViewport(0, 0, _glWidth, _glHeight);
    glEnable(GL_DEPTH_TEST);
    glDisable(GL_BLEND);
    glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT|GL_DEPTH_BUFFER_BIT);
    
    for (Mesh* mesh in meshesArray) {
        mesh.viewMatrix = viewMatrix;
        mesh.projectionMatrix = projectionMatrix;
        [mesh drawToDepthBuffer];
    }
    
    pixelData = [[NSMutableData alloc] initWithLength:4*_glWidth*_glHeight];
    glReadPixels(0, 0, _glWidth, _glHeight, GL_RGBA, GL_UNSIGNED_BYTE, pixelData.mutableBytes);
    
    //Restore previous GL state
    if (wasBlendEnabled) {
        glEnable(GL_BLEND);
    } else {
        glDisable(GL_BLEND);
    }
    
    if (wasDepthEnabled) {
        glEnable(GL_DEPTH_TEST);
    } else {
        glDisable(GL_DEPTH_TEST);
    }
    
    glClearColor(clearColor[0], clearColor[1], clearColor[2], clearColor[3]);
    
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    
    return pixelData;
}

//Return depth value written int colorbuffer using shaders
//-1 is returned if depth is unkown (clicked on background pixels)
-(float)depthForPoint:(CGPoint)touchPoint depthBuffer:(NSData*)pixelData {
    GLubyte* pixels = (GLubyte*)pixelData.bytes;
    
    int index = touchPoint.y * _glWidth + touchPoint.x;
    int index4 = index * 4;
    
    GLubyte r = pixels[index4];
    GLubyte g = pixels[index4 + 1];
    GLubyte b = pixels[index4 + 2];
    GLubyte a = pixels[index4 + 3];
    
    if (r != 0 && g != 0 && b != 0) {
        GLKVector4 color = GLKVector4Make(r, g, b, a);
        float depth = GLKVector4DotProduct(color, GLKVector4Make(1.0, 1/255.0, 1/65025.0, 1/16581375.0));
        depth = depth/255.0;
        return depth;
    }
    
    return -1;
}

//Convert window coordinates into world coordinates.
//Touchpoint is in the form of (touchx, touchy, depth)
-(BOOL)modelCoordinates:(GLKVector3*)objectCoord3 forTouchPoint:(GLKVector3)touchPoint {
    GLKVector4 viewport = GLKVector4Make(0, 0, _glWidth, _glHeight);
    int result = [Utilities gluUnProjectf:touchPoint :modelViewProjectionMatrix :viewport :objectCoord3];
    if (result != 0) {
        return YES;
    }
    return NO;
}

//Convert window coordinates into world coordinates.
//Touchpoint is in the form of (touchx, touchy). Depth is extracted from given depth buffer information
-(BOOL)modelCoordinates:(GLKVector3*)objectCoord3 forTouchPoint:(CGPoint)touchPoint depthBuffer:(NSData*)pixelData {
    float depth = [self depthForPoint:touchPoint depthBuffer:pixelData];
    
    if (depth >= 0) {
        GLKVector3 windowCoord3 = GLKVector3Make(touchPoint.x, touchPoint.y, depth);
        GLKVector4 viewport = GLKVector4Make(0, 0, _glWidth, _glHeight);
        int result = [Utilities gluUnProjectf:windowCoord3 :modelViewProjectionMatrix :viewport :objectCoord3];
        if (result != 0) {
            return YES;
        }
    }
    return NO;
}

//Create a ray from a given touch point in a direction orthogonal to the surface of the screen
-(BOOL)rayOrigin:(GLKVector3*)rayOrigin rayDirection:(GLKVector3*)rayDirection forTouchPoint:(CGPoint)touchPoint {
    GLKVector3 rayStartWindow = GLKVector3Make(touchPoint.x, touchPoint.y, 0);
    GLKVector4 viewport = GLKVector4Make(0, 0, _glWidth, _glHeight);

    int result = [Utilities gluUnProjectf:rayStartWindow :modelViewProjectionMatrix :viewport :rayOrigin];
    
    bool isInv;
    *rayDirection = GLKMatrix4MultiplyVector3(GLKMatrix4Invert(viewMatrix, &isInv), GLKVector3Make(0, 0, -1));
    if (result != 0 && isInv) {
        return YES;
    }
    return NO;
}

//Create a ray from a given touch gesture in a direction orthogonal to the surface of the screen
-(BOOL)rayOrigin:(GLKVector3*)rayOrigin rayDirection:(GLKVector3*)rayDirection forGesture:(UIGestureRecognizer*)gesture {
    CGPoint touchPoint = [self touchPointFromGesture:gesture];
    return [self rayOrigin:rayOrigin rayDirection:rayDirection forTouchPoint:touchPoint];
}

#pragma mark - Navigation Bar Button Selector

- (void)resetClicked:(id)sender {
    [_rotationManager reset];
    viewMatrix = GLKMatrix4Identity;
    _translationManager.translationMatrix = GLKMatrix4Identity;
    _zoomManager.scaleMatrix = GLKMatrix4Identity;
//    [_branchPoints removeAllObjects];
}

-(void)sliderChanged:(id)sender{

    float newStep = roundf(_branchWidthSlider.value);
    
    // Convert "steps" back to the context of the sliders values.
    _branchWidthSlider.value = newStep;
    _pMesh.branchWidth = newStep;

}

-(void)transformSwitchChanged:(id)sender {
    UISwitch* s = (UISwitch*)sender;
    _twoFingerBending.enabled = s.isOn;
}

-(void)skeletonSwitchChanged:(id)sender {
//    [_pMesh showSkeleton:_skeletonSwitch.isOn];
}


#pragma mark - UIAlertView Delegate 
- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if ([alertView.title isEqualToString:@"Undo?"]) {
        if (buttonIndex == 0) {
            [_pMesh undo];
        }
        [alertView dismissWithClickedButtonIndex:buttonIndex animated:YES];
    }
}

@end
