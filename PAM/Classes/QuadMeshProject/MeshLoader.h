//
//  MeshLoader.h
//  Ossa
//
//  Created by Rinat Abdrashitov on 2013-10-14.
//  Copyright (c) 2013 Rinat Abdrashitov. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface MeshLoader : NSObject

+(NSMutableData *)meshData;
+(NSMutableData *)meshDataFromObjFile:(NSString *)objFilePath;

@end
