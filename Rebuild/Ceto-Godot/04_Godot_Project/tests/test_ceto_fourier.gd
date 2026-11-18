extends SceneTree

# Strict CI currently expects all thirteen numerical test groups.

const CetoFourier = preload("res://scripts/ceto_fourier.gd")
const CetoSpectrum = preload("res://scripts/ceto_spectrum.gd")
const CetoDotNetRandom = preload("res://scripts/ceto_dotnet_random.gd")
const CetoSpectrumGenerator = preload("res://scripts/ceto_spectrum_generator.gd")
const CetoDisplacement = preload("res://scripts/ceto_displacement.gd")
const CetoInterpolatedArray2D = preload("res://scripts/ceto_interpolated_array_2d.gd")
const CetoWaveQuery = preload("res://scripts/ceto_wave_query.gd")
const CetoOceanSimulation = preload("res://scripts/ceto_ocean_simulation.gd")
const TOLERANCE := 0.002


func _initialize() -> void:
	var failures: Array[String] = []
	_test_direct_dft(failures)
	_test_impulse(failures)
	_test_constant_dc(failures)
	_test_plane_wave(failures)
	_test_lookup_textures(failures)
	_test_spectrum_math(failures)
	_test_dotnet_random(failures)
	_test_spectrum_generation(failures)
	_test_displacement_initialization(failures)
	_test_bilinear_interpolation(failures)
	_test_wave_query(failures)
	_test_packed_cpu_pipeline(failures)
	_test_integrated_simulation(failures)

	if failures.is_empty():
		print("CETO GODOT NUMERICS: 13/13 PASS")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("CETO GODOT FFT: FAIL (%d)" % failures.size())
		quit(1)


func _complex_multiply(a: Vector2, b: Vector2) -> Vector2:
	return Vector2(a.x * b.x - a.y * b.y, a.x * b.y + a.y * b.x)


func _direct_dft(values: PackedVector2Array, size: int) -> PackedVector2Array:
	var output := PackedVector2Array()
	output.resize(size * size)
	for fy in range(size):
		for fx in range(size):
			var total := Vector2.ZERO
			for y in range(size):
				for x in range(size):
					var phase := TAU * float(fx * x + fy * y) / float(size)
					var twiddle := Vector2(cos(phase), sin(phase))
					total += _complex_multiply(values[x + y * size], twiddle)
			output[fx + fy * size] = total
	return output


func _assert_close(actual: PackedVector2Array, expected: PackedVector2Array, label: String, failures: Array[String]) -> void:
	if actual.size() != expected.size():
		failures.append("%s: length mismatch" % label)
		return
	for i in range(actual.size()):
		if actual[i].distance_to(expected[i]) > TOLERANCE:
			failures.append("%s: sample %d differs (got %s expected %s)" % [label, i, actual[i], expected[i]])
			return


func _test_direct_dft(failures: Array[String]) -> void:
	for size in [2, 4, 8]:
		var values := PackedVector2Array()
		for i in range(size * size):
			values.append(Vector2(sin(float(i) * 0.37), cos(float(i) * 0.19)))
		_assert_close(
			CetoFourier.transform_2d(values, size),
			_direct_dft(values, size),
			"direct DFT size %d" % size,
			failures
		)


func _test_impulse(failures: Array[String]) -> void:
	var size := 16
	var values := PackedVector2Array()
	values.resize(size * size)
	values[0] = Vector2.ONE
	var expected := PackedVector2Array()
	expected.resize(size * size)
	for i in range(size * size):
		expected[i] = Vector2.ONE
	_assert_close(CetoFourier.transform_2d(values, size), expected, "impulse", failures)


func _test_constant_dc(failures: Array[String]) -> void:
	var size := 8
	var values := PackedVector2Array()
	values.resize(size * size)
	for i in range(values.size()):
		values[i] = Vector2(1.0, 0.0)
	var expected := PackedVector2Array()
	expected.resize(size * size)
	expected[0] = Vector2(size * size, 0.0)
	_assert_close(CetoFourier.transform_2d(values, size), expected, "constant DC", failures)


func _test_plane_wave(failures: Array[String]) -> void:
	var size := 8
	var fx := 2
	var fy := 3
	var values := PackedVector2Array()
	values.resize(size * size)
	for y in range(size):
		for x in range(size):
			var phase := -TAU * float(fx * x + fy * y) / float(size)
			values[x + y * size] = Vector2(cos(phase), sin(phase))
	var expected := PackedVector2Array()
	expected.resize(size * size)
	expected[fx + fy * size] = Vector2(size * size, 0.0)
	_assert_close(CetoFourier.transform_2d(values, size), expected, "plane wave axis order", failures)


