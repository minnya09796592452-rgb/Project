shader_type canvas_item;
render_mode unshaded, blend_disabled;

uniform sampler2D ocean_mask_texture : filter_nearest, repeat_disable;
uniform float top_mask_value = 0.25;
uniform float empty_mask_value = 0.0;
uniform float bottom_mask_value = 1.0;
uniform float comparison_error = 0.01;

void fragment() {
	vec4 mask = textureLod(ocean_mask_texture, UV, 0.0);
	float is_underwater = mask.r <= top_mask_value + comparison_error ? 0.0 : 1.0;
	float is_ocean_surface = (mask.r > empty_mask_value && mask.r < bottom_mask_value) ? 1.0 : 0.0;
	COLOR = vec4(is_underwater, is_ocean_surface, mask.g, 1.0);
}
