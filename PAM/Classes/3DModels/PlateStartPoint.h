//
//  PlateStartPoint.h
//  Ossa
//
//  Created by Rinat Abdrashitov on 2013-08-22.
//  Copyright (c) 2013 Rinat Abdrashitov. All rights reserved.
//

#import "Mesh.h"

@interface PlateStartPoint : Mesh

-(id)initWithPoint:(GLKVector3)point color:(GLKVector3)color;
@property(nonatomic, assign) GLKVector3 point;
@end
