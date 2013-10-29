attribute vec4 position;
attribute vec4 color;

varying lowp vec4 colorVarying;
varying highp vec4 positionVarying;

uniform mat4 modelViewProjectionMatrix;

invariant gl_Position;

void main() 
{
    gl_PointSize = 5.0;
    colorVarying = color;
    positionVarying = position;
    gl_Position = modelViewProjectionMatrix * position;
}
