varying lowp vec4 frontColor;
varying lowp vec4 vColor;

void main()
{
    gl_FragColor = vColor * frontColor;
}
