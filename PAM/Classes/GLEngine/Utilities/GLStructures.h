//
//  DataStructures.h
//  Pelvic-iOS
//
//  Created by Rinat Abdrashitov on 12-10-22.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#ifndef Pelvic_iOS_GLStructures_h
#define Pelvic_iOS_GLStructures_h

typedef struct {
    GLfloat x;
    GLfloat y;
    GLfloat z;   
} PositionXYZ;

typedef struct {
    GLfloat s;
    GLfloat t;
} TextureCoord;

typedef struct {
    GLubyte r;
    GLubyte g;
    GLubyte b;
    GLubyte a;
} ColorRGBA;

typedef struct {
    GLubyte c;
} ColorMonochrome;

typedef struct {
    PositionXYZ position;
    ColorRGBA color;
} VertexRGBA;

typedef struct {
    PositionXYZ position;
    ColorMonochrome color;
} VertexMonochrome;

typedef struct {
    PositionXYZ position;
    TextureCoord texture;
} VertexTexture;

typedef struct {
    PositionXYZ position;
    PositionXYZ normal;
    ColorRGBA color;
} VertexNormRGBA;

typedef struct {
    PositionXYZ position;
    PositionXYZ normal;
    ColorMonochrome color;
} VertexNormMonochrome;

#endif
