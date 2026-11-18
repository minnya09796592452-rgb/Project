shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
uniform sampler2D scene_depth_texture : hint_depth_texture, filter_nearest;
uniform sampler2D ocean_mask_texture : filter_nearest, repeat_disable;
uniform sampler2D caustics_texture : filter_linear, repeat_enable;

uniform float top_mask_value = 0.25;
uniform vec3 absorption_coefficient = vec3(0.22, 0.09, 0.045);
uniform vec3 underwater_tint : source_color = vec3(0.015, 0.19, 0.24);
uniform float maximum_depth_distance = 80.0;
uniform float caustics_scale = 0.08;
uniform float caustics_strength : hint_range(0.0, 2.0) = 0.25;
uniform float animation_time = 0.0;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec3 source_color = texture(screen_texture, uv).rgb;
	vec4 mask = texture(ocean_mask_texture, uv);
	float is_underwater = mask.r > top_mask_value + 0.01 ? 1.0 : 0.0;

	float raw_depth = texture(scene_depth_texture, uv).r;
	vec4 clip_position = vec4(uv * 2.0 - 1.0, raw_depth, 1.0);
	vec4 view_position = INV_PROJECTION_MATRIX * clip_position;
	view_position /= max(abs(view_position.w), 0.00001);
	vec3 world_position = (INV_VIEW_MATRIX * view_position).xyz;
	float distance_to_camera = min(length(world_position - CAMERA_POSITION_WORLD), maximum_depth_distance);

	vec3 transmission = exp(-absorption_coefficient * distance_to_camera);
	vec3 absorbed_color = source_color * transmission + underwater_tint * (1.0 - transmission);

	float caustics = texture(caustics_texture, world_position.xz * caustics_scale + vec2(animation_time * 0.025, animation_time * 0.017)).r;
	absorbed_color += caustics * caustics_strength * transmission;

	ALBEDO = mix(source_color, absorbed_color, is_underwater);
	ALPHA = 1.0;
}
