attribute vec4 position;
attribute vec2 texture;

uniform mat4 modelViewProjectionMatrix;

varying vec2 textureVarying; // New

void main(void) {
    gl_Position = modelViewProjectionMatrix * position;
    textureVarying = texture; // New
}