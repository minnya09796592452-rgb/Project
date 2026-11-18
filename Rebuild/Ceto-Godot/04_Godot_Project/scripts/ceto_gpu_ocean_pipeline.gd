extends RefCounted
class_name CetoGpuOceanPipeline

## GPU-side spectrum-to-displacement initialization.
## Uses the translated Ceto InitDisplacement shader through the generic
## single-target scheduler. CPU CetoDisplacement.initialize remains the oracle.

const CetoGpuPassRunner = preload("res://scripts/ceto_gpu_pass_runner.gd")
const INIT_DISPLACEMENT_SHADER = preload("res://shaders/ceto_init_displacement.gdshader")


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
	var spectrum01: PackedVector4Array = spectrum_data["spectrum01"]
	var spectrum23: PackedVector4Array = spectrum_data["spectrum23"]
	var wtable: PackedVector4Array = spectrum_data["wtable"]
	if spectrum23.is_empty():
		spectrum23.resize(size * size)

	var spectrum01_texture := CetoGpuPassRunner.texture_from_packed_vector4(spectrum01, size)
	var spectrum23_texture := CetoGpuPassRunner.texture_from_packed_vector4(spectrum23, size)
	var wtable_texture := CetoGpuPassRunner.texture_from_packed_vector4(wtable, size)
	var inverse_grid_sizes := Vector4(
		TAU * float(size) / grid_sizes.x,
		TAU * float(size) / grid_sizes.y,
		TAU * float(size) / grid_sizes.z,
		TAU * float(size) / grid_sizes.w
	)
	var output_count := 1 if grid_count == 1 else (2 if grid_count == 2 else 3)
	var outputs: Array[Texture2D] = []

	for output_index in range(output_count):
		var uniforms := {
			"spectrum_01": spectrum01_texture,
			"spectrum_23": spectrum23_texture,
			"wtable": wtable_texture,
			"mirror_offset": Vector2(1.0 + 0.5 / float(size), 1.0 + 0.5 / float(size)),
			"inverse_grid_sizes": inverse_grid_sizes,
			"time_value": time_value,
			"grid_count": grid_count,
			"output_index": output_index
		}
		outputs.append(await runner.render_single_target_pass(
			INIT_DISPLACEMENT_SHADER, size, uniforms, spectrum01_texture
		))

	return {
		"displacement_textures": outputs,
		"spectrum01_texture": spectrum01_texture,
		"spectrum23_texture": spectrum23_texture,
		"wtable_texture": wtable_texture
	}
