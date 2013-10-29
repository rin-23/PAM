attribute vec4 position;
attribute vec4 color;

varying lowp vec4 colorVarying;

uniform mat4 modelViewProjectionMatrix;
uniform float u_PointSize;

invariant gl_Position;

void main()
{
    gl_PointSize = u_PointSize;
    colorVarying = color;
    gl_Position = modelViewProjectionMatrix * position;
}
