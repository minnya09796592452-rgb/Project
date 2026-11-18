shader_type canvas_item;
render_mode unshaded, blend_disabled;

// Ceto 1.1.4 DisplacementCopy.shader translated to a single-target pass.
uniform sampler2D height_buffer : filter_nearest, repeat_disable;
uniform sampler2D displacement_buffer : filter_nearest, repeat_disable;
uniform int grid_index : hint_range(0, 3) = 0;
uniform bool compact_single_grid = false;

void fragment() {
	vec4 height_data = textureLod(height_buffer, UV, 0.0);
	if (compact_single_grid) {
		// Unity CopyGrid1Compact: d.xyz = height_data.zxw.
		COLOR = vec4(height_data.z, height_data.x, height_data.w, 0.0);
		return;
	}

	vec4 displacement_data = textureLod(displacement_buffer, UV, 0.0);
	vec2 horizontal = (grid_index == 0 || grid_index == 2)
		? displacement_data.xy
		: displacement_data.zw;
	float height_value = height_data[grid_index];
	COLOR = vec4(horizontal.x, height_value, horizontal.y, 0.0);
}
