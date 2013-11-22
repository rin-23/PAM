//
//  AGLKVertexAttribArrayBuffer.h
//  
//

#import <GLKit/GLKit.h>

@class AGLKElementIndexArrayBuffer;

/////////////////////////////////////////////////////////////////
// 
typedef enum {
    AGLKVertexAttribPosition = GLKVertexAttribPosition,
    AGLKVertexAttribNormal = GLKVertexAttribNormal,
    AGLKVertexAttribColor = GLKVertexAttribColor,
    AGLKVertexAttribTexCoord0 = GLKVertexAttribTexCoord0,
    AGLKVertexAttribTexCoord1 = GLKVertexAttribTexCoord1,
} AGLKVertexAttrib;


@interface AGLKVertexAttribArrayBuffer : NSObject
{
   GLsizeiptr   stride;
   GLsizeiptr   bufferSizeBytes;
   GLuint       name;
}

@property (nonatomic, readonly) GLuint
   name;
@property (nonatomic, readonly) GLsizeiptr
   bufferSizeBytes;
@property (nonatomic, readonly) GLsizeiptr
   stride;

+ (void)drawPreparedArraysWithMode:(GLenum)mode
   startVertexIndex:(GLint)first
   numberOfVertices:(GLsizei)count;

- (id)initWithAttribStride:(GLsizeiptr)stride
   numberOfVertices:(GLsizei)count
   bytes:(const GLvoid *)dataPtr
   usage:(GLenum)usage;

- (void)bufferSubDataWithOffset:(GLintptr)offset
                           size:(GLsizeiptr)size
                           data:(const GLvoid *)dataPtr;

- (void)prepareToDrawWithAttrib:(GLuint)index
   numberOfCoordinates:(GLint)count
   attribOffset:(GLsizeiptr)offset
       dataType:(GLenum)type
      normalize:(GLboolean)normalized;

- (void)drawArrayWithMode:(GLenum)mode
   startVertexIndex:(GLint)first
   numberOfVertices:(GLsizei)count;

-(void)enableAttribute:(GLuint)index;

-(void)bind;


@end
