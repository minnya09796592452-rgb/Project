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
