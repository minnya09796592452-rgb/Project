extends RefCounted
class_name CetoFourier

## CPU radix-2 2D FFT port of Ceto 1.1.4 FourierGPU's butterfly schedule.
## Complex values are stored as Vector2(real, imaginary).
## Preserves Ceto's positive-exponent twiddle convention, X-then-Y order,
## bit-reversal lookup, and unnormalized output. This is a CPU reference path;
## it is not a GPU shader or a claim of GPU parity.

static func is_power_of_two(value: int) -> bool:
	return value > 0 and (value & (value - 1)) == 0


static func bit_reverse(index: int, size: int) -> int:
	var total := 0
	var weight := 1
	var mask: int = size >> 1
	while mask != 0:
		var bit := 1 if (index & mask) > mask - 1 else 0
		total += bit * weight
		weight *= 2
		mask >>= 1
	return total


static func _complex_multiply(left: Vector2, right: Vector2) -> Vector2:
	return Vector2(
		left.x * right.x - left.y * right.y,
		left.y * right.x + left.x * right.y
	)


static func _build_butterfly_table(size: int) -> Array:
	assert(is_power_of_two(size), "Ceto FFT size must be a positive power of two")
	var pass_count := 0
	var remaining := size
	while remaining > 1:
		remaining >>= 1
		pass_count += 1
	var table: Array = []

	for stage in range(pass_count):
		var block_count := 1 << (pass_count - 1 - stage)
		var half_inputs := 1 << stage
		var indices := PackedInt32Array()
		var twiddles := PackedVector2Array()
		indices.resize(size * 2)
		twiddles.resize(size)

		for block in range(block_count):
			for k in range(half_inputs):
				var first := block * half_inputs * 2 + k
				var second := first + half_inputs
				var j1 := bit_reverse(first, size) if stage == 0 else first
				var j2 := bit_reverse(second, size) if stage == 0 else second
				var theta := TAU * float(k * block_count) / float(size)
				var twiddle := Vector2(cos(theta), sin(theta))

				indices[first * 2] = j1
				indices[first * 2 + 1] = j2
				indices[second * 2] = j1
				indices[second * 2 + 1] = j2
				twiddles[first] = twiddle
				twiddles[second] = -twiddle

		table.append({"indices": indices, "twiddles": twiddles})

	return table


## Creates the RGBAF butterfly lookup textures consumed by ceto_fourier_stage.gdshader.
## Each stage stores normalized source indices in RG and the complex twiddle in BA.
static func create_butterfly_lookup_textures(size: int) -> Array[ImageTexture]:
	assert(is_power_of_two(size), "Ceto FFT size must be a positive power of two")
	var lookup := _build_butterfly_table(size)
	var textures: Array[ImageTexture] = []
	var denominator := float(maxi(size - 1, 1))

	for stage in range(lookup.size()):
		var image := Image.create(size, 1, false, Image.FORMAT_RGBAF)
		var stage_data: Dictionary = lookup[stage]
		var indices: PackedInt32Array = stage_data["indices"]
		var twiddles: PackedVector2Array = stage_data["twiddles"]

		for x in range(size):
			var j1 := float(indices[x * 2]) / denominator
			var j2 := float(indices[x * 2 + 1]) / denominator
			var twiddle := twiddles[x]
			image.set_pixel(x, 0, Color(j1, j2, twiddle.x, twiddle.y))

		textures.append(ImageTexture.create_from_image(image))

	return textures

## input_data is row-major: index = x + y * size.
## Returns a new PackedVector2Array; input_data is not modified.
static func transform_2d(input_data: PackedVector2Array, size: int) -> PackedVector2Array:
	assert(is_power_of_two(size), "Ceto FFT size must be a positive power of two")
	assert(input_data.size() == size * size, "FFT input length must equal size * size")

	if size == 1:
		return input_data.duplicate()

	var lookup := _build_butterfly_table(size)
	var buffers: Array[PackedVector2Array] = [
		PackedVector2Array(),
		input_data.duplicate()
	]
	var pass_index := 0
	var pass_count := lookup.size()

	# Match Ceto's order: all X stages, then all Y stages.
	for axis in range(2):
		for stage in range(pass_count):
			var write_index := pass_index % 2
			var read_index := (pass_index + 1) % 2
			var source: PackedVector2Array = buffers[read_index]
			var destination := PackedVector2Array()
			destination.resize(size * size)

			var stage_data: Dictionary = lookup[stage]
			var indices: PackedInt32Array = stage_data["indices"]
			var twiddles: PackedVector2Array = stage_data["twiddles"]

			if axis == 0:
				for x in range(size):
					var j1 := indices[x * 2]
					var j2 := indices[x * 2 + 1]
					var twiddle := twiddles[x]
					for y in range(size):
						var output_index := x + y * size
						var a := source[j1 + y * size]
						var b := _complex_multiply(twiddle, source[j2 + y * size])
						destination[output_index] = a + b
			else:
				for y in range(size):
					var j1 := indices[y * 2]
					var j2 := indices[y * 2 + 1]
					var twiddle := twiddles[y]
					for x in range(size):
						var output_index := x + y * size
						var a := source[x + j1 * size]
						var b := _complex_multiply(twiddle, source[x + j2 * size])
						destination[output_index] = a + b

			buffers[write_index] = destination
			pass_index += 1

	return buffers[(pass_index - 1) % 2]