func _test_lookup_textures(failures: Array[String]) -> void:
	var textures := CetoFourier.create_butterfly_lookup_textures(8)
	if textures.size() != 3:
		failures.append("lookup texture count: expected 3 stages")
		return
	var image := textures[0].get_image()
	var shader_paths := [
		"res://shaders/ceto_fourier_stage.gdshader",
		"res://shaders/ceto_init_displacement.gdshader",
		"res://shaders/ceto_init_slope.gdshader",
		"res://shaders/ceto_init_jacobians.gdshader"
	]
	for shader_path in shader_paths:
		var shader_resource = ResourceLoader.load(shader_path, "Shader")
		if shader_resource == null:
			failures.append("Godot shader failed to load: %s" % shader_path)
	if image.get_format() != Image.FORMAT_RGBAF or image.get_width() != 8 or image.get_height() != 1:
		failures.append("lookup texture format/dimensions mismatch")

func _test_spectrum_math(failures: Array[String]) -> void:
	var table := CetoSpectrum.build_w_table(8, Vector4(100.0, 50.0, 25.0, 12.5), 4)
	if table.size() != 64:
		failures.append("WTable size mismatch")
		return
	if table[0].length() > TOLERANCE:
		failures.append("WTable zero-frequency origin is not zero")
	for sample in table:
		for channel in range(4):
			if not is_finite(sample[channel]):
				failures.append("WTable contains non-finite frequency")
				return

	var phillips := CetoSpectrum.phillips_parameters(8.0, 0.0)
	if CetoSpectrum.phillips_sample(0.0, 0.0, phillips) != 0.0:
		failures.append("Phillips spectrum origin must be zero")
	if CetoSpectrum.phillips_sample(1.0, 0.0, phillips) <= 0.0:
		failures.append("Phillips spectrum downwind sample must be positive")
	if CetoSpectrum.phillips_sample(0.0, 1.0, phillips) != 0.0:
		failures.append("Phillips spectrum crosswind sample must be zero")

	var unified := CetoSpectrum.unified_parameters(8.0, 0.0, 0.64)
	var downwind := CetoSpectrum.unified_sample(1.0, 0.0, unified)
	var upwind := CetoSpectrum.unified_sample(-1.0, 0.0, unified)
	if not is_finite(downwind) or downwind <= 0.0:
		failures.append("Unified spectrum downwind sample is not finite and positive")
	if upwind != 0.0:
		failures.append("Unified spectrum should suppress negative rotated kx")

func _test_dotnet_random(failures: Array[String]) -> void:
	var random := CetoDotNetRandom.new(0)
	var expected := [
		0.7262432699679598,
		0.8173253595909687,
		0.7680226893946634,
		0.5581611914365372,
		0.2060331540210327
	]
	for index in range(expected.size()):
		var actual := random.next_double()
		if absf(actual - expected[index]) > 1e-12:
			failures.append("System.Random(0) sequence mismatch at %d: %.16f" % [index, actual])
			return


func _test_spectrum_generation(failures: Array[String]) -> void:
	var settings := CetoSpectrumGenerator.grid_configuration("unified", 4)
	var parameters := CetoSpectrum.unified_parameters(8.0, 0.0, 0.64)
	var first := CetoSpectrumGenerator.generate(
		8, "unified", parameters,
		settings["grid_sizes"], settings["wave_amplitudes"], 4
	)
	var second := CetoSpectrumGenerator.generate(
		8, "unified", parameters,
		settings["grid_sizes"], settings["wave_amplitudes"], 4
	)
	if first["spectrum01"].size() != 64 or first["spectrum23"].size() != 64:
		failures.append("SpectrumTask packed buffer dimensions mismatch")
		return
	if first["wtable"].size() != 64:
		failures.append("SpectrumTask WTable dimensions mismatch")
		return
	for index in range(64):
		if first["spectrum01"][index] != second["spectrum01"][index]:
			failures.append("SpectrumTask Spectrum01 is not deterministic")
			return
		if first["spectrum23"][index] != second["spectrum23"][index]:
			failures.append("SpectrumTask Spectrum23 is not deterministic")
			return
		for channel in range(4):
			if not is_finite(first["spectrum01"][index][channel]):
				failures.append("SpectrumTask Spectrum01 contains non-finite values")
				return
			if not is_finite(first["spectrum23"][index][channel]):
				failures.append("SpectrumTask Spectrum23 contains non-finite values")
				return

