const highp vec4 packFactors = vec4(1.0, 255.0, 65025.0, 16581375.0);
const highp vec4 cutoffMask  = vec4(1.0/255.0,1.0/255.0,1.0/255.0,0.0);

void main()
{
//    gl_FragColor = vec4(vec3(gl_FragCoord.z), 1.0);
    highp vec4 packedVal = vec4(fract(packFactors * gl_FragCoord.z));
    gl_FragColor = packedVal - packedVal.yzww * cutoffMask;
}

 