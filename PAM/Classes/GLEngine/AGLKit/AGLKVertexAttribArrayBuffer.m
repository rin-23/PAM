//
//  AGLKVertexAttribArrayBuffer.m
//  
//

#import "AGLKVertexAttribArrayBuffer.h"

@interface AGLKVertexAttribArrayBuffer ()

@property (nonatomic, assign) GLsizeiptr bufferSizeBytes;
@property (nonatomic, assign) GLsizeiptr stride;

@end


@implementation AGLKVertexAttribArrayBuffer

@synthesize name;
@synthesize bufferSizeBytes;
@synthesize stride;

/////////////////////////////////////////////////////////////////
// This method creates a vertex attribute array buffer in
// the current OpenGL ES context for the thread upon which this 
// method is called.
- (id)initWithAttribStride:(GLsizeiptr)aStride
   numberOfVertices:(GLsizei)count
   bytes:(const GLvoid *)dataPtr
   usage:(GLenum)usage;
{
    NSParameterAssert(0 < aStride);
    NSAssert((0 < count && NULL != dataPtr) ||
             (0 == count && NULL == dataPtr),
             @"data must not be NULL or count > 0");
    
    if(nil != (self = [super init]))
    {
        stride = aStride;
        bufferSizeBytes = stride * count;
        
        glGenBuffers(1, &name);                // STEP 1
        glBindBuffer(GL_ARRAY_BUFFER, self.name); // STEP 2
        glBufferData(                  // STEP 3
                     GL_ARRAY_BUFFER,  // Initialize buffer contents
                     bufferSizeBytes,  // Number of bytes to copy
                     dataPtr,          // Address of bytes to copy
                     usage);           // Hint: cache in GPU memory
        
        NSAssert(0 != name, @"Failed to generate name");
    }
    
    // Report any errors
    GLenum error = glGetError();
    if (GL_NO_ERROR != error) {
        NSLog(@"GL Error: 0x%x", error);
    }   
    
    return self;
}

- (void)bufferSubDataWithOffset:(GLintptr)offset size:(GLsizeiptr)size data:(const GLvoid *)dataPtr
{
    NSAssert((offset + size <= self.bufferSizeBytes), @"Offest and size exceed curent buffer size");

    glBindBuffer(GL_ARRAY_BUFFER, self.name); // STEP 2
    glBufferSubData(GL_ARRAY_BUFFER, 0, self.bufferSizeBytes, dataPtr);
}


-(void)enableAttribute:(GLuint)index {
    glEnableVertexAttribArray(index);
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

   glBindBuffer(GL_ARRAY_BUFFER,self.name);

//    glVertexAttribPointer (GLuint indx, GLint size, GLenum type, GLboolean normalized, GLsizei stride, const GLvoid* ptr)
    
   glVertexAttribPointer(
      index,               // Identifies the attribute to use
      count,               // number of coordinates for attribute
      type,                // data is floating point
      normalized,            // no fixed point scaling
      self.stride,         // total num bytes stored per vertex
      (char*)NULL + offset);      // offset from start of each vertex to
                           // first coord for attribute

   {  // Report any errors 
      GLenum error = glGetError();
      if(GL_NO_ERROR != error)
      {
         NSLog(@"GL Error: 0x%x", error);
      }
   }
}


/////////////////////////////////////////////////////////////////
// Submits the drawing command identified by mode and instructs
// OpenGL ES to use count vertices from the buffer starting from
// the vertex at index first. Vertex indices start at 0.
- (void)drawArrayWithMode:(GLenum)mode
   startVertexIndex:(GLint)first
   numberOfVertices:(GLsizei)count
{
   NSAssert(self.bufferSizeBytes >= 
      ((first + count) * self.stride),
      @"Attempt to draw more vertex data than available.");
      
   glDrawArrays(mode, first, count); // Step 6
}


/////////////////////////////////////////////////////////////////
// Submits the drawing command identified by mode and instructs
// OpenGL ES to use count vertices from previously prepared 
// buffers starting from the vertex at index first in the 
// prepared buffers
+ (void)drawPreparedArraysWithMode:(GLenum)mode
   startVertexIndex:(GLint)first
   numberOfVertices:(GLsizei)count;
{
   glDrawArrays(mode, first, count); // Step 6
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
