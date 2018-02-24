#include <metal_stdlib>
#include <simd/simd.h>
#import "Shader.h"

using namespace metal;

struct Transfer {
    float4 position [[position]];
    float2 txt;
    float4 lighting;
};

vertex Transfer texturedVertexShader
(
 device TVertex* vData [[ buffer(0) ]],
 constant Control& control [[ buffer(1) ]],
 unsigned int vid [[ vertex_id ]])
{
    Transfer out;
    TVertex v = vData[vid];
    
    out.txt = v.txt;
    out.position = control.mvp * float4(v.pos, 1.0);
    
    float intensity = control.ambient + saturate(dot(vData[vid].nrm.rgb, control.light));
    out.lighting = float4(intensity,intensity,intensity,1);
    
    return out;
}

fragment float4 texturedFragmentShader
(
 Transfer data [[stage_in]],
 texture2d<float> tex2D [[texture(0)]],
 sampler sampler2D [[sampler(0)]])
{
    return tex2D.sample(sampler2D, data.txt.xy) * data.lighting;
}

//MARK: -

#define SGSIZEX 1         // xyz indexing into array
#define SGSIZEY SGSIZE
#define SGSIZEZ (SGSIZE * SGSIZE)

kernel void calcGridInsideAndNormal
(
 device TVertex *grid [[ buffer(0) ]],
 const device Control &control[[ buffer(1) ]],
 uint id [[ thread_position_in_grid ]])
{
    int ix = int(id);
    int iz = ix / SGSIZEZ;   ix -= iz * SGSIZEZ;
    int iy = ix / SGSIZEY;   ix -= iy * SGSIZEY;
    
    if(ix < 1 || iy < 1 || iz < 1) return;
    if(ix >= SGSIZE-1 || iy >= SGSIZE-1 || iz >= SGSIZE-1) return;
    
    grid[id].inside = grid[id].flux >= control.isoValue ? 1 : 0;
    
    grid[id].nrm.x = grid[id - SGSIZEX].flux - grid[id + SGSIZEX].flux;
    grid[id].nrm.y = grid[id - SGSIZEY].flux - grid[id + SGSIZEY].flux;
    grid[id].nrm.z = grid[id - SGSIZEZ].flux - grid[id + SGSIZEZ].flux;
    grid[id].nrm = normalize(grid[id].nrm);
}

//MARK: -

kernel void calcScrollTexture
(
 device TVertex *tri [[ buffer(0) ]],
 const device Control &control[[ buffer(1) ]],
 uint id [[ thread_position_in_grid ]])
{
    if(int(id) > control.tCount) return;
    
    tri[id].txt.x += 0.0020;
    tri[id].txt.y += 0.0024;
    
    if(tri[id].txt.x >= 1) tri[id].txt.x -= 1;
    if(tri[id].txt.y >= 1) tri[id].txt.y -= 1;
}

