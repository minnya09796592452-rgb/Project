shader_type canvas_item;
render_mode unshaded, blend_disabled;

uniform sampler2D overlay_height : filter_linear, repeat_disable;
uniform sampler2D overlay_height_mask : filter_linear, repeat_disable;
uniform sampler2D overlay_normal : filter_linear, repeat_disable;
uniform sampler2D overlay_normal_mask : filter_linear, repeat_disable;
uniform sampler2D overlay_foam : filter_linear, repeat_disable;
uniform sampler2D overlay_foam_mask : filter_linear, repeat_disable;
uniform sampler2D overlay_clip : filter_linear, repeat_disable;

uniform mat3 mask_uv_transform = mat3(1.0);
uniform mat3 overlay_rotation = mat3(1.0);
uniform float overlay_alpha : hint_range(0.0, 1.0) = 1.0;
uniform float overlay_mask_alpha : hint_range(0.0, 1.0) = 1.0;
uniform int overlay_mask_mode : hint_range(0, 3) = 0;
uniform vec2 texture_foam = vec2(1.0, 1.0);
uniform int output_mode : hint_range(0, 5) = 0;

float apply_mask(float value, inout float mask_value) {
	if (overlay_mask_mode == 0) return value * overlay_alpha;
	if (overlay_mask_mode == 1) {
		float result = value * overlay_alpha * mask_value;
		mask_value = 0.0;
		return result;
	}
	if (overlay_mask_mode == 2) return value * overlay_alpha * (1.0 - mask_value);
	return value * overlay_alpha * mask_value;
}

vec3 apply_mask(vec3 value, inout float mask_value) {
	if (overlay_mask_mode == 0) return value * overlay_alpha;
	if (overlay_mask_mode == 1) {
		vec3 result = value * overlay_alpha * mask_value;
		mask_value = 0.0;
		return result;
	}
	if (overlay_mask_mode == 2) return value * overlay_alpha * (1.0 - mask_value);
	return value * overlay_alpha * mask_value;
}

void fragment() {
	vec2 mask_uv = (mask_uv_transform * vec3(UV, 1.0)).xy;
	if (output_mode == 0 || output_mode == 4) {
		float height_value = texture(overlay_height, UV).a;
		float mask_value = clamp(texture(overlay_height_mask, mask_uv).a * overlay_mask_alpha, 0.0, 1.0);
		height_value = apply_mask(height_value, mask_value);
		COLOR = vec4(height_value, mask_value, 0.0, 0.0);
	} else if (output_mode == 1) {
		vec3 normal_value = texture(overlay_normal, UV).rgb * 2.0 - 1.0;
		normal_value = normal_value.xzy;
		float mask_value = clamp(texture(overlay_normal_mask, mask_uv).a * overlay_mask_alpha, 0.0, 1.0);
		normal_value = apply_mask(normal_value, mask_value);
		normal_value = overlay_rotation * normal_value;
		COLOR = vec4(normal_value, mask_value);
	} else if (output_mode == 2 || output_mode == 5) {
		float foam_value = texture(overlay_foam, UV).a;
		float mask_value = clamp(texture(overlay_foam_mask, mask_uv).a * overlay_mask_alpha, 0.0, 1.0);
		foam_value = apply_mask(foam_value, mask_value);
		COLOR = vec4(foam_value * texture_foam, 0.0, mask_value);
	} else {
		float clip_value = texture(overlay_clip, UV).a;
		COLOR = vec4(clip_value, 0.0, 0.0, 0.0);
	}
}
