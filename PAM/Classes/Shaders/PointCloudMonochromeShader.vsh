attribute vec4 position;
attribute float color;

varying lowp vec4 colorVarying;

uniform mat4 modelViewProjectionMatrix;
uniform float u_PointSize;

invariant gl_Position;

void main()
{
    gl_PointSize = u_PointSize;
    colorVarying = vec4(color, color, color, 1.0);
    gl_Position = modelViewProjectionMatrix * position;
}
