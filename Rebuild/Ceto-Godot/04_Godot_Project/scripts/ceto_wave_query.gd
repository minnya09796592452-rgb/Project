extends RefCounted
class_name CetoWaveQuery

## CPU query path translated from Ceto QueryDisplacements.QueryWaves.
## Uses four wrapped bilinear grids and the original iterative inverse
## displacement solve for POSITION queries.

const GRID_COUNT := 4
const MIN_ERROR := 0.01
const MAX_ITERATIONS := 20
const MAX_SPECTRUM_WAVE_HEIGHT := 40.0


static func _sample_grids(
	displacements: Array[CetoInterpolatedArray2D],
	sample_spectrum: Array[bool],
	num_grids: int,
	x: float,
	z: float,
	inverse_grid_sizes: Vector4,
	choppiness: Vector4,
	scale_y: float
) -> Array[Vector3]:
	var values: Array[Vector3] = []
	for grid in range(GRID_COUNT):
		values.append(Vector3.ZERO)
		if grid >= num_grids or not sample_spectrum[grid]:
			continue
		var inverse_size := inverse_grid_sizes[grid]
		var sampled := displacements[grid].sample_vector3(x * inverse_size, z * inverse_size)
		values[grid] = Vector3(
			sampled.x * choppiness[grid],
			sampled.y * scale_y,
			sampled.z * choppiness[grid]
		)
	return values


static func query(
	displacements: Array[CetoInterpolatedArray2D],
	world_x: float,
	world_z: float,
	sample_spectrum: Array[bool],
	num_grids: int,
	inverse_grid_sizes: Vector4,
	choppiness: Vector4,
	scale_y: float = 1.0,
	offset: Vector2 = Vector2.ZERO,
	mode: String = "position",
	min_error: float = 0.1
) -> Dictionary:
	assert(displacements.size() == GRID_COUNT, "Ceto queries require four grid buffers")
	assert(sample_spectrum.size() == GRID_COUNT, "Ceto queries require four sample flags")
	assert(num_grids >= 1 and num_grids <= GRID_COUNT)

	var enabled := 0
	for grid in range(num_grids):
		if sample_spectrum[grid]:
			enabled += 1

	var x := world_x + offset.x
	var z := world_z + offset.y
	var result: Array[Vector3] = []
	for _grid in range(GRID_COUNT):
		result.append(Vector3.ZERO)

	if enabled == 0:
		return {
			"height": 0.0,
			"displacement_x": 0.0,
			"displacement_z": 0.0,
			"iterations": 0,
			"error": 0.0,
			"displacement": result
		}

	if enabled == 1 or mode == "displacement":
		result = _sample_grids(
			displacements, sample_spectrum, num_grids,
			x, z, inverse_grid_sizes, choppiness, scale_y
		)
		var height_only := 0.0
		for value in result:
			height_only += value.y
		return {
			"height": clampf(height_only, -MAX_SPECTRUM_WAVE_HEIGHT, MAX_SPECTRUM_WAVE_HEIGHT),
			"displacement_x": 0.0,
			"displacement_z": 0.0,
			"iterations": 0,
			"error": 0.0,
			"displacement": result
		}

	var dx := x
	var dz := z
	var u := x
	var v := z
	var threshold := maxf(min_error, MIN_ERROR)
	var threshold_squared := threshold * threshold
	var error := INF
	var displacement_x := 0.0
	var displacement_z := 0.0
	var iterations := 0

	while true:
		u += x - dx
		v += z - dz
		result = _sample_grids(
			displacements, sample_spectrum, num_grids,
			u, v, inverse_grid_sizes, choppiness, scale_y
		)
		displacement_x = 0.0
		displacement_z = 0.0
		var height := 0.0
		for value in result:
			displacement_x += value.x
			displacement_z += value.z
			height += value.y

		dx = u + displacement_x
		dz = v + displacement_z
		iterations += 1
		var error_x := x - dx
		var error_z := z - dz
		error = error_x * error_x + error_z * error_z
		if not (error > threshold_squared and iterations <= MAX_ITERATIONS):
			break

	var total_height := 0.0
	for value in result:
		total_height += value.y

	return {
		"height": clampf(total_height, -MAX_SPECTRUM_WAVE_HEIGHT, MAX_SPECTRUM_WAVE_HEIGHT),
		"displacement_x": displacement_x,
		"displacement_z": displacement_z,
		"iterations": iterations,
		"error": error,
		"displacement": result
	}
