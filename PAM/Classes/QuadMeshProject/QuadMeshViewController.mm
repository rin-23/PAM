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
#import "AGLKContext.h"
#import "Utilities.h"
#import "MeshLoader.h"
#import "PlateStartPoint.h"
#import "Line.h"
#include <vector>
#import "SettingsManager.h"
#import "PAMPanGestureRecognizer.h"
#import "PAMPinchGestureRecognizer.h"
#import "PAMTapGestureRecongnizer.h"

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

    PolarAnnularMesh* _pMesh;
    BoundingBox _bbox;
    
    //Off Screen framebuffers and renderbuffers
    GLuint _offScreenFrameBuffer;
    GLuint _offScreenColorBuffer;
    GLuint _offScreenDepthBuffer;

//    NSMutableArray* _branchPoints;
    
    DrawingState _drawingState;
    float _gaussianDepth;
    float _touchSize;
    float _speedSum;
    int _touchCount;
    
    //Branch creation
    Line* _selectionLine;
    Line* _selectionLine2;
    Line* _selectionLine3;
    NSMutableArray* _ribsLines;
    std::vector<GLKVector3> _branchPoint;

    
//    UISwipeGestureRecognizer* _twoFingerSwipeUpGesture;
//    UISwipeGestureRecognizer* _twoFingerSwipeDownGesture;
    UIPanGestureRecognizer* _twoFingerTranslation;
    
    
    //Auto backup
    NSTimer* _autoSave;
    UIAlertView* _restorSessionAlert;
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
//        _branchPoints = [[NSMutableArray alloc] init];
        
//        _modelingState = MODELING_NONE;
    }
    return self;
}

#pragma mark - View cycle and OpenGL setup

-(void)dealloc {
    [self stopBackupTimer];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view.
//    [self loadMeshData];
    [self loadEmptyWorspace];
    
    [self setupGL];
    [self addGestureRecognizersToView:self.view];
    
    if ([self backupExist]) {
        _restorSessionAlert = [[UIAlertView alloc] initWithTitle:nil message:@"Restore last session" delegate:self cancelButtonTitle:nil otherButtonTitles:@"Yes", @"No", nil];
        [_restorSessionAlert show];
    } else {
        [self startBackupTimer];
    }
    
    
    UIButton* undoBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    [undoBtn setFrame:CGRectMake(0, self.view.frame.size.height-100, 100, 100)];
    [undoBtn addTarget:self action:@selector(undoButtonClicked:) forControlEvents:UIControlEventTouchUpInside];
    undoBtn.autoresizingMask = UIViewAutoresizingFlexibleTopMargin;
    [self.view addSubview:undoBtn];

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
    [_pMesh clearMemmory];
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
    //Two finger tap to switch between modeling and transformation
    UITapGestureRecognizer* twoFingerTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTwoFingeTapGesture:)];
    twoFingerTap.numberOfTapsRequired = 1;
    twoFingerTap.numberOfTouchesRequired = 2;
    [view addGestureRecognizer:twoFingerTap];
    
    //Pinch To Zoom. Scaling along X,Y,Z
    PAMPinchGestureRecognizer* pinchToZoom = [[PAMPinchGestureRecognizer alloc] initWithTarget:self action:@selector(handlePinchGesture:)];
    [view addGestureRecognizer:pinchToZoom];
    
//    _twoFingerSwipeUpGesture = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(handleTwoFingerSwipeUpGesture:)];
//    _twoFingerSwipeUpGesture.delegate = self;
//    _twoFingerSwipeUpGesture.enabled = NO;
//    _twoFingerSwipeUpGesture.direction = UISwipeGestureRecognizerDirectionUp;
//    _twoFingerSwipeUpGesture.numberOfTouchesRequired = 2;
//    [view addGestureRecognizer:_twoFingerSwipeUpGesture];

//    _twoFingerSwipeDownGesture = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(handleTwoFingerSwipeDownGesture:)];
//    _twoFingerSwipeDownGesture.delegate = self;
//    _twoFingerSwipeDownGesture.enabled = NO;
//    _twoFingerSwipeDownGesture.direction = UISwipeGestureRecognizerDirectionDown;
//    _twoFingerSwipeDownGesture.numberOfTouchesRequired = 2;
//    [view addGestureRecognizer:_twoFingerSwipeDownGesture];

    UIPanGestureRecognizer* threeFingerTranslation = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleThreeFingerTranslation:)];
    threeFingerTranslation.minimumNumberOfTouches = 3;
    [view addGestureRecognizer:threeFingerTranslation];
    
    //Translation along X, Y
    _twoFingerTranslation = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleTwoFingerPanGesture:)];
    _twoFingerTranslation.minimumNumberOfTouches = 2;
    _twoFingerTranslation.maximumNumberOfTouches = 2;
//    _twoFingerTranslation.delegate = self;
//    [_twoFingerTranslation requireGestureRecognizerToFail:_twoFingerSwipeDownGesture];
//    [_twoFingerTranslation requireGestureRecognizerToFail:_twoFingerSwipeUpGesture];
    [view addGestureRecognizer:_twoFingerTranslation];

    
    //Rotate along Z-axis
    UIRotationGestureRecognizer* rotationInPlaneOfScreen = [[UIRotationGestureRecognizer alloc] initWithTarget:self action:@selector(handleRotationGesture:)];
    [view addGestureRecognizer:rotationInPlaneOfScreen];
    
    
    //ArcBall Rotation
    PAMPanGestureRecognizer* oneFingerPanning = [[PAMPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleOneFingerPanGesture:)];
    oneFingerPanning.maximumNumberOfTouches = 1;
    [view addGestureRecognizer:oneFingerPanning];
    
    //Double tap to smooth
    PAMTapGestureRecongnizer* doubleTap = [[PAMTapGestureRecongnizer alloc] initWithTarget:self action:@selector(handleDoubleTapGesture:)];
    doubleTap.numberOfTouchesRequired = 1;
    doubleTap.numberOfTapsRequired = 2;
    [view addGestureRecognizer:doubleTap];
    
    UITapGestureRecognizer* singleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleSingleTapGesture:)];
    singleTap.numberOfTouchesRequired = 1;
    singleTap.numberOfTapsRequired = 1;
    [singleTap requireGestureRecognizerToFail:doubleTap];
    [view addGestureRecognizer:singleTap];
    
    UILongPressGestureRecognizer* longPress = [[ UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPressGesture:)];
    longPress.numberOfTouchesRequired = 1;
    [view addGestureRecognizer:longPress];
}

