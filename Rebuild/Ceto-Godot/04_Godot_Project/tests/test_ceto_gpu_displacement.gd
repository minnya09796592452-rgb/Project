extends SceneTree

const CetoSpectrum = preload("res://scripts/ceto_spectrum.gd")
const CetoSpectrumGenerator = preload("res://scripts/ceto_spectrum_generator.gd")
const CetoDisplacement = preload("res://scripts/ceto_displacement.gd")
const CetoGpuPassRunner = preload("res://scripts/ceto_gpu_pass_runner.gd")
const CetoGpuOceanPipeline = preload("res://scripts/ceto_gpu_ocean_pipeline.gd")
const TOLERANCE := 0.035


func _initialize() -> void:
	await _run_test()


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
	var expected := CetoDisplacement.initialize(
		spectrum, size, settings["grid_sizes"], grid_count, time_value
	)

	var runner := CetoGpuPassRunner.new()
	root.add_child(runner)
	await process_frame
	var gpu_pipeline := CetoGpuOceanPipeline.new()
	var result: Dictionary = await gpu_pipeline.initialize_displacement(
		runner, spectrum, size, settings["grid_sizes"], grid_count, time_value
	)
	var outputs: Array = result["displacement_textures"]
	var expected_buffers: Array = [
		expected["displacement"],
		expected["slopes_01"],
		expected["slopes_23"]
	]
	var passed := outputs.size() == 3 and runner.get_last_pass_count() == 3
	var max_error := 0.0

	if not passed:
		push_error("GPU displacement pass count mismatch: expected 3 outputs")
	else:
		for output_index in range(3):
			var image: Image = outputs[output_index].get_image()
			if image == null or image.get_width() != size or image.get_height() != size:
				push_error("GPU displacement output %d has invalid dimensions" % output_index)
				passed = false
				continue
			var expected_data: PackedVector4Array = expected_buffers[output_index]
			for y in range(size):
				for x in range(size):
					var index := x + y * size
					var pixel := image.get_pixel(x, y)
					var actual := Vector4(pixel.r, pixel.g, pixel.b, pixel.a)
					for channel in range(4):
						max_error = maxf(max_error, absf(actual[channel] - expected_data[index][channel]))

	if max_error > TOLERANCE:
		push_error("GPU displacement differs from CPU reference: max error %.6f > %.6f" % [max_error, TOLERANCE])
		passed = false
	if passed:
		print("CETO GPU DISPLACEMENT: PASS (3 passes, max error %.6f)" % max_error)

	runner.release_targets()
	runner.queue_free()
	quit(0 if passed else 1)
