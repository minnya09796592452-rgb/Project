shader_type canvas_item;
render_mode unshaded, blend_disabled;

uniform sampler2D camera_depth_texture : filter_nearest, repeat_disable;

void fragment() {
	float depth_value = textureLod(camera_depth_texture, UV, 0.0).r;
	COLOR = vec4(vec3(depth_value), 1.0);
}
