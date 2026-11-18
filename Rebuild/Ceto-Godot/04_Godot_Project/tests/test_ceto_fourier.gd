extends SceneTree

const CetoFourier = preload("res://scripts/ceto_fourier.gd")
const TOLERANCE := 0.002


func _initialize() -> void:
	var failures: Array[String] = []
	_test_direct_dft(failures)
	_test_impulse(failures)
	_test_constant_dc(failures)
	_test_plane_wave(failures)
	_test_lookup_textures(failures)

	if failures.is_empty():
		print("CETO GODOT FFT: 5/5 PASS")
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
