varying lowp vec2 textureVarying; // New
uniform sampler2D textureUniform; // New

void main(void) {
    gl_FragColor =  texture2D(textureUniform, textureVarying); // New
}