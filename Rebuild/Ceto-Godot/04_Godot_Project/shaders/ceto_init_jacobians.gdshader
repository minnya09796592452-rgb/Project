shader_type canvas_item;
render_mode unshaded, blend_disabled;

// Ceto 1.1.4 InitJacobians.shader translated to single-target passes.
// output_index selects the Unity MRT attachment (0, 1, or 2).
uniform sampler2D spectrum_01 : filter_nearest, repeat_disable;
uniform sampler2D spectrum_23 : filter_nearest, repeat_disable;
uniform sampler2D wtable : filter_nearest, repeat_disable;
uniform vec2 mirror_offset = vec2(1.0, 1.0);
uniform vec4 inverse_grid_sizes = vec4(1.0);
uniform float time_value = 0.0;
uniform float foam_amount = 1.0;
uniform int grid_count : hint_range(1, 4) = 4;
uniform int output_index : hint_range(0, 2) = 0;

vec2 get_spectrum(float omega, vec2 s0, vec2 s0c) {
	float phase = omega * time_value;
	float c = cos(phase);
	float s = sin(phase);
	return vec2(
		(s0.x + s0c.x) * c - (s0.y + s0c.y) * s,
		(s0.x - s0c.x) * s + (s0.y - s0c.y) * c
	);
}

vec3 jacobian_terms(vec2 k, float height_real) {
	float magnitude = length(k);
	float inverse_magnitude = magnitude == 0.0 ? 0.0 : 1.0 / magnitude;
	float scale = -height_real * foam_amount * inverse_magnitude;
	return vec3(k.x * k.x, k.y * k.y, k.x * k.y) * scale;
}

void fragment() {
	vec2 uv = UV;
	vec2 st = vec2(uv.x > 0.5 ? uv.x - 1.0 : uv.x,
				   uv.y > 0.5 ? uv.y - 1.0 : uv.y);
	vec2 mirrored_uv = mirror_offset - uv;

	vec4 s12 = textureLod(spectrum_01, uv, 0.0) * foam_amount;
	vec4 s12c = textureLod(spectrum_01, mirrored_uv, 0.0) * foam_amount;
	vec4 s34 = textureLod(spectrum_23, uv, 0.0) * foam_amount;
	vec4 s34c = textureLod(spectrum_23, mirrored_uv, 0.0) * foam_amount;
	vec4 w = textureLod(wtable, uv, 0.0);

	vec2 k1 = st * inverse_grid_sizes.x;
	vec2 h1 = get_spectrum(w.x, s12.xy, s12c.xy);
	vec3 j1 = jacobian_terms(k1, h1.x);

	if (grid_count == 1) {
		COLOR = vec4(j1, 0.0);
		return;
	}

	vec2 k2 = st * inverse_grid_sizes.y;
	vec2 h2 = get_spectrum(w.y, s12.zw, s12c.zw);
	vec3 j2 = jacobian_terms(k2, h2.x);

	if (grid_count == 2) {
		COLOR = output_index == 0
			? vec4(j1.x, j2.x, j1.y, j2.y)
			: vec4(j1.z, j2.z, 0.0, 0.0);
		return;
	}

	vec2 k3 = st * inverse_grid_sizes.z;
	vec2 h3 = get_spectrum(w.z, s34.xy, s34c.xy);
	vec3 j3 = jacobian_terms(k3, h3.x);

	if (grid_count == 3) {
		if (output_index == 0) {
			COLOR = vec4(j1.x, j2.x, j3.x, 0.0);
		} else if (output_index == 1) {
			COLOR = vec4(j1.y, j2.y, j3.y, 0.0);
		} else {
			COLOR = vec4(j1.z, j2.z, j3.z, 0.0);
		}
		return;
	}

	vec2 k4 = st * inverse_grid_sizes.w;
	vec2 h4 = get_spectrum(w.w, s34.zw, s34c.zw);
	vec3 j4 = jacobian_terms(k4, h4.x);

	if (output_index == 0) {
		COLOR = vec4(j1.x, j2.x, j3.x, j4.x);
	} else if (output_index == 1) {
		COLOR = vec4(j1.y, j2.y, j3.y, j4.y);
	} else {
		COLOR = vec4(j1.z, j2.z, j3.z, j4.z);
	}
}
