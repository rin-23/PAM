attribute vec4 position;

uniform mat4 modelViewProjectionMatrix;

invariant gl_Position;

void main()
{
    gl_PointSize = 20.0;
    gl_Position = modelViewProjectionMatrix * position;
}