func _test_displacement_initialization(failures: Array[String]) -> void:
	var parameters := CetoSpectrum.unified_parameters(8.0, 25.0, 0.64)
	var one_grid := CetoSpectrumGenerator.grid_configuration("unified", 1)
	var one_spectrum := CetoSpectrumGenerator.generate(
		8, "unified", parameters,
		one_grid["grid_sizes"], one_grid["wave_amplitudes"], 1
	)
	var at_zero := CetoDisplacement.initialize(one_spectrum, 8, one_grid["grid_sizes"], 1, 0.0)
	var sample_x := 3
	var sample_y := 2
	var sample_index := sample_x + sample_y * 8
	var mirror_index := ((8 - sample_x) % 8) + ((8 - sample_y) % 8) * 8
	var source: Vector4 = one_spectrum["spectrum01"][sample_index]
	var mirrored: Vector4 = one_spectrum["spectrum01"][mirror_index]
	var expected_height := Vector2(source.x + mirrored.x, source.y - mirrored.y)
	var actual_height: Vector4 = at_zero["displacement"][sample_index]
	if Vector2(actual_height.x, actual_height.y).distance_to(expected_height) > TOLERANCE:
		failures.append("Zero-time displacement does not match Ceto's mirrored-frequency formula")
		return

	for grid_count in [1, 2, 3, 4]:
		var settings := CetoSpectrumGenerator.grid_configuration("unified", grid_count)
		var spectrum := CetoSpectrumGenerator.generate(
			8, "unified", parameters,
			settings["grid_sizes"], settings["wave_amplitudes"], grid_count
		)
		var initialized := CetoDisplacement.initialize(
			spectrum, 8, settings["grid_sizes"], grid_count, 1.25
		)
		if initialized["displacement"].size() != 64 or initialized["slopes_01"].size() != 64:
			failures.append("Displacement output dimensions mismatch for %d grids" % grid_count)
			return
		var expected_secondary := 64 if grid_count > 2 else 0
		if initialized["slopes_23"].size() != expected_secondary:
			failures.append("Secondary slope dimensions mismatch for %d grids" % grid_count)
			return
		for sample in initialized["displacement"]:
			for channel in range(4):
				if not is_finite(sample[channel]):
					failures.append("Displacement contains non-finite values for %d grids" % grid_count)
					return

func _test_bilinear_interpolation(failures: Array[String]) -> void:
	var wrapped := CetoInterpolatedArray2D.new(2, 2, 3, true)
	var values := [
		Vector3(0.0, 0.0, 0.0),
		Vector3(2.0, 4.0, 6.0),
		Vector3(4.0, 8.0, 12.0),
		Vector3(6.0, 12.0, 18.0)
	]
	for y in range(2):
		for x in range(2):
			var value: Vector3 = values[x + y * 2]
			for channel in range(3):
				wrapped.set_value(x, y, channel, value[channel])

	var center := wrapped.sample_vector3(0.5, 0.5)
	if center.distance_to(Vector3(3.0, 6.0, 9.0)) > TOLERANCE:
		failures.append("Bilinear center sample mismatch")
		return
	var wrapped_edge := wrapped.sample_vector3(-0.25, 0.25)
	if wrapped_edge.distance_to(Vector3(2.0, 4.0, 6.0)) > TOLERANCE:
		failures.append("Wrapped negative-coordinate sample mismatch")
		return

	wrapped.wrap = false
	var clamped_edge := wrapped.sample_vector3(-0.25, 0.25)
	if clamped_edge.length() > TOLERANCE:
		failures.append("Clamped negative-coordinate sample mismatch")

