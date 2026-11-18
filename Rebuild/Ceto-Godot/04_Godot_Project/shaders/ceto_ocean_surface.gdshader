shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

uniform sampler2D displacement_grid_0 : filter_linear, repeat_enable;
uniform sampler2D displacement_grid_1 : filter_linear, repeat_enable;
uniform sampler2D displacement_grid_2 : filter_linear, repeat_enable;
uniform sampler2D displacement_grid_3 : filter_linear, repeat_enable;
uniform sampler2D slope_buffer_01 : filter_linear, repeat_enable;
uniform sampler2D slope_buffer_23 : filter_linear, repeat_enable;
uniform sampler2D foam_texture : filter_linear, repeat_enable;

uniform vec4 grid_sizes = vec4(1372.0, 392.0, 28.0, 4.0);
uniform vec4 choppiness = vec4(2.3, 2.1, 1.6, 0.9);
uniform int grid_count : hint_range(1, 4) = 4;
uniform float foam_strength : hint_range(0.0, 4.0) = 1.0;
uniform vec3 deep_water_color : source_color = vec3(0.008, 0.075, 0.12);
uniform vec3 shallow_water_color : source_color = vec3(0.025, 0.28, 0.34);
uniform vec3 foam_color : source_color = vec3(0.82, 0.91, 0.94);
uniform float minimum_fresnel : hint_range(0.0, 1.0) = 0.02;
uniform float fresnel_power : hint_range(0.1, 12.0) = 5.0;
uniform float specular_intensity : hint_range(0.0, 1.0) = 0.45;
uniform vec3 sun_direction = vec3(0.0, 1.0, 0.0);
uniform vec3 subsurface_tint : source_color = vec3(0.12, 0.42, 0.5);
uniform float subsurface_strength : hint_range(0.0, 2.0) = 0.25;
uniform vec3 foam_tint : source_color = vec3(0.82, 0.91, 0.94);
uniform vec3 absorption_coefficient = vec3(0.28, 0.12, 0.06);

void vertex() {
	vec2 uv0 = UV;
	vec2 uv1 = UV * (grid_sizes.x / grid_sizes.y);
	vec2 uv2 = UV * (grid_sizes.x / grid_sizes.z);
	vec2 uv3 = UV * (grid_sizes.x / grid_sizes.w);

	vec4 d0 = textureLod(displacement_grid_0, uv0, 0.0);
	vec4 d1 = textureLod(displacement_grid_1, uv1, 0.0);
	vec4 d2 = textureLod(displacement_grid_2, uv2, 0.0);
	vec4 d3 = textureLod(displacement_grid_3, uv3, 0.0);

	VERTEX += d0.xyz * choppiness.x;
	if (grid_count > 1) VERTEX += d1.xyz * choppiness.y;
	if (grid_count > 2) VERTEX += d2.xyz * choppiness.z;
	if (grid_count > 3) VERTEX += d3.xyz * choppiness.w;

	vec4 s01_0 = textureLod(slope_buffer_01, uv0, 0.0);
	vec4 s01_1 = textureLod(slope_buffer_01, uv1, 0.0);
	vec4 s23_2 = textureLod(slope_buffer_23, uv2, 0.0);
	vec4 s23_3 = textureLod(slope_buffer_23, uv3, 0.0);
	vec2 gradient = vec2(s01_0.x, s01_0.y) * choppiness.x;
	if (grid_count > 1) gradient += vec2(s01_1.z, s01_1.w) * choppiness.y;
	if (grid_count > 2) gradient += vec2(s23_2.x, s23_2.y) * choppiness.z;
	if (grid_count > 3) gradient += vec2(s23_3.z, s23_3.w) * choppiness.w;
	NORMAL = normalize(vec3(-gradient.x, 1.0, -gradient.y));
}

void fragment() {
	vec2 uv0 = UV;
	vec2 uv1 = UV * (grid_sizes.x / grid_sizes.y);
	vec2 uv2 = UV * (grid_sizes.x / grid_sizes.z);
	vec2 uv3 = UV * (grid_sizes.x / grid_sizes.w);
	vec4 foam0 = texture(foam_texture, uv0);
	vec4 foam1 = texture(foam_texture, uv1);
	vec4 foam2 = texture(foam_texture, uv2);
	vec4 foam3 = texture(foam_texture, uv3);
	float foam = max(max(foam0.x, foam1.y), max(foam2.z, foam3.w));
	foam = clamp(foam * foam_strength, 0.0, 1.0);

	vec3 normal_world = normalize(NORMAL);
	vec3 view_direction = normalize(VIEW);
	float fresnel = clamp(
		minimum_fresnel + (1.0 - minimum_fresnel) *
		pow(1.0 - clamp(dot(view_direction, normal_world), 0.0, 1.0), fresnel_power),
		0.0, 1.0
	);
	vec3 water = mix(deep_water_color, shallow_water_color, 0.25 + fresnel * 0.65);

	vec3 sun = normalize(sun_direction);
	float view_up = 1.0 - max(0.0, dot(view_direction, vec3(0.0, 1.0, 0.0)));
	float view_sun = max(0.0, dot(reflect(view_direction, vec3(0.0, 1.0, 0.0)) * -1.0, sun));
	float subsurface = view_up * view_up * view_sun * view_sun * view_sun * view_sun;
	if (sun.y < 0.0) subsurface = 0.0;
	water += subsurface_tint * subsurface * subsurface_strength;

	vec3 foam_surface = foam_tint * foam * exp(-absorption_coefficient * (1.0 - foam));
	ALBEDO = mix(water, foam_surface, foam);
	ROUGHNESS = mix(0.12, 0.78, foam);
	METALLIC = 0.04;
	SPECULAR = specular_intensity;
}
