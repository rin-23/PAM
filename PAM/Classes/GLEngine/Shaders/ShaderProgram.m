//
//  Shader.m
//  Ossa
//
//  Created by Rinat Abdrashitov on 2013-07-31.
//  Copyright (c) 2013 Rinat Abdrashitov. All rights reserved.
//

#import "ShaderProgram.h"
#import <OpenGLES/ES2/gl.h>
#import <OpenGLES/ES2/glext.h>

static NSMutableDictionary* cachedShaders = nil;
static NSMutableDictionary* cachedShadersCount;

static BOOL shouldCacheShaders = YES;

@interface ShaderProgram()
@property (nonatomic) NSString* vertexShaderName;
@property (nonatomic) NSString* fragmentShaderName;
@property (nonatomic) NSString* shaderProgramHashKey;
@end

@implementation ShaderProgram

-(id)initWithVertexShader:(NSString*)vertexShaderPath fragmentShader:(NSString*)fragmentShaderPath {
    self = [super init];
    if (self) {
        _vertexShaderName = [vertexShaderPath lastPathComponent];
        _fragmentShaderName = [fragmentShaderPath lastPathComponent];
        _shaderProgramHashKey = [self dictionaryKeyForVertexShader:_vertexShaderName
                                                    fragmentShader:_fragmentShaderName];
        
        //Retrieve shader from cache is exists
        if (shouldCacheShaders && cachedShaders != nil) {
            NSNumber* shaderNum = [cachedShaders objectForKey:_shaderProgramHashKey];
            if (shaderNum != nil) {
                _program = [shaderNum unsignedIntValue];
                
                //increment the count
                NSNumber* shaderCount = [cachedShadersCount objectForKey:_shaderProgramHashKey];
                [cachedShadersCount setValue:@([shaderCount intValue] + 1) forKey:_shaderProgramHashKey];
                return self;
            }
        }
        
        GLuint vertShader, fragShader;

        // Create shader program.
        GLuint program = glCreateProgram();
        
        // Create and compile vertex shader.
        if (![self compileShader:&vertShader type:GL_VERTEX_SHADER file:vertexShaderPath]) {
            NSLog(@"Failed to compile vertex shader");
            return nil;
        }
        
        // Create and compile fragment shader.
        if (![self compileShader:&fragShader type:GL_FRAGMENT_SHADER file:fragmentShaderPath]) {
            NSLog(@"Failed to compile fragment shader");
            return nil;
        }
        
        // Attach vertex shader to program.
        glAttachShader(program, vertShader);
        
        // Attach fragment shader to program.
        glAttachShader(program, fragShader);
        
        // Link program.
        if (![self linkProgram:program]) {
            NSLog(@"Failed to link program: %d", program);
            if (vertShader) {
                glDeleteShader(vertShader);
                vertShader = 0;
            }
            if (fragShader) {
                glDeleteShader(fragShader);
                fragShader = 0;
            }
            if (program) {
                glDeleteProgram(program);
                program = 0;
            }
            return nil;
        }
        
        // Release vertex and fragment shaders.
        if (vertShader) {
            glDetachShader(program, vertShader);
            glDeleteShader(vertShader);
        }
        if (fragShader) {
            glDetachShader(program, fragShader);
            glDeleteShader(fragShader);
        }
        
        
        _program = program;
        
        //Cache the sahder program
        if (shouldCacheShaders) {
            if (cachedShaders == nil) {
                cachedShaders = [[NSMutableDictionary alloc] init];
                cachedShadersCount = [[NSMutableDictionary alloc] init];
            }
            [cachedShaders setValue:@(program) forKey:_shaderProgramHashKey];
            [cachedShadersCount setValue:@1 forKey:_shaderProgramHashKey];
        }
    }
    return self;
}


-(void)dealloc {
    if (cachedShaders != nil) {
        //decrement the count or delete if count is zero
        NSNumber* countNum = [cachedShadersCount objectForKey:_shaderProgramHashKey];
        int countInt = [countNum intValue] - 1;
        if (countInt < 1) {
            glDeleteProgram(_program);
            [cachedShaders removeObjectForKey:_shaderProgramHashKey];
            [cachedShadersCount removeObjectForKey:_shaderProgramHashKey];
        } else {
            [cachedShadersCount setValue:@(countInt) forKey:_shaderProgramHashKey];
        }
    }
}

-(GLint)attributeLocation:(const GLchar*) name {
   return glGetAttribLocation(self.program, name);
}

-(GLint)uniformLocation:(const GLchar*) name {
   return glGetUniformLocation(self.program, name);
}


#pragma mark - SHADER COMPILATION

- (BOOL)compileShader:(GLuint *)shader type:(GLenum)type file:(NSString *)file
{
    GLint status;
    const GLchar *source;
    
    source = (GLchar *)[[NSString stringWithContentsOfFile:file encoding:NSUTF8StringEncoding error:nil] UTF8String];
    if (!source) {
        NSLog(@"Failed to load vertex shader");
        return NO;
    }
    
    *shader = glCreateShader(type);
    glShaderSource(*shader, 1, &source, NULL);
    glCompileShader(*shader);
    
#if defined(DEBUG)
    GLint logLength;
    glGetShaderiv(*shader, GL_INFO_LOG_LENGTH, &logLength);
    if (logLength > 0) {
        GLchar *log = (GLchar *)malloc(logLength);
        glGetShaderInfoLog(*shader, logLength, &logLength, log);
        NSLog(@"Shader compile log:\n%s", log);
        free(log);
    }
#endif
    
    glGetShaderiv(*shader, GL_COMPILE_STATUS, &status);
    if (status == 0) {
        glDeleteShader(*shader);
        return NO;
    }
    
    return YES;
}

- (BOOL)linkProgram:(GLuint)prog
{
    GLint status;
    glLinkProgram(prog);
    
#if defined(DEBUG)
    GLint logLength;
    glGetProgramiv(prog, GL_INFO_LOG_LENGTH, &logLength);
    if (logLength > 0) {
        GLchar *log = (GLchar *)malloc(logLength);
        glGetProgramInfoLog(prog, logLength, &logLength, log);
        NSLog(@"Program link log:\n%s", log);
        free(log);
    }
#endif
    
    glGetProgramiv(prog, GL_LINK_STATUS, &status);
    if (status == 0) {
        return NO;
    }
    
    return YES;
}

- (BOOL)validateProgram:(GLuint)prog
{
    GLint logLength, status;
    
    glValidateProgram(prog);
    glGetProgramiv(prog, GL_INFO_LOG_LENGTH, &logLength);
    if (logLength > 0) {
        GLchar *log = (GLchar *)malloc(logLength);
        glGetProgramInfoLog(prog, logLength, &logLength, log);
        NSLog(@"Program validate log:\n%s", log);
        free(log);
    }
    
    glGetProgramiv(prog, GL_VALIDATE_STATUS, &status);
    if (status == 0) {
        return NO;
    }
    
    return YES;
}

+(void)setCacheShaderPrograms:(BOOL)shouldCache {
    shouldCacheShaders = shouldCache;
}

-(NSString*)dictionaryKeyForVertexShader:(NSString*)vShader fragmentShader:(NSString*)fShader {
    return [[NSMutableString alloc] initWithFormat:@"%@-%@", vShader, fShader];
}

@end
