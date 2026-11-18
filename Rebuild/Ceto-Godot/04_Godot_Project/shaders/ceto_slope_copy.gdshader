shader_type canvas_item;
render_mode unshaded, blend_disabled;

// Ceto 1.1.4 SlopeCopy.shader: direct filtered texture copy.
uniform sampler2D slope_buffer : filter_nearest, repeat_disable;

void fragment() {
	COLOR = textureLod(slope_buffer, UV, 0.0);
}
