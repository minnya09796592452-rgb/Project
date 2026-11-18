shader_type canvas_item;
render_mode unshaded, blend_disabled;

uniform sampler2D source_texture : filter_linear, repeat_disable;
uniform vec2 source_texel_size = vec2(0.001953125, 0.001953125);
uniform vec2 blur_offsets = vec2(1.0, 1.0);

void fragment() {
	vec2 base_uv = UV - blur_offsets * source_texel_size;
	vec2 offset = blur_offsets * source_texel_size;
	vec4 color = textureLod(source_texture, base_uv + offset, 0.0);
	color += textureLod(source_texture, base_uv - offset, 0.0);
	color += textureLod(source_texture, base_uv + offset * vec2(1.0, -1.0), 0.0);
	color += textureLod(source_texture, base_uv - offset * vec2(1.0, -1.0), 0.0);
	COLOR = max(color * 0.25, vec4(0.0));
}