-(void)undoButtonClicked:(UIButton*)btn {
    [_pMesh undo];
}

#pragma mark - UIGestureRecognizerDelegate

-(void)startBackupTimer {
    _autoSave = [NSTimer timerWithTimeInterval:30
                                        target:self
                                      selector:@selector(backupSession)
                                      userInfo:nil
                                       repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:_autoSave forMode:NSDefaultRunLoopMode];
}

-(void)stopBackupTimer {
    [_autoSave invalidate];
}
//
//-(BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer
//{
//    if ([SettingsManager sharedInstance].transform) {
//        return NO;
//    }
//    if (gestureRecognizer == _twoFingerSwipeUpGesture &&
//        otherGestureRecognizer == _twoFingerTranslation)
//    {
//        return YES;
//    } else if (gestureRecognizer == _twoFingerSwipeDownGesture &&
//               otherGestureRecognizer == _twoFingerTranslation)
//    {
//        return YES;
//    }
//    return NO;
//}

#pragma mark - Save/Restore modeling session
-(void)backupSession {
    if (_pMesh == nil || ![_pMesh isLoaded]) {
        return;
    }
    
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0ul);
    dispatch_async(queue, ^{
        NSArray* paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        NSString* cacheFolder = [NSString stringWithFormat:@"%@/Backups", [paths objectAtIndex:0]];
        if (![[NSFileManager defaultManager] fileExistsAtPath:cacheFolder]) {
            [[NSFileManager defaultManager] createDirectoryAtPath:cacheFolder withIntermediateDirectories:YES attributes:nil error:nil];
        }
//        NSString *timeStampValue = [NSString stringWithFormat:@"%ld", (long)[[NSDate date] timeIntervalSince1970]];
        NSString* filePath = [NSString stringWithFormat:@"%@/backup.obj", cacheFolder];
        
        BOOL saved = [_pMesh backup:filePath];
        dispatch_sync(dispatch_get_main_queue(), ^{
            if (saved) {
                NSLog(@"[INFO]Session saved");
            } else {
                NSLog(@"[Info]Failed to save session");
//                [[[UIAlertView alloc] initWithTitle:@"Error" message:@"Coudln't backup session" delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
            }
        });
    });
}

