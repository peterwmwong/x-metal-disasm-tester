//
//  shaders.metal
//  x-metal-disasm-tester
//
//  Created by Peter Wong on 2/6/23.
//

#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    vec<float,4> position  [[position]];
    float point_size [[point_size]];
};


[[vertex]]
VertexOut main_vertex() {
    return {
        .position = float4(0,0,0,1),
        .point_size = 2.0
    };
}

[[fragment]]
half4 main_fragment() {
    return half4(1.);
}
