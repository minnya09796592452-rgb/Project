extends SceneTree

const CetoFourier = preload("res://scripts/ceto_fourier.gd")
const CetoSpectrum = preload("res://scripts/ceto_spectrum.gd")
const CetoDotNetRandom = preload("res://scripts/ceto_dotnet_random.gd")
const CetoSpectrumGenerator = preload("res://scripts/ceto_spectrum_generator.gd")
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

	if failures.is_empty():
		print("CETO GODOT NUMERICS: 8/8 PASS")
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
