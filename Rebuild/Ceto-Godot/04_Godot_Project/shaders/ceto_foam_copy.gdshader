shader_type canvas_item;
render_mode unshaded, blend_disabled;

// Ceto 1.1.4 FoamCopy.shader translated to a single-target Godot pass.
uniform sampler2D jacobian_buffer_0 : filter_nearest, repeat_disable;
uniform sampler2D jacobian_buffer_1 : filter_nearest, repeat_disable;
uniform sampler2D jacobian_buffer_2 : filter_nearest, repeat_disable;
uniform vec4 foam_choppiness = vec4(1.0);
uniform float foam_coverage = 0.0;
uniform int grid_count : hint_range(1, 4) = 4;

float foam_value(float jxx, float jyy, float jxy, float chop) {
	return foam_coverage + jxx + jyy + chop * jxx * jyy - jxy * jxy;
}

void fragment() {
	vec4 j0 = textureLod(jacobian_buffer_0, UV, 0.0);
	if (grid_count == 1) {
		float chop = foam_choppiness.x;
		float jxx = chop * j0.x;
		float jyy = chop * j0.y;
		float jxy = chop * chop * j0.z;
		COLOR = vec4(foam_value(jxx, jyy, jxy, chop), 0.0, 0.0, 0.0);
		return;
	}

	if (grid_count == 2) {
		vec2 chop = foam_choppiness.xy;
		vec2 jxx = chop * j0.xy;
		vec2 jyy = chop * j0.zw;
		vec2 jxy = chop * chop * textureLod(jacobian_buffer_1, UV, 0.0).xy;
		vec2 result = vec2(
			foam_coverage + jxx.x + jyy.x + chop.x * jxx.x * jyy.x - jxy.x * jxy.x,
			foam_coverage + jxx.y + jyy.y + chop.y * jxx.y * jyy.y - jxy.y * jxy.y
		);
		COLOR = vec4(result, 0.0, 0.0);
		return;
	}

	if (grid_count == 3) {
		vec3 chop = foam_choppiness.xyz;
		vec3 jxx = chop * textureLod(jacobian_buffer_0, UV, 0.0).xyz;
		vec3 jyy = chop * textureLod(jacobian_buffer_1, UV, 0.0).xyz;
		vec3 jxy = chop * chop * textureLod(jacobian_buffer_2, UV, 0.0).xyz;
		vec3 result = vec3(
			foam_coverage + jxx.x + jyy.x + chop.x * jxx.x * jyy.x - jxy.x * jxy.x,
			foam_coverage + jxx.y + jyy.y + chop.y * jxx.y * jyy.y - jxy.y * jxy.y,
			foam_coverage + jxx.z + jyy.z + chop.z * jxx.z * jyy.z - jxy.z * jxy.z
		);
		COLOR = vec4(result, 0.0);
		return;
	}

	vec4 chop = foam_choppiness;
	vec4 jxx = chop * j0;
	vec4 jyy = chop * textureLod(jacobian_buffer_1, UV, 0.0);
	vec4 jxy = chop * chop * textureLod(jacobian_buffer_2, UV, 0.0);
	vec4 result = vec4(
		foam_coverage + jxx.x + jyy.x + chop.x * jxx.x * jyy.x - jxy.x * jxy.x,
		foam_coverage + jxx.y + jyy.y + chop.y * jxx.y * jyy.y - jxy.y * jxy.y,
		foam_coverage + jxx.z + jyy.z + chop.z * jxx.z * jyy.z - jxy.z * jxy.z,
		foam_coverage + jxx.w + jyy.w + chop.w * jxx.w * jyy.w - jxy.w * jxy.w
	);
	COLOR = result;
}
