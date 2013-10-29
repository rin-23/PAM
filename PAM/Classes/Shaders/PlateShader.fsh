varying lowp vec4 colorVarying;
varying highp vec4 positionVarying;

uniform highp float holeRadius;
uniform highp vec4 holeCenter;

//uniform highp float holeSpacing;
//uniform highp vec4 startPoint;
//uniform highp vec4 direction;
//uniform highp float length;
//uniform int numberOfHoles;

void main()
{
    gl_FragColor = colorVarying;

    if (distance(positionVarying, holeCenter) < holeRadius) {
        gl_FragColor = vec4(0,0,0,0);
    }
}




