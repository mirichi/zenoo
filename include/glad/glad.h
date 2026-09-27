#ifndef __glad_h_
#define __glad_h_

#ifdef __gl_h_
#error OpenGL header already included, remove this include, glad already provides it
#endif
#define __gl_h_

#if defined(_WIN32) && !defined(APIENTRY) && !defined(__CYGWIN__) && !defined(__SC__)
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#endif

#ifndef APIENTRY
#define APIENTRY
#endif
#ifndef APIENTRYP
#define APIENTRYP APIENTRY *
#endif
#ifndef GLAPI
#define GLAPI extern
#endif

#include "KHR/khrplatform.h"

typedef unsigned int GLenum;
typedef unsigned char GLboolean;
typedef unsigned int GLbitfield;
typedef void GLvoid;
typedef signed char GLbyte;
typedef short GLshort;
typedef int GLint;
typedef int GLsizei;
typedef unsigned char GLubyte;
typedef unsigned short GLushort;
typedef unsigned int GLuint;
typedef unsigned short GLhalf;
typedef float GLfloat;
typedef float GLclampf;
typedef double GLdouble;
typedef double GLclampd;
typedef char GLchar;
typedef ptrdiff_t GLsizeiptr;
typedef ptrdiff_t GLintptr;

#define GL_FALSE                          0
#define GL_TRUE                           1
#define GL_BYTE                           0x1400
#define GL_UNSIGNED_BYTE                  0x1401
#define GL_SHORT                          0x1402
#define GL_UNSIGNED_SHORT                 0x1403
#define GL_INT                            0x1404
#define GL_UNSIGNED_INT                   0x1405
#define GL_FLOAT                          0x1406
#define GL_POINTS                         0x0000
#define GL_LINES                          0x0001
#define GL_LINE_LOOP                      0x0002
#define GL_LINE_STRIP                     0x0003
#define GL_TRIANGLES                      0x0004
#define GL_TRIANGLE_STRIP                 0x0005
#define GL_TRIANGLE_FAN                   0x0006
#define GL_COLOR_BUFFER_BIT               0x00004000
#define GL_DEPTH_BUFFER_BIT               0x00000100
#define GL_BLEND                          0x0BE2
#define GL_SRC_ALPHA                      0x0302
#define GL_ONE_MINUS_SRC_ALPHA            0x0303
#define GL_SRC_COLOR                      0x0300
#define GL_DST_COLOR                      0x0306
#define GL_ONE                            1
#define GL_ZERO                           0
#define GL_SCISSOR_TEST                   0x0C11
#define GL_TEXTURE_2D                     0x0DE1
#define GL_TEXTURE_WRAP_S                 0x2802
#define GL_TEXTURE_WRAP_T                 0x2803
#define GL_TEXTURE_MAG_FILTER             0x2800
#define GL_TEXTURE_MIN_FILTER             0x2801
#define GL_NEAREST                        0x2600
#define GL_LINEAR                         0x2601
#define GL_CLAMP_TO_EDGE                  0x812F
#define GL_RGBA                           0x1908
#define GL_RGB                            0x1907
#define GL_RED                            0x1903
#define GL_ARRAY_BUFFER                   0x8892
#define GL_ELEMENT_ARRAY_BUFFER           0x8893
#define GL_STREAM_DRAW                    0x88E0
#define GL_STATIC_DRAW                    0x88E4
#define GL_DYNAMIC_DRAW                   0x88E8
#define GL_FRAGMENT_SHADER                0x8B30
#define GL_VERTEX_SHADER                  0x8B31
#define GL_COMPILE_STATUS                 0x8B81
#define GL_LINK_STATUS                    0x8B82
#define GL_INFO_LOG_LENGTH                0x8B84
#define GL_ACTIVE_TEXTURE                 0x84E0
#define GL_TEXTURE0                       0x84C0

#define GL_VENDOR                         0x1F00
#define GL_RENDERER                       0x1F01
#define GL_VERSION                        0x1F02
#define GL_EXTENSIONS                     0x1F03

typedef const GLubyte * (APIENTRYP PFNGLGETSTRINGPROC)(GLenum name);
GLAPI PFNGLGETSTRINGPROC glGetString;

