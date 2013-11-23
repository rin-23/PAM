attribute vec4 position;

varying lowp vec4 colorVarying;

uniform mat4 modelViewProjectionMatrix;

invariant gl_Position;

void main()
{
    colorVarying = vec4(1.0, 0.0, 0.0, 1.0);
    gl_Position = modelViewProjectionMatrix * position;
}