func _test_wave_query(failures: Array[String]) -> void:
	var grids: Array[CetoInterpolatedArray2D] = []
	for grid_index in range(4):
		var grid := CetoInterpolatedArray2D.new(2, 2, 3, true)
		var constant_value := Vector3(0.15, 2.0, 0.0) if grid_index == 0 else (
			Vector3(0.05, 3.0, 0.0) if grid_index == 1 else Vector3.ZERO
		)
		for y in range(2):
			for x in range(2):
				for channel in range(3):
					grid.set_value(x, y, channel, constant_value[channel])
		grids.append(grid)

	var sample_two: Array[bool] = [true, true, false, false]
	var inverse_sizes := Vector4.ONE
	var chop := Vector4.ONE
	var position_result := CetoWaveQuery.query(
		grids, 12.0, -4.0, sample_two, 2,
		inverse_sizes, chop, 1.0, Vector2.ZERO, "position", 0.1
	)
	if absf(position_result["height"] - 5.0) > TOLERANCE:
		failures.append("Wave POSITION query height mismatch")
		return
	if absf(position_result["displacement_x"] - 0.2) > TOLERANCE:
		failures.append("Wave POSITION query horizontal displacement mismatch")
		return
	if position_result["iterations"] != 2 or position_result["error"] > TOLERANCE:
		failures.append("Wave POSITION inverse-displacement iteration mismatch")
		return

	var height_result := CetoWaveQuery.query(
		grids, 12.0, -4.0, sample_two, 2,
		inverse_sizes, chop, 1.0, Vector2.ZERO, "displacement", 0.1
	)
	if absf(height_result["height"] - 5.0) > TOLERANCE:
		failures.append("Wave DISPLACEMENT query height mismatch")
		return
	for value in height_result["displacement"]:
		if absf(value.x) > TOLERANCE or absf(value.z) > TOLERANCE:
			failures.append("Height-only query returned horizontal displacement")
			return

func _test_packed_cpu_pipeline(failures: Array[String]) -> void:
	var size := 8
	var packed := PackedVector4Array()
	packed.resize(size * size)
	for index in range(packed.size()):
		packed[index] = Vector4(
			sin(float(index) * 0.13),
			cos(float(index) * 0.21),
			sin(float(index) * 0.31),
			cos(float(index) * 0.41)
		)
	var double_fft := CetoFourier.transform_packed_vector4_2d(packed, size, true)
	var xy := PackedVector2Array()
	var zw := PackedVector2Array()
	for value in packed:
		xy.append(Vector2(value.x, value.y))
		zw.append(Vector2(value.z, value.w))
	var expected_xy := CetoFourier.transform_2d(xy, size)
	var expected_zw := CetoFourier.transform_2d(zw, size)
	for index in range(packed.size()):
		if Vector2(double_fft[index].x, double_fft[index].y).distance_to(expected_xy[index]) > TOLERANCE:
			failures.append("Double-packed FFT XY result mismatch")
			return
		if Vector2(double_fft[index].z, double_fft[index].w).distance_to(expected_zw[index]) > TOLERANCE:
			failures.append("Double-packed FFT ZW result mismatch")
			return

	var parameters := CetoSpectrum.unified_parameters(8.0, 15.0, 0.64)
	for grid_count in [1, 2, 3, 4]:
		var settings := CetoSpectrumGenerator.grid_configuration("unified", grid_count)
		var spectrum := CetoSpectrumGenerator.generate(
			size, "unified", parameters,
			settings["grid_sizes"], settings["wave_amplitudes"], grid_count
		)
		var cpu := CetoDisplacement.run_cpu_pipeline(
			spectrum, size, settings["grid_sizes"], grid_count, 0.75
		)
		if cpu["displacements"].size() != 4:
			failures.append("CPU pipeline did not return four grid slots")
			return
		for grid in range(4):
			if cpu["displacements"][grid].size() != size * size:
				failures.append("CPU pipeline grid dimensions mismatch")
				return
			for value in cpu["displacements"][grid]:
				for channel in range(3):
					if not is_finite(value[channel]):
						failures.append("CPU pipeline generated non-finite displacement")
						return

func _test_integrated_simulation(failures: Array[String]) -> void:
	var simulation := CetoOceanSimulation.new()
	simulation.configure(8, 2, "unified", 8.0, 25.0, 0.64, 1.0)
	simulation.initialize()
	simulation.update(0.75)
	var query_result := simulation.query(
		5.5, -2.5, [true, true, false, false], "position", 0.1
	)
	if not is_finite(query_result["height"]):
		failures.append("Integrated simulation returned non-finite wave height")
		return
	if query_result["displacement"].size() != 4:
		failures.append("Integrated simulation query did not return four grid results")
		return
	if simulation.get_displacement_grid(0).size() != 64:
		failures.append("Integrated simulation displacement grid size mismatch")
		return
	simulation.update(1.25)
	if absf(simulation.get_simulation_time() - 1.25) > TOLERANCE:
		failures.append("Integrated simulation time update mismatch")