typedef void (APIENTRYP PFNGLVIEWPORTPROC)(GLint x, GLint y, GLsizei width, GLsizei height);
typedef void (APIENTRYP PFNGLCLEARCOLORPROC)(GLfloat red, GLfloat green, GLfloat blue, GLfloat alpha);
typedef void (APIENTRYP PFNGLCLEARPROC)(GLbitfield mask);
typedef void (APIENTRYP PFNGLFLUSHPROC)(void);
typedef void (APIENTRYP PFNGLENABLEPROC)(GLenum cap);
typedef void (APIENTRYP PFNGLDISABLEPROC)(GLenum cap);

GLAPI PFNGLFLUSHPROC glFlush;
typedef void (APIENTRYP PFNGLBLENDFUNCPROC)(GLenum sfactor, GLenum dfactor);
typedef void (APIENTRYP PFNGLBLENDFUNCSEPARATEPROC)(GLenum sfactorRGB, GLenum dfactorRGB, GLenum sfactorAlpha, GLenum dfactorAlpha);
typedef void (APIENTRYP PFNGLSCISSORPROC)(GLint x, GLint y, GLsizei width, GLsizei height);

typedef void (APIENTRYP PFNGLGENTEXTURESPROC)(GLsizei n, GLuint *textures);
typedef void (APIENTRYP PFNGLDELETETEXTURESPROC)(GLsizei n, const GLuint *textures);
typedef void (APIENTRYP PFNGLBINDTEXTUREPROC)(GLenum target, GLuint texture);
typedef void (APIENTRYP PFNGLTEXIMAGE2DPROC)(GLenum target, GLint level, GLint internalformat, GLsizei width, GLsizei height, GLint border, GLenum format, GLenum type, const void *pixels);
typedef void (APIENTRYP PFNGLTEXPARAMETERIPROC)(GLenum target, GLenum pname, GLint param);
typedef void (APIENTRYP PFNGLACTIVETEXTUREPROC)(GLenum texture);

typedef GLuint (APIENTRYP PFNGLCREATESHADERPROC)(GLenum type);
typedef void (APIENTRYP PFNGLSHADERSOURCEPROC)(GLuint shader, GLsizei count, const GLchar *const*string, const GLint *length);
typedef void (APIENTRYP PFNGLCOMPILESHADERPROC)(GLuint shader);
typedef void (APIENTRYP PFNGLGETSHADERIVPROC)(GLuint shader, GLenum pname, GLint *params);
typedef void (APIENTRYP PFNGLGETSHADERINFOLOGPROC)(GLuint shader, GLsizei bufSize, GLsizei *length, GLchar *infoLog);
typedef void (APIENTRYP PFNGLDELETESHADERPROC)(GLuint shader);

typedef GLuint (APIENTRYP PFNGLCREATEPROGRAMPROC)(void);
typedef void (APIENTRYP PFNGLATTACHSHADERPROC)(GLuint program, GLuint shader);
typedef void (APIENTRYP PFNGLLINKPROGRAMPROC)(GLuint program);
typedef void (APIENTRYP PFNGLGETPROGRAMIVPROC)(GLuint program, GLenum pname, GLint *params);
typedef void (APIENTRYP PFNGLGETPROGRAMINFOLOGPROC)(GLuint program, GLsizei bufSize, GLsizei *length, GLchar *infoLog);
typedef void (APIENTRYP PFNGLUSEPROGRAMPROC)(GLuint program);
typedef void (APIENTRYP PFNGLDELETEPROGRAMPROC)(GLuint program);

typedef GLint (APIENTRYP PFNGLGETUNIFORMLOCATIONPROC)(GLuint program, const GLchar *name);
typedef void (APIENTRYP PFNGLUNIFORM1IPROC)(GLint location, GLint v0);
typedef void (APIENTRYP PFNGLUNIFORM1FPROC)(GLint location, GLfloat v0);
typedef void (APIENTRYP PFNGLUNIFORM2FPROC)(GLint location, GLfloat v0, GLfloat v1);
typedef void (APIENTRYP PFNGLUNIFORM3FPROC)(GLint location, GLfloat v0, GLfloat v1, GLfloat v2);
typedef void (APIENTRYP PFNGLUNIFORM4FPROC)(GLint location, GLfloat v0, GLfloat v1, GLfloat v2, GLfloat v3);
typedef void (APIENTRYP PFNGLUNIFORMMATRIX4FVPROC)(GLint location, GLsizei count, GLboolean transpose, const GLfloat *value);

