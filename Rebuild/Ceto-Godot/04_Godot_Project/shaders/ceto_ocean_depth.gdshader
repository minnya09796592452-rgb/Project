shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

uniform float ocean_level = 0.0;
uniform float maximum_depth_distance = 100.0;
uniform sampler2D albedo_texture : source_color, filter_linear, repeat_enable;
uniform bool use_alpha_cutout = false;
uniform float alpha_cutoff : hint_range(0.0, 1.0) = 0.5;

void fragment() {
	vec3 world_position = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float relative_depth = clamp((ocean_level - world_position.y) / maximum_depth_distance, -1.0, 1.0);
	float camera_distance = length(world_position - CAMERA_POSITION_WORLD);
	float normalized_distance = clamp(camera_distance / maximum_depth_distance, 0.0, 1.0);
	if (use_alpha_cutout && texture(albedo_texture, UV).a < alpha_cutoff) {
		discard;
	}
	ALBEDO = vec3(relative_depth * 0.5 + 0.5, normalized_distance, 0.0);
	ALPHA = 1.0;
}
