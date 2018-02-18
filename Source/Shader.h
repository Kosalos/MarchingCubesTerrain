#ifndef Shader_h
#define Shader_h
#include <simd/simd.h>
#include <simd/base.h>

#define SGSIZE  30      // grid size

struct TVertex {
    vector_float3 pos;
    vector_float3 nrm;
    vector_float2 txt;
    float flux;
    unsigned char inside;
};

struct Control {
    matrix_float4x4 mvp;
    vector_float3 light;
    float ambient;
    int mode;
    int tCount;
    
    float isoValue;
};

#endif /* Shader_h */
