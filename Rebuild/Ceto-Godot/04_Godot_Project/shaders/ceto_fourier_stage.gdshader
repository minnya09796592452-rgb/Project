shader_type canvas_item;
render_mode unshaded, blend_disabled;

// Single-target Godot translation of Ceto 1.1.4 Fourier.shader.
// Run once per logical data texture and per axis/stage. The Unity source uses
// MRT for 2-4 buffers; this Godot variant intentionally uses one output per draw.

uniform sampler2D read_buffer : source_color, filter_nearest, repeat_disable;
uniform sampler2D butterfly_lookup : filter_nearest, repeat_disable;
uniform bool axis_y = false;

vec4 fft_butterfly(vec2 twiddle, vec4 input_a, vec4 input_b) {
	vec2 b0 = vec2(
		twiddle.x * input_b.x - twiddle.y * input_b.y,
		twiddle.y * input_b.x + twiddle.x * input_b.y
	);
	vec2 b1 = vec2(
		twiddle.x * input_b.z - twiddle.y * input_b.w,
		twiddle.y * input_b.z + twiddle.x * input_b.w
	);
	return input_a + vec4(b0, b1);
}

void fragment() {
	float lookup_coordinate = axis_y ? UV.y : UV.x;
	vec4 lookup = textureLod(butterfly_lookup, vec2(lookup_coordinate, 0.5), 0.0);
	vec2 uv_a;
	vec2 uv_b;

	if (axis_y) {
		uv_a = vec2(UV.x, lookup.x);
		uv_b = vec2(UV.x, lookup.y);
	} else {
		uv_a = vec2(lookup.x, UV.y);
		uv_b = vec2(lookup.y, UV.y);
	}

	vec4 input_a = textureLod(read_buffer, uv_a, 0.0);
	vec4 input_b = textureLod(read_buffer, uv_b, 0.0);
	COLOR = fft_butterfly(lookup.zw, input_a, input_b);
}
