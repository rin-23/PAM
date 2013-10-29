attribute vec4 position;
attribute vec4 normal;
attribute vec4 color;

uniform mat4 matrix;
uniform vec4 lightDirection;
uniform vec4 lightDiffuseColor;

varying lowp vec4 frontColor;
varying lowp vec4 vColor;

void main()
{
    vec4 normalizedNormal = normalize(matrix * normal);
    vec4 normalizedLightDirection = normalize(lightDirection);
    
    float nDotL = max(dot(normalizedNormal, normalizedLightDirection), 0.0);
    
    frontColor = nDotL * lightDiffuseColor;
    vColor = color;
    
    gl_Position = matrix * position;
}