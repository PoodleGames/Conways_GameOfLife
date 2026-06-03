#[compute]
#version 450
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(set = 0, binding = 0, r8) uniform restrict readonly image2D input_grid;
layout(set = 0, binding = 1, r8) uniform restrict writeonly image2D output_grid;

void main() {
	ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = imageSize(input_grid);
	
	if (pos.x >= size.x || pos.y >= size.y) {
		return;
	}
	
	float alive = imageLoad(input_grid, pos).r;
	
	int neighbors = 0;
	for (int dy = -1; dy <= 1; dy++) {
		for (int dx = -1; dx <= 1; dx++) {
			if (dx == 0 && dy == 0) continue;
			
			ivec2 npos = pos + ivec2(dx, dy);
			npos = clamp(npos, ivec2(0), size - ivec2(1));
			
			if (imageLoad(input_grid, npos).r > 0.5) {
				neighbors++;
			}
		}
	}
	
	float new_state = 0.0;
	if (alive > 0.5) {
		if (neighbors == 2 || neighbors == 3) {
			new_state = 1.0;
		}
	} else {
		if (neighbors == 3) {
			new_state = 1.0;
		}
	}
	
	imageStore(output_grid, pos, vec4(new_state));
}