-(void)restoreLastSession {
    NSArray* paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString* cacheFolder = [NSString stringWithFormat:@"%@/Backups", [paths objectAtIndex:0]];
    if ([[NSFileManager defaultManager] fileExistsAtPath:cacheFolder]) {

        [self setPaused:YES]; //pause rendering
        
        NSFileManager* fileManager = [NSFileManager defaultManager];
        NSArray* allBackups = [fileManager contentsOfDirectoryAtPath:cacheFolder error:nil];
        NSArray* sortedBackups = [allBackups sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
        NSString* lastPath = [NSString stringWithFormat:@"%@/%@",cacheFolder, [sortedBackups lastObject]];
        
        //Reset all transformations. Remove all previous screws and plates
        [_pMesh clear];
        _pMesh = nil;
        [self resetTransformations];
        
        if (_pMesh == nil) {
            _pMesh = [[PolarAnnularMesh alloc] init];
            _pMesh.delegate = self;
        }
        
        //Load obj file
        [_pMesh restoreMeshFromObjFile:lastPath];
        _bbox = _pMesh.boundingBox;
        _translationManager.scaleFactor = _bbox.radius;

        [self setPaused:NO];
    }
}

-(BOOL)backupExist {
    NSArray* paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString* cacheFolder = [NSString stringWithFormat:@"%@/Backups", [paths objectAtIndex:0]];
    if (![[NSFileManager defaultManager] fileExistsAtPath:cacheFolder]) {
        return NO;
    } else {
        return YES;
    }
}


#pragma mark - Gesture recognizer selectors
-(void)handleLongPressGesture:(UIGestureRecognizer*)sender {
    if (![_pMesh isLoaded]) {
        return;
    }
    if ([SettingsManager sharedInstance].showSkeleton) {
        return;
    }
    
    if (sender.state == UIGestureRecognizerStateBegan) {
        if (![SettingsManager sharedInstance].transform) {
            if (_pMesh.modState == MODIFICATION_PIN_POINT_SET) {
                [_pMesh deleteCurrentPinPoint];
            } else if (_pMesh.modState == MODIFICATION_NONE) {
                GLKVector3 modelCoord;
                if (![self modelCoordinates:&modelCoord forGesture:sender]) {
                    NSLog(@"[WARNING] Touched background");
                    return;
                }
                [_pMesh createPinPoint:modelCoord];
//                _twoFingerSwipeDownGesture.enabled = YES;
//                _twoFingerSwipeUpGesture.enabled = YES;
            }
        }
    }
}

-(void)handleSingleTapGesture:(UIGestureRecognizer*)sender {
    if (_pMesh.modState == MODIFICATION_BRANCH_DETACHED ||
        _pMesh.modState == MODIFICATION_BRANCH_DETACHED_AN_MOVED)
    {
        GLKVector3 modelCoord;
        if (![self modelCoordinates:&modelCoord forGesture:sender]) {
            NSLog(@"[WARNING] Touched background");
            return;
        }
        [_pMesh moveDetachedBranchToPoint:modelCoord];
    } else if (_pMesh.modState == MODIFICATION_BRANCH_COPIED_BRANCH_FOR_CLONING) {
        GLKVector3 modelCoord;
        if (![self modelCoordinates:&modelCoord forGesture:sender]) {
            NSLog(@"[WARNING] Touched background");
            return;
        }

        [_pMesh cloneBranchTo:modelCoord];
    }
}

-(void)handleDoubleTapGesture:(UIGestureRecognizer*)sender {
//    @synchronized(self) {
        GLKVector3 modelCoord;
        if (![self modelCoordinates:&modelCoord forGesture:sender]) {
            NSLog(@"[WARNING] Touched background");
            return;
        }
        int iter = [SettingsManager sharedInstance].tapSmoothing;
        float wrong_radius = 3*[self touchSizeForGesture:sender];
        float radius = 3*[self touchSizeForFingerSize:8.0f];

        [_pMesh smoothAtPoint:modelCoord radius:radius iterations:iter];
//    }
}

-(void)handleTwoFingeTapGesture:(UIGestureRecognizer*)sender {
    [SettingsManager sharedInstance].transform = ![SettingsManager sharedInstance].transform;
    if ([SettingsManager sharedInstance].transform) {
//        _twoFingerSwipeUpGesture.enabled = NO;
//        _twoFingerSwipeDownGesture.enabled = NO;
    } else{
        BOOL enabled = NO;
        if (_pMesh.modState == MODIFICATION_BRANCH_COPIED_AND_MOVED_THE_CLONE ||
            _pMesh.modState == MODIFICATION_BRANCH_COPIED_BRANCH_FOR_CLONING ||
            _pMesh.modState == MODIFICATION_PIN_POINT_SET)
        {
            enabled = YES;
        }
//        _twoFingerSwipeUpGesture.enabled = enabled;
//        _twoFingerSwipeDownGesture.enabled = enabled;
    }
    
    _transformModeLabel.alpha = 1.0f;
    if ([SettingsManager sharedInstance].transform) {
        _transformModeLabel.text = @"Transform";
    } else {
        _transformModeLabel.text = @"Model";
    }
}

-(void)handlePinchGesture:(UIGestureRecognizer*)sender {
    if (![_pMesh isLoaded]) {
        return;
    }
    
    if ([SettingsManager sharedInstance].transform) {
        [_zoomManager handlePinchGesture:sender];
    } else  if ([SettingsManager sharedInstance].showSkeleton) {
        return;
    } else {
        /*MODELING*/
        if (_pMesh.modState == MODIFICATION_PIN_POINT_SET ||
            _pMesh.modState == MODIFICATION_BRANCH_SCALING)
        {
            PAMPinchGestureRecognizer* pinch = (PAMPinchGestureRecognizer*) sender;
            if (sender.state == UIGestureRecognizerStateBegan) {
                GLKVector3 modelCoord;
                if (![self modelCoordinates:&modelCoord forGesture:pinch]) {
                    NSLog(@"[WARNING] Touched background");
                    return;
                }
                [_pMesh startScalingBranchTreeWithTouchPoint:modelCoord scale:pinch.scale];
            } else if (sender.state == UIGestureRecognizerStateChanged) {
                [_pMesh continueScalingBranchTreeWithScale:pinch.scale];
            } else if (sender.state == UIGestureRecognizerStateEnded) {
                [_pMesh endScalingBranchTreeWithScale:pinch.scale];
            }
        }
        else if (_pMesh.modState == MODIFICATION_BRANCH_COPIED_AND_MOVED_THE_CLONE ||
                 _pMesh.modState == MODIFICATION_BRANCH_CLONE_SCALING )
        {
            PAMPinchGestureRecognizer* pinch = (PAMPinchGestureRecognizer*) sender;
            if (sender.state == UIGestureRecognizerStateBegan) {
                [_pMesh startScaleClonedBranch:pinch.scale];
            } else if (sender.state == UIGestureRecognizerStateChanged) {
                [_pMesh continueScaleClonedBranch:pinch.scale];
            } else if (sender.state == UIGestureRecognizerStateEnded) {
                [_pMesh endScaleClonedBranch:pinch.scale];
            }
        }
        
        else if (_pMesh.modState == MODIFICATION_NONE ||
                 _pMesh.modState == MODIFICATION_SCULPTING_SCALING ||
                 _pMesh.modState == MODIFICATION_SCULPTING_ANISOTROPIC_SCALING ||
                 _pMesh.modState == MODIFICATION_SCULPTING_BUMP_CREATION)
        {
            //sculpting
            PAMPinchGestureRecognizer* pinch = (PAMPinchGestureRecognizer*) sender;
//            NSLog(@"Scale %f", pinch.velocity);
            if (sender.state == UIGestureRecognizerStateBegan) {
                CGPoint touchPoint1 = [self scaleTouchPoint:[sender locationOfTouch:0 inView:(GLKView*)sender.view]
                                                     inView:(GLKView*)sender.view];
                CGPoint touchPoint2 = [self scaleTouchPoint:[sender locationOfTouch:1 inView:(GLKView*)sender.view]
                                                     inView:(GLKView*)sender.view];
                
                NSMutableData* pixelData = [self renderToOffscreenDepthBuffer:@[_pMesh]];
                float depth1 = [self depthForPoint:touchPoint1 depthBuffer:pixelData];
                float depth2 = [self depthForPoint:touchPoint2 depthBuffer:pixelData];
                
                float touchSize = 2 * [self touchSizeForGesture:sender];
                
                if (depth1 < 0 || depth2 < 0) {
                    //on of the fingers touched background. Start scaling.
                    if (depth1 < 0 && depth2 < 0) {
                        GLKVector3 rayOrigin, rayDir;
                        if (![self rayOrigin:&rayOrigin rayDirection:&rayDir forTouchPoint:touchPoint1]) {
                            NSLog(@"[WARNING] Couldn't determine touch area");
                            return;
                        }
                        [_pMesh startScalingSingleRibWithTouchPoint:rayOrigin secondPointOnTheModel:NO scale:pinch.scale velocity:pinch.velocity touchSize:touchSize];
                    } else if (depth1 < 0) {
                        GLKVector3 rayOrigin, rayDir;
                        if (![self rayOrigin:&rayOrigin rayDirection:&rayDir forTouchPoint:touchPoint1]) {
                            NSLog(@"[WARNING] Couldn't determine touch area");
                            return;
                        }
                        [_pMesh startScalingSingleRibWithTouchPoint:rayOrigin secondPointOnTheModel:YES scale:pinch.scale velocity:pinch.velocity touchSize:touchSize];
                    } else {
                        GLKVector3 rayOrigin, rayDir;
                        if (![self rayOrigin:&rayOrigin rayDirection:&rayDir forTouchPoint:touchPoint2]) {
                            NSLog(@"[WARNING] Couldn't determine touch area");
                            return;
                        }
                        [_pMesh startScalingSingleRibWithTouchPoint:rayOrigin secondPointOnTheModel:YES scale:pinch.scale velocity:pinch.velocity touchSize:touchSize];
                    }
                } else if (depth1 >= 0 && depth2 >= 0) {
                    //touched the model so start bump creation
                    GLKVector3 modelCoord1, modelCoord2;
                    GLKVector3 worldTouchPoint1 = GLKVector3Make(touchPoint1.x, touchPoint1.y, depth1);
                    GLKVector3 worldTouchPoint2 = GLKVector3Make(touchPoint2.x, touchPoint2.y, depth2);
                    [self modelCoordinates:&modelCoord1 forTouchPoint:worldTouchPoint1];
                    [self modelCoordinates:&modelCoord2 forTouchPoint:worldTouchPoint2];
                    float distanceBetweenFingers = GLKVector3Length(GLKVector3Subtract(modelCoord2, modelCoord1));
                    
                    CGPoint touchPoint = CGPointMake(floorf(0.5*(touchPoint1.x +touchPoint2.x)),
                                                     floorf(0.5*(touchPoint1.y +touchPoint2.y)));
                    float depth = [self depthForPoint:touchPoint depthBuffer:pixelData];
                    GLKVector3 modelCoord;
                    [self modelCoordinates:&modelCoord forTouchPoint:GLKVector3Make(touchPoint.x, touchPoint.y, depth)];
                    float brushSize = distanceBetweenFingers/2;
                    [_pMesh startBumpCreationAtPoint:modelCoord
                                           brushSize:brushSize
                                          brushDepth:pinch.scale];
                }
            } else if (sender.state == UIGestureRecognizerStateChanged) {
                if (_pMesh.modState == MODIFICATION_SCULPTING_BUMP_CREATION) {
                    [_pMesh continueBumpCreationWithBrushDepth:pinch.scale];
                } else {
                    [_pMesh changeScalingSingleRibWithScaleFactor:pinch.scale];
                }
            } else if (sender.state == UIGestureRecognizerStateEnded) {
                if (_pMesh.modState == MODIFICATION_SCULPTING_BUMP_CREATION) {
                    [_pMesh endBumpCreation];
                } else {
                    [_pMesh endScalingSingleRibWithScaleFactor:pinch.scale];
                }
            }
        }
        
    }
}

-(void)handleOneFingerPanGesture:(UIGestureRecognizer*)sender {
    
    if (![_pMesh isLoaded]) {
        NSLog(@"[WARNING] Manifold is not loaded yet");
        return;
    }

    if ([SettingsManager sharedInstance].transform) {
        [_rotationManager handlePanGesture:sender withViewMatrix:GLKMatrix4Identity];
    } else if ([SettingsManager sharedInstance].showSkeleton){
        return;
    } else {
        if (_pMesh.modState == MODIFICATION_PIN_POINT_SET) {
            if (sender.state == UIGestureRecognizerStateEnded) {
                GLKVector3 rayOrigin, rayDirection;
                if (![self rayOrigin:&rayOrigin rayDirection:&rayDirection forGesture:sender]) {
                    NSLog(@"[WARNING] Couldn't determine touch area");
                    return;
                }
                
                UIPanGestureRecognizer* pan = (UIPanGestureRecognizer*)sender;
                CGPoint t = [pan translationInView:self.view];
                float swipeLength = sqrtf(powf(t.x, 2) + pow(t.y, 2));
                NSLog(@"Swipe length:%f", swipeLength);
                if (swipeLength < 160) {
                    [_pMesh detachBranch:rayOrigin];
                } else {
                    [_pMesh deleteBranch:rayOrigin];
                }
            }
        } else if (_pMesh.modState == MODIFICATION_BRANCH_DETACHED) {
            if (sender.state == UIGestureRecognizerStateEnded) {
                [_pMesh attachDetachedBranch];
            }
        } else if (_pMesh.modState == MODIFICATION_BRANCH_DETACHED_AN_MOVED) {
            if (sender.state == UIGestureRecognizerStateEnded) {
                [_pMesh attachDetachedBranch];
            }
        } else if (_pMesh.modState == MODIFICATION_NONE) {
            PAMPanGestureRecognizer* oneFingerPAMGesture = (PAMPanGestureRecognizer*)sender;
            if (sender.state == UIGestureRecognizerStateBegan)
            {
                _touchSize = [oneFingerPAMGesture touchSize];
                _speedSum = 0;
                _touchCount = 0;
                
                _drawingState = TOUCHED_NONE;
                CGPoint touchPoint = [self touchPointFromGesture:sender];
                
                //Add touch point to a line
                GLKVector3 rayOrigin, rayDirection;
                BOOL result = [self rayOrigin:&rayOrigin rayDirection:&rayDirection forTouchPoint:touchPoint];
                if (!result) {
                    NSLog(@"[WARNING] Touched background");
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
                        NSLog(@"[WARNING] Touched background");
                        return;
                    }
                    _drawingState = TOUCHED_BACKGROUND;
                } else { //clicked on a model
                    _gaussianDepth = depth;
                    BOOL result = [self modelCoordinates:&modelCoord forTouchPoint:GLKVector3Make(touchPoint.x, touchPoint.y, _gaussianDepth)];
                    if (!result) {
                        NSLog(@"[WARNING] Touched background");
                        return;
                    }
                    _drawingState = TOUCHED_MODEL;
                }
                
                [_pMesh startCreateBranch:rayOrigin closestPoint:modelCoord];
            }
            else if (sender.state == UIGestureRecognizerStateChanged)
            {
                CGPoint velocity = [oneFingerPAMGesture velocityInView:self.view];
                float cur_speed = sqrtf(powf(velocity.x, 2) + powf(velocity.y, 2));
                _speedSum += cur_speed;
                _touchCount += 1;
                
                //Add touch point to a line
                CGPoint touchPoint = [self touchPointFromGesture:sender];
                GLKVector3 rayOrigin, rayDirection;
                BOOL result = [self rayOrigin:&rayOrigin rayDirection:&rayDirection forTouchPoint:touchPoint];
                if (!result) {
                    NSLog(@"[WARNING] Touched background");
                    return;
                }
                rayOrigin = GLKVector3Add(rayOrigin, rayDirection);

                [_selectionLine addVertex:rayOrigin];
                [_pMesh continueCreateBranch:rayOrigin];
            }
            else if (sender.state == UIGestureRecognizerStateEnded)
            {
                CGPoint velocity = [oneFingerPAMGesture velocityInView:self.view];
                float cur_speed = sqrtf(powf(velocity.x, 2) + powf(velocity.y, 2));

                GLKVector3 modelCoord;
                GLKVector3 rayOrigin, rayDirection;
                
                BOOL touchedModelStart = _drawingState == TOUCHED_MODEL;
                BOOL touchedModelEnd = [self modelCoordinates:&modelCoord forGesture:sender];
//                BOOL shouldStick = cur_speed < 10;
                BOOL shouldStick = NO;
                [self rayOrigin:&rayOrigin rayDirection:&rayDirection forGesture:sender];
                rayOrigin = GLKVector3Add(rayOrigin, rayDirection);
                
                GLKVector3 lastPoint;
                if (shouldStick) {
                    lastPoint = touchedModelEnd ? modelCoord : rayOrigin;
                } else {
                    lastPoint = rayOrigin;
                }
                
                float averageSpeed = _speedSum/_touchCount;
                NSLog(@"Average Speed: %f", averageSpeed);
//                std::vector<std::vector<GLKVector3>> allRibs;
                
                 [_pMesh endCreateBranchBended:lastPoint
                                      touchedModelStart:touchedModelStart
                                        touchedModelEnd:touchedModelEnd
                                            shouldStick:shouldStick
                                              touchSize:_touchSize
                                      averageTouchSpeed:averageSpeed];

                _drawingState = TOUCHED_NONE;
                _selectionLine = nil;
                
//                _ribsLines = [[NSMutableArray alloc] initWithCapacity:allRibs.size()];
//                for (int i = 0; i <allRibs.size();i++) {
//                    std::vector<GLKVector3> rib = allRibs[i];
//                    NSMutableData* vData = [[NSMutableData alloc] init];
//    //                for (GLKVector3 v: rib) {
//
//                    for (int j = 0; j < rib.size(); j++) {
//                        GLKVector3 v = rib[j];
//                        GLubyte b = 0;
//                        GLubyte r = 0;
//    //                                            GLubyte b = j * (255.0f/rib.size());
//                        if (j%2 ==0) {
//                            r = 255;
//                        } else {
//                            b = 255;
//                        }
//                        VertexRGBA vertex1 = {{v.x, v.y, v.z}, {r,b,0,255}};
//                        [vData appendBytes:&vertex1 length:sizeof(VertexRGBA)];
//                    }
//                    Line* line = [[Line alloc] initWithVertexData:vData];
//                    [_ribsLines addObject:line];
//                }

    //            _bbox = _pMesh.boundingBox;
    //            _translationManager.scaleFactor = _bbox.radius;
            }
        }
    }
}

