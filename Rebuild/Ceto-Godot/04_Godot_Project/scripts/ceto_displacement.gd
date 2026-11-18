extends RefCounted
class_name CetoDisplacement

## CPU translation of Ceto InitSpectrumDisplacementsTask.
## Evolves packed frequency coefficients in time, mirrors negative-frequency
## indices, combines up to four grids, and builds normalized slope buffers.

const TWO_PI := TAU


static func _evolve_grid(
	current: Vector4,
	mirrored: Vector4,
	channel: int,
	angular_frequency: float,
	time_value: float
) -> Vector2:
	var real_value := current[channel]
	var imaginary_value := current[channel + 1]
	var mirrored_real := mirrored[channel]
	var mirrored_imaginary := mirrored[channel + 1]
	var phase := angular_frequency * time_value
	var cosine := cos(phase)
	var sine := sin(phase)
	return Vector2(
		(real_value + mirrored_real) * cosine - (imaginary_value + mirrored_imaginary) * sine,
		(real_value - mirrored_real) * sine + (imaginary_value - mirrored_imaginary) * cosine
	)


static func _slope_for_grid(
	height: Vector2,
	st_x: float,
	st_y: float,
	inverse_grid_size: float
) -> Vector2:
	var kx := st_x * inverse_grid_size
	var ky := st_y * inverse_grid_size
	var wave_number := sqrt(kx * kx + ky * ky)
	var inverse_wave_number := 0.0 if wave_number == 0.0 else 1.0 / wave_number
	var normal_x := -(kx * height.y) - ky * height.x
	var normal_y := kx * height.x - ky * height.y
	return Vector2(normal_x * inverse_wave_number, normal_y * inverse_wave_number)


static func initialize(
	spectrum_data: Dictionary,
	size: int,
	grid_sizes: Vector4,
	num_grids: int,
	time_value: float
) -> Dictionary:
	assert(size > 0, "Displacement size must be positive")
	assert(num_grids >= 1 and num_grids <= 4, "Ceto supports one through four grids")

	var spectrum01: PackedVector4Array = spectrum_data["spectrum01"]
	var spectrum23: PackedVector4Array = spectrum_data["spectrum23"]
	var wtable: PackedVector4Array = spectrum_data["wtable"]
	assert(spectrum01.size() == size * size, "Spectrum01 dimensions do not match")
	assert(wtable.size() == size * size, "WTable dimensions do not match")
	if num_grids > 2:
		assert(spectrum23.size() == size * size, "Spectrum23 dimensions do not match")

	var inverse_grid_sizes := Vector4(
		TWO_PI * float(size) / grid_sizes.x,
		TWO_PI * float(size) / grid_sizes.y,
		TWO_PI * float(size) / grid_sizes.z,
		TWO_PI * float(size) / grid_sizes.w
	)

	var data0 := PackedVector4Array()
	var data1 := PackedVector4Array()
	var data2 := PackedVector4Array()
	data0.resize(size * size)
	data1.resize(size * size)
	if num_grids > 2:
		data2.resize(size * size)

	for y in range(size):
		for x in range(size):
			var index := x + y * size
			var mirror_x := (size - x) % size
			var mirror_y := (size - y) % size
			var mirror_index := mirror_x + mirror_y * size
			var current01 := spectrum01[index]
			var mirrored01 := spectrum01[mirror_index]
			var current23 := spectrum23[index] if num_grids > 2 else Vector4.ZERO
			var mirrored23 := spectrum23[mirror_index] if num_grids > 2 else Vector4.ZERO
			var omega := wtable[index]

			var uv_x := float(x) / float(size)
			var uv_y := float(y) / float(size)
			var st_x := uv_x - 1.0 if uv_x > 0.5 else uv_x
			var st_y := uv_y - 1.0 if uv_y > 0.5 else uv_y

			var heights: Array[Vector2] = []
			var slopes: Array[Vector2] = []
			for grid in range(num_grids):
				var channel := (grid % 2) * 2
				var source := current01 if grid < 2 else current23
				var mirror_source := mirrored01 if grid < 2 else mirrored23
				var height := _evolve_grid(
					source,
					mirror_source,
					channel,
					omega[grid],
					time_value
				)
				heights.append(height)
				slopes.append(_slope_for_grid(height, st_x, st_y, inverse_grid_sizes[grid]))

			var output0 := Vector4.ZERO
			output0.x = heights[0].x
			output0.y = heights[0].y
			if num_grids > 1:
				output0.x -= heights[1].y
				output0.y += heights[1].x
			if num_grids > 2:
				output0.z = heights[2].x
				output0.w = heights[2].y
			if num_grids > 3:
				output0.z -= heights[3].y
				output0.w += heights[3].x
			data0[index] = output0

			var output1 := Vector4(slopes[0].x, slopes[0].y, 0.0, 0.0)
			if num_grids > 1:
				output1.z = slopes[1].x
				output1.w = slopes[1].y
			data1[index] = output1

			if num_grids > 2:
				var output2 := Vector4(slopes[2].x, slopes[2].y, 0.0, 0.0)
				if num_grids > 3:
					output2.z = slopes[3].x
					output2.w = slopes[3].y
				data2[index] = output2

	return {
		"displacement": data0,
		"slopes_01": data1,
		"slopes_23": data2
	}
