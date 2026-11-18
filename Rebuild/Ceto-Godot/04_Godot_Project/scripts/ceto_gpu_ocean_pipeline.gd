extends RefCounted
class_name CetoGpuOceanPipeline

## GPU-side Ceto spectrum initialization passes. CPU CetoDisplacement remains
## the reference implementation; each Unity MRT attachment is rendered as a
## separate Godot SubViewport pass.

const CetoGpuPassRunner = preload("res://scripts/ceto_gpu_pass_runner.gd")
const INIT_DISPLACEMENT_SHADER = preload("res://shaders/ceto_init_displacement.gdshader")
const INIT_SLOPE_SHADER = preload("res://shaders/ceto_init_slope.gdshader")
const INIT_JACOBIANS_SHADER = preload("res://shaders/ceto_init_jacobians.gdshader")


func _prepare_inputs(
	spectrum_data: Dictionary,
	size: int,
	grid_sizes: Vector4
) -> Dictionary:
	var spectrum01: PackedVector4Array = spectrum_data["spectrum01"]
	var spectrum23: PackedVector4Array = spectrum_data["spectrum23"]
	var wtable: PackedVector4Array = spectrum_data["wtable"]
	if spectrum23.is_empty():
		spectrum23.resize(size * size)
	return {
		"spectrum01": CetoGpuPassRunner.texture_from_packed_vector4(spectrum01, size),
		"spectrum23": CetoGpuPassRunner.texture_from_packed_vector4(spectrum23, size),
		"wtable": CetoGpuPassRunner.texture_from_packed_vector4(wtable, size),
		"mirror_offset": Vector2(1.0 + 0.5 / float(size), 1.0 + 0.5 / float(size)),
		"inverse_grid_sizes": Vector4(
			TAU * float(size) / grid_sizes.x,
			TAU * float(size) / grid_sizes.y,
			TAU * float(size) / grid_sizes.z,
			TAU * float(size) / grid_sizes.w
		)
	}


func _render_outputs(
	runner: CetoGpuPassRunner,
	shader: Shader,
	inputs: Dictionary,
	size: int,
	grid_count: int,
	time_value: float,
	output_count: int,
	extra_uniforms: Dictionary = {}
) -> Array[Texture2D]:
	var outputs: Array[Texture2D] = []
	for output_index in range(output_count):
		var uniforms := {
			"spectrum_01": inputs["spectrum01"],
			"spectrum_23": inputs["spectrum23"],
			"wtable": inputs["wtable"],
			"mirror_offset": inputs["mirror_offset"],
			"inverse_grid_sizes": inputs["inverse_grid_sizes"],
			"time_value": time_value,
			"grid_count": grid_count,
			"output_index": output_index
		}
		for key in extra_uniforms:
			uniforms[key] = extra_uniforms[key]
		outputs.append(await runner.render_single_target_pass(
			shader, size, uniforms, inputs["spectrum01"]
		))
	return outputs


func initialize_displacement(
	runner: CetoGpuPassRunner,
	spectrum_data: Dictionary,
	size: int,
	grid_sizes: Vector4,
	grid_count: int,
	time_value: float
) -> Dictionary:
	assert(grid_count >= 1 and grid_count <= 4, "Ceto supports one through four grids")
	assert(size > 0, "Spectrum size must be positive")
	var inputs := _prepare_inputs(spectrum_data, size, grid_sizes)
	var output_count := 1 if grid_count == 1 else (2 if grid_count == 2 else 3)
	var outputs := await _render_outputs(
		runner, INIT_DISPLACEMENT_SHADER, inputs, size, grid_count, time_value, output_count
	)
	return {"displacement_textures": outputs, "inputs": inputs}


func initialize_slopes(
	runner: CetoGpuPassRunner,
	spectrum_data: Dictionary,
	size: int,
	grid_sizes: Vector4,
	grid_count: int,
	time_value: float
) -> Dictionary:
	assert(grid_count >= 1 and grid_count <= 4, "Ceto supports one through four grids")
	var inputs := _prepare_inputs(spectrum_data, size, grid_sizes)
	var output_count := 1 if grid_count <= 2 else 2
	var outputs := await _render_outputs(
		runner, INIT_SLOPE_SHADER, inputs, size, grid_count, time_value, output_count
	)
	return {"slope_textures": outputs, "inputs": inputs}


