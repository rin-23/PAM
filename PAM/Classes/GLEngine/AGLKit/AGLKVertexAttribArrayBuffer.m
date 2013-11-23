//
//  AGLKVertexAttribArrayBuffer.m
//  
//

#import "AGLKVertexAttribArrayBuffer.h"
#import <OpenGLES/ES2/gl.h>
#import <OpenGLES/ES2/glext.h>

@interface AGLKVertexAttribArrayBuffer ()

@property (nonatomic, assign) GLsizeiptr bufferSizeBytes;
@property (nonatomic, assign) GLsizeiptr stride;
@property (nonatomic, assign) GLenum target;

@end


@implementation AGLKVertexAttribArrayBuffer

@synthesize name;
@synthesize bufferSizeBytes;
@synthesize stride;
@synthesize target;

-(void)errorCheck {
    // Report any errors
    if (!self.errorChecking) {
        return;
    }
    GLenum error = glGetError();
    if (GL_NO_ERROR != error) {
        NSLog(@"GL Error: 0x%x", error);
    }
    
}

- (id)initWithAttribStride:(GLsizeiptr)aStride
          numberOfVertices:(GLsizei)count
                     bytes:(const GLvoid *)dataPtr
                     usage:(GLenum)usage
                    target:(GLenum)aTarget
{
    NSParameterAssert(0 < aStride);
    NSAssert((0 < count && NULL != dataPtr) ||
             (0 == count && NULL == dataPtr),
             @"data must not be NULL or count > 0");
    
    self = [super init];
    if (self)
    {
        _errorChecking = YES;
        stride = aStride;
        bufferSizeBytes = stride * count;
        target = aTarget;
        
        glGenBuffers(1, &name);                // STEP 1
        glBindBuffer(target, self.name); // STEP 2
        glBufferData(                  // STEP 3
                     target,  // Initialize buffer contents
                     bufferSizeBytes,  // Number of bytes to copy
                     dataPtr,          // Address of bytes to copy
                     usage);           // Hint: cache in GPU memory
        
        NSAssert(0 != name, @"Failed to generate name");
        [self errorCheck];
    }
   
    return self;

}

- (void)bufferSubDataWithOffset:(GLintptr)offset
                           size:(GLsizeiptr)size
                           data:(const GLvoid *)dataPtr
{
    NSAssert((offset + size <= self.bufferSizeBytes), @"Offest and size exceed curent buffer size");
    glBufferSubData(self.target, 0, self.bufferSizeBytes, dataPtr);
}


-(void)enableAttribute:(GLuint)index {
    glEnableVertexAttribArray(index);
    [self errorCheck];
}


-(void)bind {
    glBindBuffer(self.target, self.name);
    [self errorCheck];
}
/////////////////////////////////////////////////////////////////
// A vertex attribute array buffer must be prepared when your 
// application wants to use the buffer to render any geometry. 
// When your application prepares an buffer, some OpenGL ES state
// is altered to allow bind the buffer and configure pointers.
- (void)prepareToDrawWithAttrib:(GLuint)index
            numberOfCoordinates:(GLint)count
                   attribOffset:(GLsizeiptr)offset
                       dataType:(GLenum)type
                      normalize:(GLboolean)normalized
{
   NSParameterAssert((0 < count) && (count <= 4));
   NSParameterAssert(offset < self.stride);
   NSAssert(0 != name, @"Invalid name");

   glVertexAttribPointer(
      index,               // Identifies the attribute to use
      count,               // number of coordinates for attribute
      type,                // data is floating point
      normalized,            // no fixed point scaling
      self.stride,         // total num bytes stored per vertex
      (char*)NULL + offset);      // offset from start of each vertex to
                           // first coord for attribute

    [self errorCheck];
}


/////////////////////////////////////////////////////////////////
// Submits the drawing command identified by mode and instructs
// OpenGL ES to use count vertices from previously prepared 
// buffers starting from the vertex at index first in the 
// prepared buffers
+ (void)drawPreparedArraysWithMode:(GLenum)mode
   startVertexIndex:(GLint)first
   numberOfVertices:(GLsizei)count
{
   glDrawArrays(mode, first, count); // Step 6
}

+ (void)drawPreparedArraysWithMode:(GLenum)mode
                  dataType:(GLenum)dataType
                  indexCount:(GLsizei)numIndcies
{
    glDrawElements(mode, numIndcies, dataType, 0);
}

/////////////////////////////////////////////////////////////////
// This method deletes the receiver's buffer from the current
// Context when the receiver is deallocated.
- (void)dealloc
{
    // Delete buffer from current context
    if (0 != name)
    {
        glDeleteBuffers (1, &name); // Step 7 
        name = 0;
    }
}

@end
