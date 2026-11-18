extends SceneTree

const CetoGpuPassRunner = preload("res://scripts/ceto_gpu_pass_runner.gd")
const CetoGpuOceanPipeline = preload("res://scripts/ceto_gpu_ocean_pipeline.gd")
const TOLERANCE := 0.02


func _compare(texture: Texture2D, expected: PackedVector4Array, size: int, label: String) -> float:
	if texture == null:
		push_error("%s: missing output texture" % label)
		return INF
	var image := texture.get_image()
	if image == null or image.get_width() != size or image.get_height() != size:
		push_error("%s: output dimensions invalid" % label)
		return INF
	var max_error := 0.0
	for y in range(size):
		for x in range(size):
			var index := x + y * size
			var pixel := image.get_pixel(x, y)
			var actual := Vector4(pixel.r, pixel.g, pixel.b, pixel.a)
			for channel in range(4):
				max_error = maxf(max_error, absf(actual[channel] - expected[index][channel]))
	if max_error > TOLERANCE:
		push_error("%s: max error %.6f > %.6f" % [label, max_error, TOLERANCE])
	return max_error


func _run_test() -> void:
	var size := 8
	var height_values := PackedVector4Array()
	var displacement_values := PackedVector4Array()
	var slope_values := PackedVector4Array()
	var j0_values := PackedVector4Array()
	var j1_values := PackedVector4Array()
	var j2_values := PackedVector4Array()
	for index in range(size * size):
		var f := float(index) / float(size * size)
		height_values.append(Vector4(0.1 + f * 0.05, 0.2 + f * 0.03, 0.3 + f * 0.02, 0.4 + f * 0.01))
		displacement_values.append(Vector4(0.01 + f * 0.01, 0.02 + f * 0.01, 0.03 + f * 0.01, 0.04 + f * 0.01))
		slope_values.append(Vector4(0.05 + f * 0.01, 0.06 + f * 0.01, 0.07 + f * 0.01, 0.08 + f * 0.01))
		j0_values.append(Vector4(0.01 + f * 0.01, 0.02 + f * 0.01, 0.03 + f * 0.01, 0.04 + f * 0.01))
		j1_values.append(Vector4(0.015 + f * 0.005, 0.025 + f * 0.005, 0.035 + f * 0.005, 0.045 + f * 0.005))
		j2_values.append(Vector4(0.005 + f * 0.002, 0.006 + f * 0.002, 0.007 + f * 0.002, 0.008 + f * 0.002))

	var height_texture := CetoGpuPassRunner.texture_from_packed_vector4(height_values, size)
	var displacement_texture := CetoGpuPassRunner.texture_from_packed_vector4(displacement_values, size)
	var slope_texture := CetoGpuPassRunner.texture_from_packed_vector4(slope_values, size)
	var j0_texture := CetoGpuPassRunner.texture_from_packed_vector4(j0_values, size)
	var j1_texture := CetoGpuPassRunner.texture_from_packed_vector4(j1_values, size)
	var j2_texture := CetoGpuPassRunner.texture_from_packed_vector4(j2_values, size)

	var runner := CetoGpuPassRunner.new()
	root.add_child(runner)
	await process_frame
	var pipeline := CetoGpuOceanPipeline.new()
	var passed := true
	var max_error := 0.0

	var slope_copy := await pipeline.copy_slope(runner, slope_texture, size)
	var error := _compare(slope_copy, slope_values, size, "SlopeCopy")
	max_error = maxf(max_error, error)
	passed = passed and error <= TOLERANCE

	runner.release_targets()
	await process_frame
	for grid in range(4):
		var compact := false
		var output: Texture2D = await pipeline.copy_displacement(
			runner, height_texture, displacement_texture, size, grid, compact
		)
		var expected := PackedVector4Array()
		expected.resize(size * size)
		for index in range(size * size):
			var height := height_values[index][grid]
			var displacement := displacement_values[index]
			var horizontal := Vector2(displacement.x, displacement.y) if grid == 0 or grid == 2 else Vector2(displacement.z, displacement.w)
			expected[index] = Vector4(horizontal.x, height, horizontal.y, 0.0)
		error = _compare(output, expected, size, "DisplacementCopy grid %d" % grid)
		max_error = maxf(max_error, error)
		passed = passed and error <= TOLERANCE

	runner.release_targets()
	await process_frame
	var choppiness := Vector4(0.5, 0.6, 0.7, 0.8)
	var foam_coverage := 0.1
	var foam_output: Texture2D = await pipeline.compose_foam(
		runner, [j0_texture, j1_texture, j2_texture], size, 4, choppiness, foam_coverage
	)
	var foam_expected := PackedVector4Array()
	foam_expected.resize(size * size)
	for index in range(size * size):
		var values := Vector4.ZERO
		for channel in range(4):
			var jxx := choppiness[channel] * j0_values[index][channel]
			var jyy := choppiness[channel] * j1_values[index][channel]
			var jxy := choppiness[channel] * choppiness[channel] * j2_values[index][channel]
			values[channel] = foam_coverage + jxx + jyy + choppiness[channel] * jxx * jyy - jxy * jxy
		foam_expected[index] = values
	error = _compare(foam_output, foam_expected, size, "FoamCopy")
	max_error = maxf(max_error, error)
	passed = passed and error <= TOLERANCE

	if passed:
		print("CETO GPU COPY: PASS (6 passes, max error %.6f)" % max_error)
	runner.release_targets()
	runner.queue_free()
	quit(0 if passed else 1)


func _initialize() -> void:
	await _run_test()
