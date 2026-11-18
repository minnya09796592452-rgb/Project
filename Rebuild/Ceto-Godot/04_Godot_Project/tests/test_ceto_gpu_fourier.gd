extends SceneTree

const CetoFourier = preload("res://scripts/ceto_fourier.gd")
const CetoGpuPassRunner = preload("res://scripts/ceto_gpu_pass_runner.gd")
const TOLERANCE := 0.04


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
			var scale := 1.0 / float(size * size * 2)
			var value := Vector4(
				sin(float(index) * 0.13) * scale,
				cos(float(index) * 0.21) * scale,
				sin(float(index) * 0.31) * scale,
				cos(float(index) * 0.41) * scale
			)
			packed[index] = value
			input_image.set_pixel(x, y, Color(value.x, value.y, value.z, value.w))

	var second_packed := PackedVector4Array()
	second_packed.resize(size * size)
	var second_image := Image.create(size, size, false, Image.FORMAT_RGBAF)
	for y in range(size):
		for x in range(size):
			var index := x + y * size
			var scale := 1.0 / float(size * size * 2)
			var value := Vector4(
				cos(float(index) * 0.17) * scale,
				sin(float(index) * 0.23) * scale,
				cos(float(index) * 0.37) * scale,
				sin(float(index) * 0.43) * scale
			)
			second_packed[index] = value
			second_image.set_pixel(x, y, Color(value.x, value.y, value.z, value.w))

	var expected := CetoFourier.transform_packed_vector4_2d(packed, size, true)
	var expected_second := CetoFourier.transform_packed_vector4_2d(second_packed, size, true)
	var input_texture := ImageTexture.create_from_image(input_image)
	var second_texture := ImageTexture.create_from_image(second_image)
	var runner := CetoGpuPassRunner.new()
	root.add_child(runner)
	await process_frame

	var output_textures: Array[Texture2D] = await runner.transform_packed_textures(
		[input_texture, second_texture], size
	)
	if output_textures.size() != 2:
		push_error("GPU FFT did not return two buffer outputs")
		runner.release_targets()
		runner.queue_free()
		quit(1)
		return

	var max_error := 0.0
	var expected_buffers: Array = [expected, expected_second]
	for buffer_index in range(2):
		var output_image := output_textures[buffer_index].get_image()
		if output_image == null or output_image.get_width() != size or output_image.get_height() != size:
			push_error("GPU FFT output %d image dimensions are invalid" % buffer_index)
			runner.release_targets()
			runner.queue_free()
			quit(1)
			return
		for y in range(size):
			for x in range(size):
				var index := x + y * size
				var pixel := output_image.get_pixel(x, y)
				var actual := Vector4(pixel.r, pixel.g, pixel.b, pixel.a)
				var reference: PackedVector4Array = expected_buffers[buffer_index]
				for channel in range(4):
					max_error = maxf(max_error, absf(actual[channel] - reference[index][channel]))

	var passed := true
	if runner.get_last_pass_count() != 12:
		push_error("GPU FFT pass count mismatch: expected 12, got %d" % runner.get_last_pass_count())
		passed = false
	elif max_error > TOLERANCE:
		push_error("GPU FFT differs from CPU reference: max error %.6f > %.6f" % [max_error, TOLERANCE])
		passed = false
	else:
		print("CETO GPU FFT: PASS (2 buffers, 12 passes, max error %.6f)" % max_error)

	runner.release_targets()
	runner.queue_free()
	quit(0 if passed else 1)
