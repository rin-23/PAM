//
//  AGLKVertexAttribArrayBuffer.h
//  
//

#import <GLKit/GLKit.h>

@interface AGLKVertexAttribArrayBuffer : NSObject
{
    GLsizeiptr stride;
    GLsizeiptr bufferSizeBytes;
    GLuint name;
    GLenum target;
}

@property (nonatomic, readonly) GLuint name;
@property (nonatomic, readonly) GLsizeiptr bufferSizeBytes;
@property (nonatomic, readonly) GLsizeiptr stride;
@property (nonatomic, assign) BOOL errorChecking;

- (id)initWithAttribStride:(GLsizeiptr)aStride
          numberOfVertices:(GLsizei)count
                     bytes:(const GLvoid *)dataPtr
                     usage:(GLenum)usage
                    target:(GLenum)aTarget;

- (void)bufferSubDataWithOffset:(GLintptr)offset
                           size:(GLsizeiptr)size
                           data:(const GLvoid *)dataPtr;

- (void)prepareToDrawWithAttrib:(GLuint)index
            numberOfCoordinates:(GLint)count
                   attribOffset:(GLsizeiptr)offset
                       dataType:(GLenum)type
                      normalize:(GLboolean)normalized;

-(void)enableAttribute:(GLuint)index;

-(void)bind;

+ (void)drawPreparedArraysWithMode:(GLenum)mode
                  startVertexIndex:(GLint)first
                  numberOfVertices:(GLsizei)count;

+ (void)drawPreparedArraysWithMode:(GLenum)mode
                          dataType:(GLenum)dataType
                        indexCount:(GLsizei)numIndcies;

@end
