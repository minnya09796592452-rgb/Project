extends SceneTree

const CetoSpectrum = preload("res://scripts/ceto_spectrum.gd")
const CetoSpectrumGenerator = preload("res://scripts/ceto_spectrum_generator.gd")
const CetoDisplacement = preload("res://scripts/ceto_displacement.gd")
const CetoGpuPassRunner = preload("res://scripts/ceto_gpu_pass_runner.gd")
const CetoGpuOceanPipeline = preload("res://scripts/ceto_gpu_ocean_pipeline.gd")
const TOLERANCE := 0.04
const FOAM_AMOUNT := 0.7


func _initialize() -> void:
	if RenderingServer.get_rendering_device() == null:
		print("CETO GPU INITIALIZATION: SKIP (Compatibility renderer has no HDR RenderingDevice)")
		quit(0)
		return
	await _run_test()


func _evolve(current: Vector4, mirrored: Vector4, channel: int, omega: float, time_value: float) -> Vector2:
	var phase := omega * time_value
	var cosine := cos(phase)
	var sine := sin(phase)
	return Vector2(
		(current[channel] + mirrored[channel]) * cosine
			- (current[channel + 1] + mirrored[channel + 1]) * sine,
		(current[channel] - mirrored[channel]) * sine
			+ (current[channel + 1] - mirrored[channel + 1]) * cosine
	)


func _compare_texture(texture: Texture2D, expected: PackedVector4Array, size: int, label: String) -> float:
	if texture == null:
		push_error("%s: missing GPU texture" % label)
		return INF
	var image := texture.get_image()
	if image == null or image.get_width() != size or image.get_height() != size:
		push_error("%s: invalid GPU texture dimensions" % label)
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


func _build_slope_reference(
	spectrum: Dictionary,
	size: int,
	grid_sizes: Vector4,
	time_value: float
) -> Array[PackedVector4Array]:
	var output01 := PackedVector4Array()
	var output23 := PackedVector4Array()
	output01.resize(size * size)
	output23.resize(size * size)
	var inverse_sizes := Vector4(
		TAU * float(size) / grid_sizes.x,
		TAU * float(size) / grid_sizes.y,
		TAU * float(size) / grid_sizes.z,
		TAU * float(size) / grid_sizes.w
	)
	var spec01: PackedVector4Array = spectrum["spectrum01"]
	var spec23: PackedVector4Array = spectrum["spectrum23"]
	var wtable: PackedVector4Array = spectrum["wtable"]
	for y in range(size):
		for x in range(size):
			var index := x + y * size
			var mirror := ((size - x) % size) + ((size - y) % size) * size
			var uvx := float(x) / float(size)
			var uvy := float(y) / float(size)
			var st := Vector2(uvx - 1.0 if uvx > 0.5 else uvx, uvy - 1.0 if uvy > 0.5 else uvy)
			var slopes: Array[Vector2] = []
			for grid in range(4):
				var source := spec01[index] if grid < 2 else spec23[index]
				var mirrored := spec01[mirror] if grid < 2 else spec23[mirror]
				var channel := (grid % 2) * 2
				var height := _evolve(source, mirrored, channel, wtable[index][grid], time_value)
				var k := st * inverse_sizes[grid]
				slopes.append(Vector2(
					-k.x * height.y - k.y * height.x,
					k.x * height.x - k.y * height.y
				))
			output01[index] = Vector4(slopes[0].x, slopes[0].y, slopes[1].x, slopes[1].y)
			output23[index] = Vector4(slopes[2].x, slopes[2].y, slopes[3].x, slopes[3].y)
	return [output01, output23]


