extends SceneTree

const CetoFourier = preload("res://scripts/ceto_fourier.gd")
const CetoGpuPassRunner = preload("res://scripts/ceto_gpu_pass_runner.gd")
const TOLERANCE := 0.025


func _initialize() -> void:
	await _run_gpu_fft_test()


func _run_gpu_fft_test() -> void:
	var size := 8
	var packed := PackedVector4Array()
	packed.resize(size * size)
	var input_image := Image.create(size, size, false, Image.FORMAT_RGBAF)
	for y in range(size):
		for x in range(size):
			var index := x + y * size
			var value := Vector4(
				sin(float(index) * 0.13),
				cos(float(index) * 0.21),
				sin(float(index) * 0.31),
				cos(float(index) * 0.41)
			)
			packed[index] = value
			input_image.set_pixel(x, y, Color(value.x, value.y, value.z, value.w))

	var expected := CetoFourier.transform_packed_vector4_2d(packed, size, true)
	var input_texture := ImageTexture.create_from_image(input_image)
	var runner := CetoGpuPassRunner.new()
	root.add_child(runner)
	await process_frame

	var output_texture: Texture2D = await runner.transform_packed_texture(input_texture, size)
	if output_texture == null:
		push_error("GPU FFT returned no output texture")
		runner.release_targets()
		runner.queue_free()
		quit(1)
		return

	var output_image := output_texture.get_image()
	if output_image == null or output_image.get_width() != size or output_image.get_height() != size:
		push_error("GPU FFT output image dimensions are invalid")
		runner.release_targets()
		runner.queue_free()
		quit(1)
		return

	var max_error := 0.0
	for y in range(size):
		for x in range(size):
			var index := x + y * size
			var pixel := output_image.get_pixel(x, y)
			var actual := Vector4(pixel.r, pixel.g, pixel.b, pixel.a)
			for channel in range(4):
				max_error = maxf(max_error, absf(actual[channel] - expected[index][channel]))

	var passed := true
	if runner.get_last_pass_count() != 6:
		push_error("GPU FFT pass count mismatch: expected 6, got %d" % runner.get_last_pass_count())
		passed = false
	elif max_error > TOLERANCE:
		push_error("GPU FFT differs from CPU reference: max error %.6f > %.6f" % [max_error, TOLERANCE])
		passed = false
	else:
		print("CETO GPU FFT: PASS (6 passes, max error %.6f)" % max_error)

	runner.release_targets()
	runner.queue_free()
	quit(0 if passed else 1)
