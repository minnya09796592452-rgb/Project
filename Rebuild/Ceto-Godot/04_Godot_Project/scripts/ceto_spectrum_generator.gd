extends RefCounted
class_name CetoSpectrumGenerator

## Deterministic port of Ceto SpectrumTask packing and WTable construction.
## Random phases use the legacy .NET System.Random(0) sequence, and packed
## channels follow Spectrum01 RG/BA and Spectrum23 RG/BA exactly.

const SpectrumMath = preload("res://scripts/ceto_spectrum.gd")
const DotNetRandom = preload("res://scripts/ceto_dotnet_random.gd")
const SQRT_TWO := 1.414213562


static func grid_configuration(spectrum_type: String, num_grids: int) -> Dictionary:
	assert(num_grids >= 1 and num_grids <= 4, "Ceto supports one through four grids")
	var sizes := Vector4.ONE
	var choppiness := Vector4.ONE
	var amplitudes := Vector4.ONE

	if spectrum_type == "unified":
		match num_grids:
			1:
				sizes = Vector4(772.0, 1.0, 1.0, 1.0)
				choppiness = Vector4(2.3, 1.0, 1.0, 1.0)
			2:
				sizes = Vector4(772.0, 57.0, 1.0, 1.0)
				choppiness = Vector4(2.3, 2.1, 1.0, 1.0)
			3:
				sizes = Vector4(1372.0, 392.0, 28.0, 1.0)
				choppiness = Vector4(2.3, 2.1, 1.6, 1.0)
			4:
				sizes = Vector4(1372.0, 392.0, 28.0, 4.0)
				choppiness = Vector4(2.3, 2.1, 1.6, 0.9)
	elif spectrum_type == "phillips":
		match num_grids:
			1:
				sizes = Vector4(217.0, 1.0, 1.0, 1.0)
				choppiness = Vector4(1.5, 1.0, 1.0, 1.0)
				amplitudes = Vector4(0.5, 1.0, 1.0, 1.0)
			2:
				sizes = Vector4(217.0, 97.0, 1.0, 1.0)
				choppiness = Vector4(1.5, 1.2, 1.0, 1.0)
				amplitudes = Vector4(0.5, 1.0, 1.0, 1.0)
			3:
				sizes = Vector4(217.0, 97.0, 31.0, 1.0)
				choppiness = Vector4(1.5, 1.2, 1.0, 1.0)
				amplitudes = Vector4(0.5, 1.0, 1.0, 1.0)
			4:
				sizes = Vector4(1372.0, 217.0, 97.0, 31.0)
				choppiness = Vector4(1.5, 1.2, 1.0, 1.0)
				amplitudes = Vector4(0.25, 0.5, 1.0, 1.0)
	else:
		assert(false, "Unknown Ceto spectrum type: " + spectrum_type)

	return {
		"grid_sizes": sizes,
		"choppiness": choppiness,
		"wave_amplitudes": amplitudes
	}


static func _sample_spectrum(
	kx: float,
	ky: float,
	amplitude: float,
	spectrum_type: String,
	parameters: Dictionary
) -> float:
	if spectrum_type == "unified":
		return SpectrumMath.unified_sample(kx, ky, parameters)
	return SpectrumMath.phillips_sample(kx, ky, parameters)


static func _get_spectrum_sample(
	i: float,
	j: float,
	dk: float,
	k_min: float,
	amplitude: float,
	spectrum_type: String,
	parameters: Dictionary
) -> float:
	var kx := i * dk
	var ky := j * dk
	if absf(kx) < k_min and absf(ky) < k_min:
		return 0.0

	var spectrum_value := _sample_spectrum(kx, ky, amplitude, spectrum_type, parameters) * amplitude
	if spectrum_value <= 0.0 or not is_finite(spectrum_value):
		return 0.0
	var height := sqrt(spectrum_value * 0.5) * dk
	return height if is_finite(height) else 0.0


static func generate(
	size: int,
	spectrum_type: String,
	parameters: Dictionary,
	grid_sizes: Vector4,
	wave_amplitudes: Vector4,
	num_grids: int
) -> Dictionary:
	assert(size > 0, "Spectrum size must be positive")
	assert(num_grids >= 1 and num_grids <= 4, "Ceto supports one through four grids")

	var sizes := [grid_sizes.x, grid_sizes.y, grid_sizes.z, grid_sizes.w]
	var amplitudes := [wave_amplitudes.x, wave_amplitudes.y, wave_amplitudes.z, wave_amplitudes.w]
	var dk := PackedFloat64Array()
	var k_min := PackedFloat64Array()
	for grid in range(4):
		dk.append(SpectrumMath.PI_2 / sizes[grid])
		if grid == 0:
			k_min.append(PI / sizes[grid])
		else:
			k_min.append(PI * float(size) / sizes[grid])

	var spectrum01 := PackedVector4Array()
	spectrum01.resize(size * size)
	var spectrum23 := PackedVector4Array()
	if num_grids > 2:
		spectrum23.resize(size * size)

	var random := DotNetRandom.new(0)
	var half_size := size >> 1

	for y in range(size):
		for x in range(size):
			var index := x + y * size
			var signed_x := float(x - size) if x >= half_size else float(x)
			var signed_y := float(y - size) if y >= half_size else float(y)
			var packed01 := Vector4.ZERO
			var packed23 := Vector4.ZERO

			for grid in range(num_grids):
				# Ceto draws the random phase before evaluating the spectrum.
				var phase := random.next_double() * SpectrumMath.PI_2
				var height := _get_spectrum_sample(
					signed_x,
					signed_y,
					dk[grid],
					k_min[grid],
					amplitudes[grid],
					spectrum_type,
					parameters
				)
				var complex_value := Vector2(
					height * cos(phase) * SQRT_TWO,
					height * sin(phase) * SQRT_TWO
				)

				match grid:
					0:
						packed01.x = complex_value.x
						packed01.y = complex_value.y
					1:
						packed01.z = complex_value.x
						packed01.w = complex_value.y
					2:
						packed23.x = complex_value.x
						packed23.y = complex_value.y
					3:
						packed23.z = complex_value.x
						packed23.w = complex_value.y

			spectrum01[index] = packed01
			if num_grids > 2:
				spectrum23[index] = packed23

	return {
		"spectrum01": spectrum01,
		"spectrum23": spectrum23,
		"wtable": SpectrumMath.build_w_table(size, grid_sizes, num_grids)
	}
