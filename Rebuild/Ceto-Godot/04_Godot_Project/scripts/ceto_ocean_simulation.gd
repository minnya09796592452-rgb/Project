extends RefCounted
class_name CetoOceanSimulation

## Integrated CPU Ceto simulation path for Godot:
## spectrum conditions -> deterministic spectrum buffers -> time evolution ->
## packed 2D FFT -> per-grid displacement arrays -> bilinear wave queries.
## This is the CPU numerical backend; it does not yet render an ocean mesh.

const CetoFourier = preload("res://scripts/ceto_fourier.gd")
const SpectrumMath = preload("res://scripts/ceto_spectrum.gd")
const SpectrumGenerator = preload("res://scripts/ceto_spectrum_generator.gd")
const Displacement = preload("res://scripts/ceto_displacement.gd")
const WaveQuery = preload("res://scripts/ceto_wave_query.gd")

var size := 64
var num_grids := 4
var spectrum_type := "unified"
var wind_speed := 8.0
var wind_direction := 0.0
var wave_age := 0.64
var scale_y := 1.0

var grid_sizes := Vector4.ZERO
var choppiness := Vector4.ONE
var wave_amplitudes := Vector4.ONE

var _spectrum_parameters: Dictionary = {}
var _spectrum_data: Dictionary = {}
var _grid_displacements: Array[PackedVector3Array] = []
var _query_buffers: Array[CetoInterpolatedArray2D] = []
var _initialized := false
var _last_time := 0.0


func configure(
	fourier_size: int = 64,
	grid_count: int = 4,
	spectrum: String = "unified",
	wind: float = 8.0,
	wind_dir_degrees: float = 0.0,
	age: float = 0.64,
	height_scale: float = 1.0
) -> void:
	assert(CetoFourier.is_power_of_two(fourier_size), "Ceto Fourier size must be a power of two")
	assert(grid_count >= 1 and grid_count <= 4, "Ceto supports one through four grids")
	assert(spectrum == "unified" or spectrum == "phillips", "Unknown Ceto spectrum type")
	size = fourier_size
	num_grids = grid_count
	spectrum_type = spectrum
	wind_speed = wind
	wind_direction = wind_dir_degrees
	wave_age = age
	scale_y = height_scale
	_initialized = false


func initialize() -> void:
	var settings := SpectrumGenerator.grid_configuration(spectrum_type, num_grids)
	grid_sizes = settings["grid_sizes"]
	choppiness = settings["choppiness"]
	wave_amplitudes = settings["wave_amplitudes"]

	if spectrum_type == "unified":
		_spectrum_parameters = SpectrumMath.unified_parameters(
			wind_speed, wind_direction, wave_age
		)
	else:
		_spectrum_parameters = SpectrumMath.phillips_parameters(
			wind_speed, wind_direction
		)

	_spectrum_data = SpectrumGenerator.generate(
		size, spectrum_type, _spectrum_parameters,
		grid_sizes, wave_amplitudes, num_grids
	)

	_query_buffers.clear()
	for _grid in range(4):
		_query_buffers.append(CetoInterpolatedArray2D.new(size, size, 3, true))

	_grid_displacements.clear()
	for _grid in range(4):
		var empty_grid := PackedVector3Array()
		empty_grid.resize(size * size)
		_grid_displacements.append(empty_grid)

	_last_time = 0.0
	_initialized = true


func update(time_value: float) -> void:
	if not _initialized:
		initialize()

	var cpu_result := Displacement.run_cpu_pipeline(
		_spectrum_data, size, grid_sizes, num_grids, time_value
	)
	_grid_displacements = cpu_result["displacements"]

	for grid in range(4):
		var buffer: CetoInterpolatedArray2D = _query_buffers[grid]
		var values: PackedVector3Array = _grid_displacements[grid]
		for index in range(size * size):
			var x := index % size
			var y: int = index / size
			var value := values[index]
			buffer.set_value(x, y, 0, value.x)
			buffer.set_value(x, y, 1, value.y)
			buffer.set_value(x, y, 2, value.z)

	_last_time = time_value


func query(
	world_x: float,
	world_z: float,
	sample_spectrum: Array[bool] = [true, true, false, false],
	mode: String = "position",
	min_error: float = 0.1
) -> Dictionary:
	assert(_initialized, "Call initialize() or update() before querying")
	var inverse_grid_sizes := Vector4(
		1.0 / grid_sizes.x,
		1.0 / grid_sizes.y,
		1.0 / grid_sizes.z,
		1.0 / grid_sizes.w
	)
	return WaveQuery.query(
		_query_buffers,
		world_x,
		world_z,
		sample_spectrum,
		num_grids,
		inverse_grid_sizes,
		choppiness,
		scale_y,
		Vector2.ZERO,
		mode,
		min_error
	)



func sample_surface(world_x: float, world_z: float) -> Vector3:
	assert(_initialized, "Call initialize() or update() before sampling")
	var total := Vector3.ZERO
	for grid in range(num_grids):
		var sample := _query_buffers[grid].sample_vector3(
			world_x / grid_sizes[grid],
			world_z / grid_sizes[grid]
		)
		total.x += sample.x * choppiness[grid]
		total.y += sample.y * scale_y
		total.z += sample.z * choppiness[grid]
	return total

func get_displacement_grid(index: int) -> PackedVector3Array:
	assert(index >= 0 and index < 4)
	return _grid_displacements[index]


func get_simulation_time() -> float:
	return _last_time
