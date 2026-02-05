#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0, r8) uniform restrict readonly image2D input_grid;
layout(set = 0, binding = 1, rgba8) uniform restrict writeonly image2D output_color;

layout(push_constant) uniform PushConstants {
    vec4 dead_color;
    vec4 alive_color;
    vec4 glow_color;
    float glow_strength;
    float enable_glow;
} pc;

void main() {
    ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
    ivec2 size = imageSize(input_grid);
    
    if (pos.x >= size.x || pos.y >= size.y) {
        return;
    }
    
    float alive = imageLoad(input_grid, pos).r;
    vec4 final_color;
    
    if (alive > 0.5) {
        final_color = pc.alive_color;
    } else {
        final_color = pc.dead_color;
        
        if (pc.enable_glow > 0.5) {
            int neighbor_count = 0;
            
            if (pos.x > 0 && imageLoad(input_grid, pos + ivec2(-1, 0)).r > 0.5) neighbor_count++;
            if (pos.x < size.x - 1 && imageLoad(input_grid, pos + ivec2(1, 0)).r > 0.5) neighbor_count++;
            if (pos.y > 0 && imageLoad(input_grid, pos + ivec2(0, -1)).r > 0.5) neighbor_count++;
            if (pos.y < size.y - 1 && imageLoad(input_grid, pos + ivec2(0, 1)).r > 0.5) neighbor_count++;
            
            if (neighbor_count > 0) {
                float glow_factor = (float(neighbor_count) / 4.0) * pc.glow_strength;
                final_color = mix(pc.dead_color, pc.glow_color, glow_factor);
            }
        }
    }
    
    imageStore(output_color, pos, final_color);
}
