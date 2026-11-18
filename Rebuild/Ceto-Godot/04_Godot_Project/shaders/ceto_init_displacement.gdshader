shader_type canvas_item;
render_mode unshaded, blend_disabled;

// Ceto 1.1.4 InitDisplacement.shader translated to single-target Godot passes.
uniform sampler2D spectrum_01 : filter_nearest, repeat_disable;
uniform sampler2D spectrum_23 : filter_nearest, repeat_disable;
uniform sampler2D wtable : filter_nearest, repeat_disable;
uniform vec2 mirror_offset = vec2(1.0, 1.0);
uniform vec4 inverse_grid_sizes = vec4(1.0);
uniform float time_value = 0.0;
uniform int grid_count : hint_range(1, 4) = 4;
uniform int output_index : hint_range(0, 2) = 0;

vec2 complex_i(vec2 z) {
	return vec2(-z.y, z.x);
}

vec2 get_spectrum(float omega, vec2 s0, vec2 s0c) {
	float phase = omega * time_value;
	float c = cos(phase);
	float s = sin(phase);
	return vec2(
		(s0.x + s0c.x) * c - (s0.y + s0c.y) * s,
		(s0.x - s0c.x) * s + (s0.y - s0c.y) * c
	);
}

vec2 displacement_term(vec2 k, vec2 h) {
	return complex_i(k.x * h) - k.y * h;
}

float inverse_length(vec2 k) {
	float magnitude = length(k);
	return magnitude == 0.0 ? 0.0 : 1.0 / magnitude;
}

void fragment() {
	vec2 uv = UV;
	vec2 st = vec2(uv.x > 0.5 ? uv.x - 1.0 : uv.x, uv.y > 0.5 ? uv.y - 1.0 : uv.y);
	vec2 mirrored_uv = mirror_offset - uv;

	vec4 s12 = textureLod(spectrum_01, uv, 0.0);
	vec4 s12c = textureLod(spectrum_01, mirrored_uv, 0.0);
	vec4 s34 = textureLod(spectrum_23, uv, 0.0);
	vec4 s34c = textureLod(spectrum_23, mirrored_uv, 0.0);
	vec4 w = textureLod(wtable, uv, 0.0);

	vec2 k1 = st * inverse_grid_sizes.x;
	vec2 h1 = get_spectrum(w.x, s12.xy, s12c.xy);
	vec2 n1 = displacement_term(k1, h1);
	float ik1 = inverse_length(k1);

	vec2 k2 = st * inverse_grid_sizes.y;
	vec2 h2 = get_spectrum(w.y, s12.zw, s12c.zw);
	vec2 n2 = displacement_term(k2, h2);
	float ik2 = inverse_length(k2);

	vec2 k3 = st * inverse_grid_sizes.z;
	vec2 h3 = get_spectrum(w.z, s34.xy, s34c.xy);
	vec2 n3 = displacement_term(k3, h3);
	float ik3 = inverse_length(k3);

	vec2 k4 = st * inverse_grid_sizes.w;
	vec2 h4 = get_spectrum(w.w, s34.zw, s34c.zw);
	vec2 n4 = displacement_term(k4, h4);
	float ik4 = inverse_length(k4);

	if (grid_count == 1) {
		COLOR = vec4(h1, n1 * ik1);
	} else if (grid_count == 2) {
		if (output_index == 0) COLOR = vec4(h1 + complex_i(h2), 0.0, 0.0);
		else COLOR = vec4(n1 * ik1, n2 * ik2);
	} else if (grid_count == 3) {
		if (output_index == 0) COLOR = vec4(h1 + complex_i(h2), h3);
		else if (output_index == 1) COLOR = vec4(n1 * ik1, n2 * ik2);
		else COLOR = vec4(n3 * ik3, 0.0, 0.0);
	} else {
		if (output_index == 0) COLOR = vec4(h1 + complex_i(h2), h3 + complex_i(h4));
		else if (output_index == 1) COLOR = vec4(n1 * ik1, n2 * ik2);
		else COLOR = vec4(n3 * ik3, n4 * ik4);
	}
}