func initialize_jacobians(
	runner: CetoGpuPassRunner,
	spectrum_data: Dictionary,
	size: int,
	grid_sizes: Vector4,
	grid_count: int,
	time_value: float,
	foam_amount: float = 1.0
) -> Dictionary:
	assert(grid_count >= 1 and grid_count <= 4, "Ceto supports one through four grids")
	var inputs := _prepare_inputs(spectrum_data, size, grid_sizes)
	var output_count := 1 if grid_count == 1 else (2 if grid_count == 2 else 3)
	var outputs := await _render_outputs(
		runner, INIT_JACOBIANS_SHADER, inputs, size, grid_count, time_value,
		output_count, {"foam_amount": foam_amount}
	)
	return {"jacobian_textures": outputs, "inputs": inputs}



func copy_displacement(
	runner: CetoGpuPassRunner,
	height_buffer: Texture2D,
	displacement_buffer: Texture2D,
	size: int,
	grid_index: int,
	compact_single_grid: bool = false
) -> Texture2D:
	var shader: Shader = preload("res://shaders/ceto_displacement_copy.gdshader")
	var uniforms := {
		"height_buffer": height_buffer,
		"displacement_buffer": displacement_buffer,
		"grid_index": grid_index,
		"compact_single_grid": compact_single_grid
	}
	return await runner.render_single_target_pass(shader, size, uniforms, height_buffer)


func copy_slope(
	runner: CetoGpuPassRunner,
	slope_buffer: Texture2D,
	size: int
) -> Texture2D:
	var shader: Shader = preload("res://shaders/ceto_slope_copy.gdshader")
	return await runner.render_single_target_pass(
		shader, size, {"slope_buffer": slope_buffer}, slope_buffer
	)


func compose_foam(
	runner: CetoGpuPassRunner,
	jacobian_buffers: Array[Texture2D],
	size: int,
	grid_count: int,
	foam_choppiness: Vector4,
	foam_coverage: float
) -> Texture2D:
	assert(grid_count >= 1 and grid_count <= 4, "Ceto supports one through four grids")
	assert(not jacobian_buffers.is_empty(), "At least one Jacobian buffer is required")
	var zero_values := PackedVector4Array()
	zero_values.resize(size * size)
	var zero_texture := CetoGpuPassRunner.texture_from_packed_vector4(zero_values, size)
	var j0: Texture2D = jacobian_buffers[0]
	var j1: Texture2D = jacobian_buffers[1] if jacobian_buffers.size() > 1 else zero_texture
	var j2: Texture2D = jacobian_buffers[2] if jacobian_buffers.size() > 2 else zero_texture
	var shader: Shader = preload("res://shaders/ceto_foam_copy.gdshader")
	var uniforms := {
		"jacobian_buffer_0": j0,
		"jacobian_buffer_1": j1,
		"jacobian_buffer_2": j2,
		"foam_choppiness": foam_choppiness,
		"foam_coverage": foam_coverage,
		"grid_count": grid_count
	}
	return await runner.render_single_target_pass(shader, size, uniforms, j0)



func update_gpu_ocean(
	runner: CetoGpuPassRunner,
	spectrum_data: Dictionary,
	size: int,
	grid_sizes: Vector4,
	grid_count: int,
	time_value: float,
	foam_choppiness: Vector4,
	foam_coverage: float = 0.0,
	foam_amount: float = 1.0
) -> Dictionary:
	# Frequency-domain initialization and two-dimensional inverse transforms.
	var displacement_init := await initialize_displacement(
		runner, spectrum_data, size, grid_sizes, grid_count, time_value
	)
	var displacement_fft: Array[Texture2D] = await runner.transform_packed_textures(
		displacement_init["displacement_textures"], size
	)

	var slope_init := await initialize_slopes(
		runner, spectrum_data, size, grid_sizes, grid_count, time_value
	)
	var slope_fft: Array[Texture2D] = await runner.transform_packed_textures(
		slope_init["slope_textures"], size
	)

	var jacobian_init := await initialize_jacobians(
		runner, spectrum_data, size, grid_sizes, grid_count, time_value, foam_amount
	)
	var jacobian_fft: Array[Texture2D] = await runner.transform_packed_textures(
		jacobian_init["jacobian_textures"], size
	)
	var foam_texture := await compose_foam(
		runner, jacobian_fft, size, grid_count, foam_choppiness, foam_coverage
	)

	var grid_displacements: Array[Texture2D] = []
	for grid in range(grid_count):
		var displacement_buffer: Texture2D
		if grid_count == 1:
			displacement_buffer = displacement_fft[0]
		elif grid < 2:
			displacement_buffer = displacement_fft[1]
		else:
			displacement_buffer = displacement_fft[2]
		grid_displacements.append(await copy_displacement(
			runner,
			displacement_fft[0],
			displacement_buffer,
			size,
			grid,
			grid_count == 1
		))

	return {
		"displacement_textures": grid_displacements,
		"slope_textures": slope_fft,
		"jacobian_textures": jacobian_fft,
		"foam_texture": foam_texture
	}