typedef void (APIENTRYP PFNGLGENVERTEXARRAYSPROC)(GLsizei n, GLuint *arrays);
typedef void (APIENTRYP PFNGLDELETEVERTEXARRAYSPROC)(GLsizei n, const GLuint *arrays);
typedef void (APIENTRYP PFNGLBINDVERTEXARRAYPROC)(GLuint array);

typedef void (APIENTRYP PFNGLGENBUFFERSPROC)(GLsizei n, GLuint *buffers);
typedef void (APIENTRYP PFNGLDELETEBUFFERSPROC)(GLsizei n, const GLuint *buffers);
typedef void (APIENTRYP PFNGLBINDBUFFERPROC)(GLenum target, GLuint buffer);
typedef void (APIENTRYP PFNGLBUFFERDATAPROC)(GLenum target, GLsizeiptr size, const void *data, GLenum usage);
typedef void (APIENTRYP PFNGLBUFFERSUBDATAPROC)(GLenum target, GLintptr offset, GLsizeiptr size, const void *data);

typedef void (APIENTRYP PFNGLENABLEVERTEXATTRIBARRAYPROC)(GLuint index);
typedef void (APIENTRYP PFNGLDISABLEVERTEXATTRIBARRAYPROC)(GLuint index);
typedef void (APIENTRYP PFNGLVERTEXATTRIBPOINTERPROC)(GLuint index, GLint size, GLenum type, GLboolean normalized, GLsizei stride, const void *pointer);
typedef void (APIENTRYP PFNGLVERTEXATTRIBDIVISORPROC)(GLuint index, GLuint divisor);

typedef void (APIENTRYP PFNGLDRAWARRAYSPROC)(GLenum mode, GLint first, GLsizei count);
typedef void (APIENTRYP PFNGLDRAWARRAYSINSTANCEDPROC)(GLenum mode, GLint first, GLsizei count, GLsizei instancecount);
typedef void (APIENTRYP PFNGLDRAWELEMENTSPROC)(GLenum mode, GLsizei count, GLenum type, const void *indices);
typedef void (APIENTRYP PFNGLDRAWELEMENTSINSTANCEDPROC)(GLenum mode, GLsizei count, GLenum type, const void *indices, GLsizei instancecount);

GLAPI PFNGLVIEWPORTPROC glViewport;
GLAPI PFNGLCLEARCOLORPROC glClearColor;
GLAPI PFNGLCLEARPROC glClear;
GLAPI PFNGLENABLEPROC glEnable;
GLAPI PFNGLDISABLEPROC glDisable;
GLAPI PFNGLBLENDFUNCPROC glBlendFunc;
GLAPI PFNGLBLENDFUNCSEPARATEPROC glBlendFuncSeparate;
GLAPI PFNGLSCISSORPROC glScissor;

GLAPI PFNGLGENTEXTURESPROC glGenTextures;
GLAPI PFNGLDELETETEXTURESPROC glDeleteTextures;
GLAPI PFNGLBINDTEXTUREPROC glBindTexture;
GLAPI PFNGLTEXIMAGE2DPROC glTexImage2D;
GLAPI PFNGLTEXPARAMETERIPROC glTexParameteri;
GLAPI PFNGLACTIVETEXTUREPROC glActiveTexture;

GLAPI PFNGLCREATESHADERPROC glCreateShader;
GLAPI PFNGLSHADERSOURCEPROC glShaderSource;
GLAPI PFNGLCOMPILESHADERPROC glCompileShader;
GLAPI PFNGLGETSHADERIVPROC glGetShaderiv;
GLAPI PFNGLGETSHADERINFOLOGPROC glGetShaderInfoLog;
GLAPI PFNGLDELETESHADERPROC glDeleteShader;

