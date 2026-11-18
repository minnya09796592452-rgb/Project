shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

uniform sampler2D displacement_grid_0 : filter_linear, repeat_enable;
uniform sampler2D displacement_grid_1 : filter_linear, repeat_enable;
uniform sampler2D displacement_grid_2 : filter_linear, repeat_enable;
uniform sampler2D displacement_grid_3 : filter_linear, repeat_enable;
uniform vec4 grid_sizes = vec4(1372.0, 392.0, 28.0, 4.0);
uniform vec4 choppiness = vec4(2.3, 2.1, 1.6, 0.9);
uniform int grid_count : hint_range(1, 4) = 4;
uniform int mask_mode : hint_range(0, 2) = 0;
// 0 = projected-grid top, 1 = projected-grid underside, 2 = ocean bottom.
uniform float top_mask_value = 0.25;
uniform float underside_mask_value = 0.5;
uniform float bottom_mask_value = 1.0;

void vertex() {
	if (mask_mode < 2) {
		vec2 uv0 = UV;
		vec2 uv1 = UV * (grid_sizes.x / grid_sizes.y);
		vec2 uv2 = UV * (grid_sizes.x / grid_sizes.z);
		vec2 uv3 = UV * (grid_sizes.x / grid_sizes.w);
		VERTEX += textureLod(displacement_grid_0, uv0, 0.0).xyz * choppiness.x;
		if (grid_count > 1) VERTEX += textureLod(displacement_grid_1, uv1, 0.0).xyz * choppiness.y;
		if (grid_count > 2) VERTEX += textureLod(displacement_grid_2, uv2, 0.0).xyz * choppiness.z;
		if (grid_count > 3) VERTEX += textureLod(displacement_grid_3, uv3, 0.0).xyz * choppiness.w;
	}
}

void fragment() {
	float mask_value = top_mask_value;
	if (mask_mode == 1) mask_value = underside_mask_value;
	if (mask_mode == 2) mask_value = bottom_mask_value;
	// R stores the Ceto mask class; G stores the current depth-buffer value.
	ALBEDO = vec3(mask_value, FRAGCOORD.z, 0.0);
	ALPHA = 1.0;
	ROUGHNESS = 1.0;
}
