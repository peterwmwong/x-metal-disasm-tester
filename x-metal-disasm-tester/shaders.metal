//
//  shaders.metal
//  x-metal-disasm-tester
//
//  Created by Peter Wong on 2/6/23.
//

#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 tx_coord;
};


[[vertex]]
VertexOut main_vertex(uint vertex_id [[vertex_id]]) {
    switch (vertex_id) {
        /* Top Left */     case 0: return { .position = float4(-1, 1, 0, 1), .tx_coord = float2(0, 0) };
        /* Top Right */    case 1: return { .position = float4( 1, 1, 0, 1), .tx_coord = float2(4, 0) };
        /* Bottom Left */  case 2: return { .position = float4(-1,-1, 0, 1), .tx_coord = float2(0, 4) };
        /* Bottom RIght */ case 3: return { .position = float4( 1,-1, 0, 1), .tx_coord = float2(4, 4) };
    };
}

[[fragment]]
half4 main_fragment(VertexOut                       in [[stage_in]],
                    texture2d<float, access::write> tx [[texture(0)]]) {
    uint2 tx_coord = uint2(in.tx_coord);
    tx.write(float4(in.tx_coord, 0., 1.), tx_coord);
    return half4(1.);
}
