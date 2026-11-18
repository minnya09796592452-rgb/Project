shader_type canvas_item;
render_mode unshaded, blend_disabled;

uniform sampler2D camera_depth_normals_texture : filter_nearest, repeat_disable;
uniform mat3 view_to_world = mat3(1.0);

void fragment() {
	vec3 view_normal = textureLod(camera_depth_normals_texture, UV, 0.0).rgb * 2.0 - 1.0;
	vec3 world_normal = normalize(view_to_world * view_normal);
	float fade = max(0.0, dot(vec3(0.0, 1.0, 0.0), world_normal));
	COLOR = vec4(fade, 0.0, 0.0, 1.0);
}
