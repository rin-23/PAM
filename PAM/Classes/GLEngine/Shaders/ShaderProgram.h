//
//  Shader.h
//  Ossa
//
//  Created by Rinat Abdrashitov on 2013-07-31.
//  Copyright (c) 2013 Rinat Abdrashitov. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface ShaderProgram : NSObject

-(id)initWithVertexShader:(NSString *)vertexShaderPath fragmentShader:(NSString *)fragmentShaderPath;

-(GLint)attributeLocation:(const GLchar *)name;
-(GLint)uniformLocation:(const GLchar *)name;

//Cache shaders into static dictionary. Default is YES.
//Hash key is vShaderName-fShaderName
+(void)setCacheShaderPrograms:(BOOL)chouldCache;

@property (nonatomic, assign) GLuint program;

@end
