extends RefCounted
class_name CetoInterpolatedArray2D

## Bilinear, multi-channel 2D data array matching Ceto InterpolatedArray2f.
## Coordinates are normalized; wrap and half-pixel behavior follow the source.

var size_x: int
var size_y: int
var channels: int
var wrap: bool
var half_pixel_offset := true
var data := PackedFloat32Array()


func _init(width: int, height: int, channel_count: int = 3, should_wrap: bool = true) -> void:
	assert(width > 0 and height > 0 and channel_count > 0)
	size_x = width
	size_y = height
	channels = channel_count
	wrap = should_wrap
	data.resize(size_x * size_y * channels)


func clear() -> void:
	data.fill(0.0)


func set_value(x: int, y: int, channel: int, value: float) -> void:
	assert(x >= 0 and x < size_x and y >= 0 and y < size_y)
	assert(channel >= 0 and channel < channels)
	data[(x + y * size_x) * channels + channel] = value


func get_value(x: int, y: int, channel: int) -> float:
	assert(x >= 0 and x < size_x and y >= 0 and y < size_y)
	assert(channel >= 0 and channel < channels)
	return data[(x + y * size_x) * channels + channel]


func _index_pair(coordinate: float, extent: int) -> Vector2i:
	var base := int(coordinate)
	var next := base + (1 if coordinate > 0.0 else (-1 if coordinate < 0.0 else 0))
	if wrap:
		if base >= extent or base <= -extent:
			base %= extent
		if base < 0:
			base = extent + base
		if next >= extent or next <= -extent:
			next %= extent
		if next < 0:
			next = extent + next
	else:
		base = clampi(base, 0, extent - 1)
		next = clampi(next, 0, extent - 1)
	return Vector2i(base, next)


func sample_uv(u: float, v: float) -> PackedFloat32Array:
	var x := u
	var y := v
	if half_pixel_offset:
		x = x * float(size_x) - 0.5
		y = y * float(size_y) - 0.5
	else:
		x *= float(size_x - 1)
		y *= float(size_y - 1)

	var fx := absf(x - float(int(x)))
	var fy := absf(y - float(int(y)))
	var x_indices := _index_pair(x, size_x)
	var y_indices := _index_pair(y, size_y)
	var result := PackedFloat32Array()
	result.resize(channels)

	for channel in range(channels):
		var v00 := get_value(x_indices.x, y_indices.x, channel)
		var v10 := get_value(x_indices.y, y_indices.x, channel)
		var v01 := get_value(x_indices.x, y_indices.y, channel)
		var v11 := get_value(x_indices.y, y_indices.y, channel)
		var top := v00 * (1.0 - fx) + v10 * fx
		var bottom := v01 * (1.0 - fx) + v11 * fx
		result[channel] = top * (1.0 - fy) + bottom * fy

	return result


func sample_vector3(u: float, v: float) -> Vector3:
	assert(channels >= 3, "Vector3 sampling requires at least three channels")
	var values := sample_uv(u, v)
	return Vector3(values[0], values[1], values[2])
