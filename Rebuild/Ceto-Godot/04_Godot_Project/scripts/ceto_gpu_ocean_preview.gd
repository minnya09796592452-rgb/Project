extends Node3D

## Optional real-time GPU preview. Uses the default project Mobile renderer;
## the CPU preview remains the deterministic fallback for unsupported devices.

const CetoSpectrum = preload("res://scripts/ceto_spectrum.gd")
const CetoSpectrumGenerator = preload("res://scripts/ceto_spectrum_generator.gd")
const CetoGpuPassRunner = preload("res://scripts/ceto_gpu_pass_runner.gd")
const CetoGpuOceanPipeline = preload("res://scripts/ceto_gpu_ocean_pipeline.gd")
const SURFACE_SHADER = preload("res://shaders/ceto_ocean_surface.gdshader")

@export_range(8, 256, 8) var fft_size := 64
@export_range(0.1, 2.0, 0.1) var update_interval := 0.5
@export_range(0.0, 4.0, 0.1) var foam_strength := 1.0

var _settings: Dictionary
var _spectrum_data: Dictionary
var _pipeline := CetoGpuOceanPipeline.new()
var _runner: CetoGpuPassRunner
var _material: ShaderMaterial
var _elapsed := 0.0
var _updating := false
var _simulation_time := 0.0


func _ready() -> void:
	if RenderingServer.get_rendering_device() == null:
		push_error("GPU ocean preview requires a Forward+ or Mobile RenderingDevice backend")
		return
	_settings = CetoSpectrumGenerator.grid_configuration("unified", 4)
	var parameters := CetoSpectrum.unified_parameters(8.0, 25.0, 0.64)
	_spectrum_data = CetoSpectrumGenerator.generate(
		fft_size, "unified", parameters,
		_settings["grid_sizes"], _settings["wave_amplitudes"], 4
	)
	_create_environment()
	_create_camera()
	_create_surface()
	_update_gpu()


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= update_interval and not _updating:
		_elapsed = 0.0
		_simulation_time += update_interval
		_update_gpu()


func _create_environment() -> void:
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.008, 0.035, 0.065)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.48, 0.64, 0.75)
	environment.ambient_light_energy = 0.8
	world.environment = environment
	add_child(world)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-48.0, -32.0, 0.0)
	light.light_energy = 1.15
	add_child(light)


func _create_camera() -> void:
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 190.0, 260.0)
	add_child(camera)
	camera.look_at(Vector3.ZERO, Vector3.UP)
	camera.current = true


func _create_surface() -> void:
	var plane := PlaneMesh.new()
	var grid_sizes: Vector4 = _settings["grid_sizes"]
	plane.size = Vector2(grid_sizes.x, grid_sizes.x)
	plane.subdivide_width = maxi(fft_size - 1, 1)
	plane.subdivide_depth = maxi(fft_size - 1, 1)

	var surface := MeshInstance3D.new()
	surface.mesh = plane
	_material = ShaderMaterial.new()
	_material.shader = SURFACE_SHADER
	_material.set_shader_parameter("grid_sizes", grid_sizes)
	_material.set_shader_parameter("choppiness", _settings["choppiness"])
	_material.set_shader_parameter("grid_count", 4)
	_material.set_shader_parameter("foam_strength", foam_strength)
	surface.material_override = _material
	add_child(surface)


func _update_gpu() -> void:
	if _updating:
		return
	_updating = true
	var next_runner := CetoGpuPassRunner.new()
	add_child(next_runner)
	var result: Dictionary = await _pipeline.update_gpu_ocean(
		next_runner,
		_spectrum_data,
		fft_size,
		_settings["grid_sizes"],
		4,
		_simulation_time,
		_settings["choppiness"],
		0.0,
		1.0
	)
	var displacement_textures: Array = result["displacement_textures"]
	if displacement_textures.size() == 4:
		for grid in range(4):
			_material.set_shader_parameter("displacement_grid_%d" % grid, displacement_textures[grid])
	var slope_textures: Array = result["slope_textures"]
	if slope_textures.size() == 2:
		_material.set_shader_parameter("slope_buffer_01", slope_textures[0])
		_material.set_shader_parameter("slope_buffer_23", slope_textures[1])
	_material.set_shader_parameter("foam_texture", result["foam_texture"])

	var previous_runner := _runner
	_runner = next_runner
	if previous_runner != null and is_instance_valid(previous_runner):
		previous_runner.queue_free()
	_updating = false