func _build_jacobian_reference(
	spectrum: Dictionary,
	size: int,
	grid_sizes: Vector4,
	time_value: float
) -> Array[PackedVector4Array]:
	var outputs: Array[PackedVector4Array] = []
	for _attachment in range(3):
		var buffer := PackedVector4Array()
		buffer.resize(size * size)
		outputs.append(buffer)
	var inverse_sizes := Vector4(
		TAU * float(size) / grid_sizes.x,
		TAU * float(size) / grid_sizes.y,
		TAU * float(size) / grid_sizes.z,
		TAU * float(size) / grid_sizes.w
	)
	var spec01: PackedVector4Array = spectrum["spectrum01"]
	var spec23: PackedVector4Array = spectrum["spectrum23"]
	var wtable: PackedVector4Array = spectrum["wtable"]
	for y in range(size):
		for x in range(size):
			var index := x + y * size
			var mirror := ((size - x) % size) + ((size - y) % size) * size
			var uvx := float(x) / float(size)
			var uvy := float(y) / float(size)
			var st := Vector2(uvx - 1.0 if uvx > 0.5 else uvx, uvy - 1.0 if uvy > 0.5 else uvy)
			var jacobians: Array[Vector3] = []
			for grid in range(4):
				var source := spec01[index] if grid < 2 else spec23[index]
				var mirrored := spec01[mirror] if grid < 2 else spec23[mirror]
				var channel := (grid % 2) * 2
				var height := _evolve(source, mirrored, channel, wtable[index][grid], time_value)
				var k := st * inverse_sizes[grid]
				var magnitude := k.length()
				var scale := 0.0 if magnitude == 0.0 else -height.x / magnitude
				scale *= FOAM_AMOUNT
				jacobians.append(Vector3(k.x * k.x, k.y * k.y, k.x * k.y) * scale)
			outputs[0][index] = Vector4(jacobians[0].x, jacobians[1].x, jacobians[2].x, jacobians[3].x)
			outputs[1][index] = Vector4(jacobians[0].y, jacobians[1].y, jacobians[2].y, jacobians[3].y)
			outputs[2][index] = Vector4(jacobians[0].z, jacobians[1].z, jacobians[2].z, jacobians[3].z)
	return outputs


func _run_test() -> void:
	var size := 8
	var grid_count := 4
	var settings := CetoSpectrumGenerator.grid_configuration("unified", grid_count)
	var parameters := CetoSpectrum.unified_parameters(8.0, 17.0, 0.64)
	var spectrum := CetoSpectrumGenerator.generate(
		size, "unified", parameters,
		settings["grid_sizes"], settings["wave_amplitudes"], grid_count
	)
	var time_value := 0.875
	var expected_displacement := CetoDisplacement.initialize(
		spectrum, size, settings["grid_sizes"], grid_count, time_value
	)

	var runner := CetoGpuPassRunner.new()
	root.add_child(runner)
	await process_frame
	var gpu_pipeline := CetoGpuOceanPipeline.new()
	var passed := true
	var max_error := 0.0

	var displacement_result: Dictionary = await gpu_pipeline.initialize_displacement(
		runner, spectrum, size, settings["grid_sizes"], grid_count, time_value
	)
	var displacement_outputs: Array = displacement_result["displacement_textures"]
	var displacement_expected: Array = [
		expected_displacement["displacement"],
		expected_displacement["slopes_01"],
		expected_displacement["slopes_23"]
	]
	if displacement_outputs.size() != 3 or runner.get_last_pass_count() != 3:
		push_error("GPU displacement initialization expected three passes")
		passed = false
	else:
		for index in range(3):
			var error := _compare_texture(displacement_outputs[index], displacement_expected[index], size, "InitDisplacement output %d" % index)
			max_error = maxf(max_error, error)
			passed = passed and error <= TOLERANCE

	runner.release_targets()
	await process_frame
	var slope_result: Dictionary = await gpu_pipeline.initialize_slopes(
		runner, spectrum, size, settings["grid_sizes"], grid_count, time_value
	)
	var slope_outputs: Array = slope_result["slope_textures"]
	var slope_expected := _build_slope_reference(spectrum, size, settings["grid_sizes"], time_value)
	if slope_outputs.size() != 2 or runner.get_last_pass_count() != 2:
		push_error("GPU slope initialization expected two passes")
		passed = false
	else:
		for index in range(2):
			var error := _compare_texture(slope_outputs[index], slope_expected[index], size, "InitSlope output %d" % index)
			max_error = maxf(max_error, error)
			passed = passed and error <= TOLERANCE

	runner.release_targets()
	await process_frame
	var jacobian_result: Dictionary = await gpu_pipeline.initialize_jacobians(
		runner, spectrum, size, settings["grid_sizes"], grid_count, time_value, FOAM_AMOUNT
	)
	var jacobian_outputs: Array = jacobian_result["jacobian_textures"]
	var jacobian_expected := _build_jacobian_reference(spectrum, size, settings["grid_sizes"], time_value)
	if jacobian_outputs.size() != 3 or runner.get_last_pass_count() != 3:
		push_error("GPU Jacobian initialization expected three passes")
		passed = false
	else:
		for index in range(3):
			var error := _compare_texture(jacobian_outputs[index], jacobian_expected[index], size, "InitJacobians output %d" % index)
			max_error = maxf(max_error, error)
			passed = passed and error <= TOLERANCE

	if passed:
		print("CETO GPU INITIALIZATION: PASS (8 shader passes, max error %.6f)" % max_error)
	runner.release_targets()
	runner.queue_free()
	quit(0 if passed else 1)
