extends SceneTree

const CetoSpectrum = preload("res://scripts/ceto_spectrum.gd")
const CetoSpectrumGenerator = preload("res://scripts/ceto_spectrum_generator.gd")
const CetoGpuPassRunner = preload("res://scripts/ceto_gpu_pass_runner.gd")
const CetoGpuOceanPipeline = preload("res://scripts/ceto_gpu_ocean_pipeline.gd")


func _initialize() -> void:
	if RenderingServer.get_rendering_device() == null:
		print("CETO GPU PIPELINE: SKIP (RenderingDevice unavailable)")
		quit(0)
		return
	await _run_test()


func _run_test() -> void:
	var size := 8
	var grid_count := 4
	var settings := CetoSpectrumGenerator.grid_configuration("unified", grid_count)
	var parameters := CetoSpectrum.unified_parameters(8.0, 25.0, 0.64)
	var spectrum := CetoSpectrumGenerator.generate(
		size, "unified", parameters,
		settings["grid_sizes"], settings["wave_amplitudes"], grid_count
	)
	var runner := CetoGpuPassRunner.new()
	root.add_child(runner)
	await process_frame
	var pipeline := CetoGpuOceanPipeline.new()
	var result: Dictionary = await pipeline.update_gpu_ocean(
		runner, spectrum, size, settings["grid_sizes"], grid_count,
		0.875, settings["choppiness"], 0.0, 1.0
	)
	var displacement: Array = result["displacement_textures"]
	var slopes: Array = result["slope_textures"]
	var jacobians: Array = result["jacobian_textures"]
	var foam: Texture2D = result["foam_texture"]
	var passed: bool = (
		int(result["pass_count"]) == 61
		and displacement.size() == 4
		and slopes.size() == 2
		and jacobians.size() == 3
		and foam != null
	)
	for texture in displacement + slopes + jacobians + [foam]:
		if texture == null or texture.get_width() != size or texture.get_height() != size:
			passed = false
			push_error("Integrated GPU pipeline returned an invalid texture")
	if not passed:
		push_error("Integrated GPU pipeline output contract failed: %s" % {
			"pass_count": result.get("pass_count", -1),
			"displacement": displacement.size(),
			"slopes": slopes.size(),
			"jacobians": jacobians.size(),
			"foam_valid": foam != null
		})
	else:
		print("CETO GPU PIPELINE: PASS (61 passes, 4 grids)")
	runner.release_targets()
	runner.queue_free()
	quit(0 if passed else 1)