GLAPI PFNGLCREATEPROGRAMPROC glCreateProgram;
GLAPI PFNGLATTACHSHADERPROC glAttachShader;
GLAPI PFNGLLINKPROGRAMPROC glLinkProgram;
GLAPI PFNGLGETPROGRAMIVPROC glGetProgramiv;
GLAPI PFNGLGETPROGRAMINFOLOGPROC glGetProgramInfoLog;
GLAPI PFNGLUSEPROGRAMPROC glUseProgram;
GLAPI PFNGLDELETEPROGRAMPROC glDeleteProgram;

GLAPI PFNGLGETUNIFORMLOCATIONPROC glGetUniformLocation;
GLAPI PFNGLUNIFORM1IPROC glUniform1i;
GLAPI PFNGLUNIFORM1FPROC glUniform1f;
GLAPI PFNGLUNIFORM2FPROC glUniform2f;
GLAPI PFNGLUNIFORM3FPROC glUniform3f;
GLAPI PFNGLUNIFORM4FPROC glUniform4f;
GLAPI PFNGLUNIFORMMATRIX4FVPROC glUniformMatrix4fv;

GLAPI PFNGLGENVERTEXARRAYSPROC glGenVertexArrays;
GLAPI PFNGLDELETEVERTEXARRAYSPROC glDeleteVertexArrays;
GLAPI PFNGLBINDVERTEXARRAYPROC glBindVertexArray;

GLAPI PFNGLGENBUFFERSPROC glGenBuffers;
GLAPI PFNGLDELETEBUFFERSPROC glDeleteBuffers;
GLAPI PFNGLBINDBUFFERPROC glBindBuffer;
GLAPI PFNGLBUFFERDATAPROC glBufferData;
GLAPI PFNGLBUFFERSUBDATAPROC glBufferSubData;

GLAPI PFNGLENABLEVERTEXATTRIBARRAYPROC glEnableVertexAttribArray;
GLAPI PFNGLDISABLEVERTEXATTRIBARRAYPROC glDisableVertexAttribArray;
GLAPI PFNGLVERTEXATTRIBPOINTERPROC glVertexAttribPointer;
GLAPI PFNGLVERTEXATTRIBDIVISORPROC glVertexAttribDivisor;

GLAPI PFNGLDRAWARRAYSPROC glDrawArrays;
GLAPI PFNGLDRAWARRAYSINSTANCEDPROC glDrawArraysInstanced;
GLAPI PFNGLDRAWELEMENTSPROC glDrawElements;
GLAPI PFNGLDRAWELEMENTSINSTANCEDPROC glDrawElementsInstanced;

#define GL_FRAMEBUFFER                    0x8D40
#define GL_READ_FRAMEBUFFER               0x8CA8
#define GL_DRAW_FRAMEBUFFER               0x8CA9
#define GL_COLOR_ATTACHMENT0              0x8CE0
#define GL_FRAMEBUFFER_COMPLETE           0x8CD5

typedef void (APIENTRYP PFNGLGENFRAMEBUFFERSPROC)(GLsizei n, GLuint *framebuffers);
typedef void (APIENTRYP PFNGLDELETEFRAMEBUFFERSPROC)(GLsizei n, const GLuint *framebuffers);
typedef void (APIENTRYP PFNGLBINDFRAMEBUFFERPROC)(GLenum target, GLuint framebuffer);
typedef void (APIENTRYP PFNGLFRAMEBUFFERTEXTURE2DPROC)(GLenum target, GLenum attachment, GLenum textarget, GLuint texture, GLint level);
typedef GLenum (APIENTRYP PFNGLCHECKFRAMEBUFFERSTATUSPROC)(GLenum target);

GLAPI PFNGLGENFRAMEBUFFERSPROC glGenFramebuffers;
GLAPI PFNGLDELETEFRAMEBUFFERSPROC glDeleteFramebuffers;
GLAPI PFNGLBINDFRAMEBUFFERPROC glBindFramebuffer;
GLAPI PFNGLFRAMEBUFFERTEXTURE2DPROC glFramebufferTexture2D;
GLAPI PFNGLCHECKFRAMEBUFFERSTATUSPROC glCheckFramebufferStatus;

typedef void* (*GLADloadproc)(const char *name);
GLAPI int gladLoadGLLoader(GLADloadproc load);

#ifdef __cplusplus
}
#endif

#endif
