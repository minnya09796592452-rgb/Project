extends Node
class_name CetoGpuPassRunner

## Sequential single-target scheduler for Ceto's GPU passes.
## Unity MRT outputs are executed as independent passes. Each pass writes to
## a fresh SubViewport, preventing read/write feedback.
## Forward+/Mobile HDR 2D targets preserve values in a 16-bit float buffer.
## Compatibility rendering ignores HDR 2D and has no RenderingDevice; GPU
## numeric parity is skipped there. The CPU path remains the reference.

const CetoFourier = preload("res://scripts/ceto_fourier.gd")
const FOURIER_STAGE_SHADER = preload("res://shaders/ceto_fourier_stage.gdshader")

var _targets: Array[SubViewport] = []
var _last_output: Texture2D
var _running := false
var _last_pass_count := 0


static func texture_from_packed_vector4(values: PackedVector4Array, size: int) -> ImageTexture:
	assert(CetoFourier.is_power_of_two(size), "Ceto texture size must be a power of two")
	assert(values.size() == size * size, "Packed data dimensions do not match size")
	var image := Image.create(size, size, false, Image.FORMAT_RGBAF)
	for y in range(size):
		for x in range(size):
			var value: Vector4 = values[x + y * size]
			image.set_pixel(x, y, Color(value.x, value.y, value.z, value.w))
	return ImageTexture.create_from_image(image)


func _render_pass(
	shader: Shader,
	size: int,
	uniforms: Dictionary,
	canvas_texture: Texture2D
) -> Texture2D:
	assert(shader != null, "A shader resource is required")
	assert(canvas_texture != null, "A canvas texture is required to draw the pass")
	var target := SubViewport.new()
	target.name = "CetoPass_%d" % _targets.size()
	target.size = Vector2i(size, size)
	target.disable_3d = true
	target.transparent_bg = true
	target.use_hdr_2d = true
	target.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	target.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(target)

	var rect := TextureRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.texture = canvas_texture
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE

	var material := ShaderMaterial.new()
	material.shader = shader
	for uniform_name in uniforms:
		material.set_shader_parameter(StringName(uniform_name), uniforms[uniform_name])
	rect.material = material
	target.add_child(rect)

	target.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	_targets.append(target)
	_last_pass_count += 1
	return target.get_texture()


func render_single_target_pass(
	shader: Shader,
	size: int,
	uniforms: Dictionary,
	canvas_texture: Texture2D
) -> Texture2D:
	assert(is_inside_tree(), "Add CetoGpuPassRunner to the SceneTree before rendering")
	assert(not _running, "CetoGpuPassRunner does not allow overlapping passes")
	_running = true
	_last_output = await _render_pass(shader, size, uniforms, canvas_texture)
	_running = false
	return _last_output


func transform_packed_textures(input_textures: Array[Texture2D], size: int) -> Array[Texture2D]:
	assert(is_inside_tree(), "Add CetoGpuPassRunner to the SceneTree before running GPU passes")
	assert(not _running, "CetoGpuPassRunner does not allow overlapping transforms")
	assert(not input_textures.is_empty(), "At least one FFT input texture is required")
	assert(CetoFourier.is_power_of_two(size), "Ceto FFT size must be a power of two")
	for input_texture in input_textures:
		assert(input_texture != null, "FFT input texture is required")
		assert(input_texture.get_width() == size and input_texture.get_height() == size,
			"FFT input texture dimensions must match size")

	_running = true
	_last_pass_count = 0
	var lookup_textures := CetoFourier.create_butterfly_lookup_textures(size)
	var outputs: Array[Texture2D] = []

	# Ceto's MRT variants are scheduled as independent texture pipelines. This
	# preserves their per-buffer result while avoiding a device MRT requirement.
	for input_texture in input_textures:
		var source: Texture2D = input_texture
		# Match FourierGPU.PeformFFT: all X stages, then all Y stages.
		for axis_y in [false, true]:
			for stage_index in range(lookup_textures.size()):
				var uniforms := {
					"read_buffer": source,
					"butterfly_lookup": lookup_textures[stage_index],
					"axis_y": axis_y
				}
				source = await _render_pass(FOURIER_STAGE_SHADER, size, uniforms, source)
		outputs.append(source)

	_last_output = outputs[outputs.size() - 1]
	_running = false
	return outputs


func transform_packed_texture(input_texture: Texture2D, size: int) -> Texture2D:
	var outputs := await transform_packed_textures([input_texture], size)
	return outputs[0]

func get_last_output() -> Texture2D:
	return _last_output


func get_last_pass_count() -> int:
	return _last_pass_count


func release_targets() -> void:
	assert(not _running, "Cannot release render targets during an active pass")
	for target in _targets:
		if is_instance_valid(target):
			target.queue_free()
	_targets.clear()
	_last_output = null
	_last_pass_count = 0