-(void)handleTwoFingerPanGesture:(UIGestureRecognizer*)sender {
    
    if ([SettingsManager sharedInstance].transform) {
        [_translationManager handlePanGesture:sender withViewMatrix:GLKMatrix4Identity];
    } else if ([SettingsManager sharedInstance].showSkeleton){
        return;
    } else {
        if (![_pMesh isLoaded]) {
            if (_pMesh.modState == MODIFICATION_NONE) {
                if ([_pMesh isLoaded]) {
                    return;
                }
                
                if (sender.state == UIGestureRecognizerStateBegan) {
                    _selectionLine  = nil;
                    _selectionLine2 = nil;
                    _selectionLine3 = nil;
                    if (sender.numberOfTouches != 2) {
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
                    VertexRGBA vertex1 = {{rayOrigin1.x, rayOrigin1.y, rayOrigin1.z}, {255,0,0,255}};
                    NSMutableData* lineData1 = [[NSMutableData alloc] initWithBytes:&vertex1 length:sizeof(VertexRGBA)];
                    _selectionLine = [[Line alloc] initWithVertexData:lineData1];
                    
                    VertexRGBA vertex2 = {{rayOrigin2.x, rayOrigin2.y, rayOrigin2.z}, {255,0,0,255}};
                    NSMutableData* lineData2 = [[NSMutableData alloc] initWithBytes:&vertex2 length:sizeof(VertexRGBA)];
                    _selectionLine2 = [[Line alloc] initWithVertexData:lineData2];
                    
                    [_pMesh startCreateBodyFinger1:rayOrigin1 finger2:rayOrigin2];
                    
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
                    [_pMesh continueCreateBodyFinger1:rayOrigin1 finger2:rayOrigin2];
                } else if (sender.state == UIGestureRecognizerStateEnded) {
                    _selectionLine = nil;
                    _selectionLine2 = nil;
                    //                std::vector<std::vector<GLKVector3>> allRibs =
                    [_pMesh endCreateBody];
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
        } else {
            UIPanGestureRecognizer* pan = (UIPanGestureRecognizer*)sender;
            CGPoint point = [pan translationInView:pan.view];
            GLfloat ratio = pan.view.frame.size.height/pan.view.frame.size.width;
            GLfloat x_ndc = point.x/pan.view.frame.size.width;
            GLfloat y_ndc = -1*(point.y/pan.view.frame.size.height)*ratio;
            
            GLKVector3 translation = GLKMatrix4MultiplyVector3(GLKMatrix4Invert(viewMatrix, NULL),
                                                               GLKVector3Make(_translationManager.scaleFactor*x_ndc, _translationManager.scaleFactor*y_ndc, 0));
            if (_pMesh.modState == MODIFICATION_PIN_POINT_SET ||
                _pMesh.modState == MODIFICATION_BRANCH_TRANSLATION )
            {
                
                if (sender.state == UIGestureRecognizerStateBegan) {
                    GLKVector3 modelCoord;
                    if (![self modelCoordinates:&modelCoord forGesture:sender]) {
                        NSLog(@"[WARNING] Touched background");
                        return;
                    }
                    [_pMesh startTranslatingBranchTreeWithTouchPoint:modelCoord translation:translation];
                } else if (sender.state == UIGestureRecognizerStateChanged) {
                    [_pMesh continueTranslatingBranchTree:translation];
                } else if (sender.state == UIGestureRecognizerStateEnded) {
                    [_pMesh endTranslatingBranchTree:translation];
                }
            } else if (_pMesh.modState == MODIFICATION_NONE ||
                       _pMesh.modState == MODIFICATION_BRANCH_POSE_TRANSLATE)
            {
//                if (sender.state == UIGestureRecognizerStateBegan) {
//                    GLKVector3 modelCoord;
//                    if (![self modelCoordinates:&modelCoord forGesture:sender]) {
//                        NSLog(@"[WARNING] Touched background");
//                        return;
//                    }
//                    [_pMesh statePosingTranslateWithTouchPoint:modelCoord translation:translation];
//                } else if (sender.state == UIGestureRecognizerStateChanged) {
//                    [_pMesh continuePosingTranslate:translation];
//                } else if (sender.state == UIGestureRecognizerStateEnded) {
//                    [_pMesh endPosingTranslate:translation];
//                }
            }
        }
    }
}

-(void)handleThreeFingerTranslation:(UIGestureRecognizer*)sender {
    if (sender.state == UIGestureRecognizerStateEnded) {
        if (_pMesh.modState == MODIFICATION_PIN_POINT_SET) {
            GLKVector3 rayOrigin, rayDirection;
            if (![self rayOrigin:&rayOrigin rayDirection:&rayDirection forGesture:sender]) {
                NSLog(@"[WARNING] Couldn't determine touch area");
                return;
            }
            [_pMesh copyBranchToBuffer:rayOrigin];
        } else if (_pMesh.modState == MODIFICATION_BRANCH_COPIED_AND_MOVED_THE_CLONE) {
            [_pMesh attachClonedBranch];
        } else if (_pMesh.modState == MODIFICATION_BRANCH_COPIED_BRANCH_FOR_CLONING) {
            [_pMesh dismissCopiedBranch];
        }
    }
}

-(void)handleRotationGesture:(UIGestureRecognizer*)sender {
    if ([SettingsManager sharedInstance].transform) {
        [_rotationManager handleRotationGesture:sender withViewMatrix:GLKMatrix4Identity];
    } else if ([SettingsManager sharedInstance].showSkeleton) {
        return;
    } else {
          UIRotationGestureRecognizer* rotGesture =( UIRotationGestureRecognizer*) sender;
        if (_pMesh.modState == MODIFICATION_PIN_POINT_SET ||
            _pMesh.modState == MODIFICATION_BRANCH_ROTATION)
        {
            if (sender.state == UIGestureRecognizerStateBegan) {
                GLKVector3 modelCoord;
                if (![self modelCoordinates:&modelCoord forGesture:sender]) {
                    NSLog(@"[WARNING] Touched background");
                    return;
                }
                [_pMesh startBendingWithTouhcPoint:modelCoord angle:rotGesture.rotation];
            } else if (sender.state == UIGestureRecognizerStateChanged) {
                [_pMesh continueBendingWithWithAngle:rotGesture.rotation];
            } else if (sender.state == UIGestureRecognizerStateEnded) {
                [_pMesh endBendingWithAngle:rotGesture.rotation];
            }
        } else if (_pMesh.modState == MODIFICATION_BRANCH_DETACHED ||
                   _pMesh.modState == MODIFICATION_BRANCH_DETACHED_AN_MOVED ||
                   _pMesh.modState == MODIFICATION_BRANCH_DETACHED_ROTATE)
        {
            if (sender.state == UIGestureRecognizerStateBegan) {
                [_pMesh startRotateDetachedBranch:rotGesture.rotation];
            } else if (sender.state == UIGestureRecognizerStateChanged) {
                [_pMesh continueRotateDetachedBranch:rotGesture.rotation];
            } else if (sender.state == UIGestureRecognizerStateEnded) {
                [_pMesh endRotateDetachedBranch:rotGesture.rotation];
            }
        } else if (_pMesh.modState == MODIFICATION_BRANCH_COPIED_AND_MOVED_THE_CLONE ||
                   _pMesh.modState == MODIFICATION_BRANCH_CLONE_ROTATION )
        {
            if (sender.state == UIGestureRecognizerStateBegan) {
                [_pMesh startRotateClonedBranch:rotGesture.rotation];
            } else if (sender.state == UIGestureRecognizerStateChanged) {
                [_pMesh continueRotateClonedBranch:rotGesture.rotation];
            } else if (sender.state == UIGestureRecognizerStateEnded) {
                [_pMesh endRotateClonedBranch:rotGesture.rotation];
            }
        } else if (_pMesh.modState == MODIFICATION_NONE ||
                   _pMesh.modState == MODIFICATION_BRANCH_POSE_ROTATE)
        {
            if (sender.state == UIGestureRecognizerStateBegan) {
                GLKVector3 modelCoord;
                if (![self modelCoordinates:&modelCoord forGesture:sender]) {
                    NSLog(@"[WARNING] Touched background");
                    return;
                }
                [_pMesh statePosingRotateWithTouchPoint:modelCoord angle:rotGesture.rotation];
            } else if (sender.state == UIGestureRecognizerStateChanged) {
                [_pMesh continuePosingRotate:rotGesture.rotation];
            } else if (sender.state == UIGestureRecognizerStateEnded) {
                [_pMesh endPosingRotate:rotGesture.rotation];
            }
        }
        
    }
}

//-(void)handleTwoFingerSwipeUpGesture:(UIGestureRecognizer*)sender {
//    if (_pMesh.modState == MODIFICATION_PIN_POINT_SET) {
//        GLKVector3 modelCoord;
//        if (![self modelCoordinates:&modelCoord forGesture:sender]) {
//            NSLog(@"[WARNING] Touched background");
//            return;
//        }
//        [_pMesh copyBranchToBuffer:modelCoord];
//    }
//}

-(void)handleTwoFingerSwipeDownGesture:(UIGestureRecognizer*)sender {
    if (_pMesh.modState == MODIFICATION_BRANCH_COPIED_AND_MOVED_THE_CLONE) {
        [_pMesh attachClonedBranch];
    } else if (_pMesh.modState == MODIFICATION_BRANCH_COPIED_BRANCH_FOR_CLONING) {
        [_pMesh dismissCopiedBranch];
    }
}

#pragma mark - Helpers

//Respong to shake events in order to promit undo dialog
- (void)motionEnded:(UIEventSubtype)motion withEvent:(UIEvent *)event {
    if (motion == UIEventSubtypeMotionShake) {
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
    

    projectionMatrix = GLKMatrix4MakeOrtho(-_bbox.radius, _bbox.radius,
                                           -_bbox.radius*aspectRatio, _bbox.radius*aspectRatio,
                                           -4*_bbox.radius, 4*_bbox.radius);
    
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
    
    glLineWidth(2.0f);
    _selectionLine.viewMatrix = viewMatrix;
    _selectionLine.projectionMatrix = projectionMatrix;
    [_selectionLine draw];
    
    _selectionLine2.viewMatrix = viewMatrix;
    _selectionLine2.projectionMatrix = projectionMatrix;
    [_selectionLine2 draw];
    
    _selectionLine3.viewMatrix = viewMatrix;
    _selectionLine3.projectionMatrix = projectionMatrix;
    [_selectionLine3 draw];
    
//    for (Line* line in _ribsLines) {
//        line.viewMatrix = viewMatrix;
//        line.projectionMatrix = projectionMatrix;
//        [line draw];
//    }
    
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
    [_pMesh clear];
    _pMesh = nil;
    [self resetTransformations];
    [self showLoadingIndicator];
    
    if (_pMesh == nil) {
        _pMesh = [[PolarAnnularMesh alloc] init];
        _pMesh.delegate = self;
    }

    //Load obj file
    NSString* objPath = [[NSBundle mainBundle] pathForResource:@"HAND PAM 15" ofType:@"obj"];
//    NSString* objPath = [[NSBundle mainBundle] pathForResource:@"man-polar150-simpl420-refit34_0.5-subd-refit10_0.5" ofType:@"obj"];
    [_pMesh setMeshFromObjFile:objPath];

    _bbox = _pMesh.boundingBox;
    _translationManager.scaleFactor = _bbox.radius;
    
    [SettingsManager sharedInstance].smoothingBrushSize = 0.3;
    [SettingsManager sharedInstance].baseSmoothingIterations = 2;
    [SettingsManager sharedInstance].spineSmoothing = NO;
    
    [self hideLoadingIndicator];
    [self setPaused:NO];
}

-(void)loadEmptyWorspace {
    [self setPaused:YES]; //pause rendering
    
    //Reset all transformations. Remove all previous screws and plates
    [self resetTransformations];
    [self showLoadingIndicator];
    
    if (_pMesh == nil) {
        _pMesh = [[PolarAnnularMesh alloc] init];
        _pMesh.delegate = self;
    }
       
    _bbox = _pMesh.boundingBox;
    _translationManager.scaleFactor = _bbox.radius;
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

-(BOOL)modelCoordinates:(GLKVector3*)modelCoord forGesture:(UIGestureRecognizer*)sender {
    CGPoint touchPoint = [self touchPointFromGesture:sender];
    NSMutableData* pixelData = [self renderToOffscreenDepthBuffer:@[_pMesh]];
    BOOL result  = [self modelCoordinates:modelCoord forTouchPoint:touchPoint depthBuffer:pixelData];
    return result;
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

-(float)touchSizeForGesture:(UIGestureRecognizer*)gesture {
    if ([gesture respondsToSelector:@selector(touchSize)]) {
        float touchSizeMM = [[gesture valueForKey:@"touchSize"] floatValue];
        float touchSize = [self touchSizeForFingerSize:touchSizeMM];
        return touchSize;
    }
    return 0;
}

-(float)touchSizeForFingerSize:(float)touchSizeMM {
    const float mmToPx = 2048.0f/240.0f; //2048 px for 240 mm for retina display
    float touchSizePx = touchSizeMM * mmToPx;
    
    GLKVector3 modelCoord, modelCoord2, rayDir, rayDir2;
    [self rayOrigin:&modelCoord rayDirection:&rayDir forTouchPoint:CGPointMake(touchSizePx, 0)];
    [self rayOrigin:&modelCoord2 rayDirection:&rayDir2 forTouchPoint:CGPointMake(0, 0)];
    
    float touchSize = GLKVector3Distance(modelCoord, modelCoord2);
    return touchSize;
}

#pragma mark - UIAlertView Delegate
- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if ([alertView.title isEqualToString:@"Undo?"]) {
        if (buttonIndex == 0) {
            [_pMesh undo];
        }
    }
    
    if (_restorSessionAlert == alertView) {
        if (buttonIndex == 0) {
            [self restoreLastSession];
        }
        [self startBackupTimer];
    }
    [alertView dismissWithClickedButtonIndex:buttonIndex animated:YES];
}

- (void)mailComposeController:(MFMailComposeViewController*)controller
          didFinishWithResult:(MFMailComposeResult)result error:(NSError*)error
{
	[self dismissViewControllerAnimated:YES completion:NULL];
}

#pragma mark - SettingsViewControllerDelegate

-(void)emailObj {
    if ([MFMailComposeViewController canSendMail]) {
        NSArray* paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        NSString* cacheFolder = [NSString stringWithFormat:@"%@/ObjFiles", [paths objectAtIndex:0]];
        if (![[NSFileManager defaultManager] fileExistsAtPath:cacheFolder]) {
            [[NSFileManager defaultManager] createDirectoryAtPath:cacheFolder withIntermediateDirectories:YES attributes:nil error:nil];
        }
        NSString *timeStampValue = [NSString stringWithFormat:@"%ld", (long)[[NSDate date] timeIntervalSince1970]];
        NSString* filePath = [NSString stringWithFormat:@"%@/obj_%@.obj", cacheFolder, timeStampValue];
        
        BOOL saved = [_pMesh saveAsObj:filePath];
        if (saved) {
            MFMailComposeViewController *picker = [[MFMailComposeViewController alloc] init];
            picker.mailComposeDelegate = self;
            [picker setSubject:@"PAM obj"];
            [picker setToRecipients:@[@"rindopuz23@gmail.com"]];
            // Attach an image to the email
            NSData *myData = [NSData dataWithContentsOfFile:filePath];
            if (myData != nil) {

                [picker addAttachmentData:myData mimeType:@"text/plain" fileName:@"PAM.obj"];
                [self presentViewController:picker animated:YES completion:nil];
            } else {
                [[[UIAlertView alloc] initWithTitle:@"Error" message:@"Could not retrieve obj file" delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
            }
        }
    } else {
        [[[UIAlertView alloc] initWithTitle:@"Error" message:@"No email account is setup" delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
    }
}


-(void)subdivide {
    [_pMesh subdivide];
}

-(void)loadArmadillo {
    [self loadMeshData];
}

-(void)showRibJunctions {
    [_pMesh showRibJunctions];
}

-(void)globalSmoothing {
    [_pMesh globalSmoothing];
}

-(void)showSkeleton:(BOOL)show {
    //overwrite
    [SettingsManager sharedInstance].showSkeleton = show;
    [_pMesh showSkeleton:show];
}
//
//-(void)transformModeIsOn:(BOOL)isOn {
//    //overwrite
//    if (isOn) {
//        _twoFingerSwipeUpGesture.enabled = NO;
//        _twoFingerSwipeDownGesture.enabled = NO;
//    } else{
//        BOOL enabled = NO;
//        if (_pMesh.modState == MODIFICATION_BRANCH_COPIED_AND_MOVED_THE_CLONE ||
//            _pMesh.modState == MODIFICATION_BRANCH_COPIED_BRANCH_FOR_CLONING ||
//            _pMesh.modState == MODIFICATION_PIN_POINT_SET)
//        {
//            enabled = YES;
//        }
//        _twoFingerSwipeUpGesture.enabled = enabled;
//        _twoFingerSwipeDownGesture.enabled = enabled;
//
//    }
//    [SettingsManager sharedInstance].transform = isOn;
//}

-(void)clearModel {
    //overwrite
    [_pMesh clear];
}

-(void)smoothingBrushSize:(float)brushSize {
    [SettingsManager sharedInstance].smoothingBrushSize = brushSize;
}

-(void) baseSmoothingIterations:(float)iter {
    [SettingsManager sharedInstance].baseSmoothingIterations = iter;
}

-(void)thinBranchWidth:(float)width {
    [SettingsManager sharedInstance].thinBranchWidth = width;
}

-(void)mediumBranchWidth:(float)width {
    [SettingsManager sharedInstance].mediumBranchWidth = width;
}

-(void)largeBranchWidth:(float)width {
    [SettingsManager sharedInstance].largeBranchWidth = width;
}

-(void)tapSmoothing:(float)power {
    [SettingsManager sharedInstance].tapSmoothing = power;
}


-(void)spineSmoothing:(BOOL)spineSmoothin {
    [SettingsManager sharedInstance].spineSmoothing = spineSmoothin;
}

-(void)poleSmoothing:(BOOL)poleSmoothing {
    [SettingsManager sharedInstance].poleSmoothing = poleSmoothing;
}

-(void)resetTransformations {
    //overwrite
    [_rotationManager reset];
    [_translationManager reset];
    viewMatrix = GLKMatrix4Identity;
    _zoomManager.scaleMatrix = GLKMatrix4Identity;
    //    [_branchPoints removeAllObjects];
}


//SCULPTING
-(void)scalingSculptTypeChanged:(ScultpScalingType)type {
    [SettingsManager sharedInstance].sculptScalingType = type;
}

-(void)silhouetteScalingBrushSize:(float)width {
    [SettingsManager sharedInstance].silhouetteScalingBrushSize = width;
}

#pragma mark - PolarAnnularMeshDelegate
-(void)modStateChangedTo:(CurrentModification)modState {
    if (modState == MODIFICATION_NONE) {        
//        _twoFingerSwipeUpGesture.enabled = NO;
//        _twoFingerSwipeDownGesture.enabled = NO;
    }
}

-(void)displayHint:(NSString *)hintString {
    _hintLabel.text = hintString;
    _hintLabel.alpha = 1.0f;
    [UIView animateWithDuration:1.0f delay:2.5 options:UIViewAnimationOptionTransitionNone animations:^{
        _hintLabel.alpha =0.0f;
    } completion:^(BOOL finished) {
        
    }];
}


@end
