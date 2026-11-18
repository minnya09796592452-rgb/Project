extends RefCounted
class_name CetoSpectrum

## Numerical spectrum equations translated from Ceto 1.1.4:
## Unified directional spectrum (Elfouhaily et al. 1997), Phillips spectrum,
## and the per-grid dispersion-frequency lookup table.

const GRAVITY := 9.818286
const WAVE_CM := 0.23
const WAVE_KM := 370.0
const PI_2 := TAU


static func _sqr(value: float) -> float:
	return value * value


static func dispersion_omega(wave_number: float) -> float:
	return sqrt(GRAVITY * wave_number * (1.0 + _sqr(wave_number / WAVE_KM)))


static func unified_parameters(wind_speed: float, wind_direction_degrees: float, wave_age: float) -> Dictionary:
	assert(wind_speed > 0.0, "Unified spectrum requires positive wind speed")
	assert(wave_age > 0.0, "Unified spectrum requires positive wave age")

	var theta := wind_direction_degrees * PI / 180.0
	var wind_direction := Vector2(cos(theta), sin(theta))
	var u10 := wind_speed
	var sqrt_10 := sqrt(10.0)
	var gravity_squared_omega_u10 := GRAVITY * _sqr(wave_age / u10)
	var z_squared_u10_g := 3.7e-5 * _sqr(u10) / 9.81
	var log_omega_6 := log(wave_age) * 6.0
	var sigma := 0.08 * (1.0 + 4.0 / pow(wave_age, 3.0))
	var sq_sigma_2 := _sqr(sigma) * 2.0
	var alpha_p := 0.006 * sqrt(wave_age)
	var log_2_4 := log(2.0) / 4.0

	var kp := gravity_squared_omega_u10
	var cp := dispersion_omega(kp) / kp
	var z0 := z_squared_u10_g * pow(u10 / cp, 0.9)
	var u_star := 0.41 * u10 / log(10.0 / z0)
	var gamma := 1.7 if wave_age < 1.0 else 1.7 + log_omega_6
	var half_alpha_p_cp := 0.5 * alpha_p * cp
	var alpham := 0.01 * (
		1.0 + log(u_star / WAVE_CM)
		if u_star < WAVE_CM
		else 1.0 + 3.0 * log(u_star / WAVE_CM)
	)
	var half_alpham_wave_cm := 0.5 * alpham * WAVE_CM
	var am := 0.13 * u_star / WAVE_CM

	return {
		"wind_speed": wind_speed,
		"wave_age": wave_age,
		"wind_direction": wind_direction,
		"sqrt_10": sqrt_10,
		"kp": kp,
		"cp": cp,
		"sq_sigma_2": sq_sigma_2,
		"gamma": gamma,
		"half_alpha_p_cp": half_alpha_p_cp,
		"half_alpham_wave_cm": half_alpham_wave_cm,
		"log_2_4": log_2_4,
		"am": am
	}


static func unified_sample(kx: float, ky: float, parameters: Dictionary) -> float:
	var wind_direction: Vector2 = parameters["wind_direction"]
	var rotated_x := kx * wind_direction.x - ky * wind_direction.y
	var rotated_y := kx * wind_direction.y + ky * wind_direction.x
	var k := sqrt(rotated_x * rotated_x + rotated_y * rotated_y)
	if k <= 0.0 or not is_finite(k):
		return 0.0

	var c := dispersion_omega(k) / k
	var kp: float = parameters["kp"]
	var cp: float = parameters["cp"]
	var wave_age: float = parameters["wave_age"]
	var lpm := exp(-1.25 * _sqr(kp / k))
	var gamma_peak := exp(-_sqr(sqrt(k / kp) - 1.0) / float(parameters["sq_sigma_2"]))
	var jp := pow(float(parameters["gamma"]), gamma_peak)
	var fp := lpm * jp * exp(-wave_age / float(parameters["sqrt_10"]) * (sqrt(k / kp) - 1.0))
	var bl := float(parameters["half_alpha_p_cp"]) / c * fp
	var fm := exp(-0.25 * _sqr(k / WAVE_KM - 1.0))
	var bh := float(parameters["half_alpham_wave_cm"]) / c * fm * lpm
	var delta := tanh(
		float(parameters["log_2_4"])
		+ 4.0 * pow(c / cp, 2.5)
		+ float(parameters["am"]) * pow(WAVE_CM / c, 2.5)
	)
	var phi := atan2(rotated_y, rotated_x)

	if rotated_x < 0.0:
		return 0.0

	bl *= 2.0
	bh *= 2.0
	var tweak := sqrt(maxf(rotated_x / k, 0.0))
	var result := (bl + bh) * (1.0 + delta * cos(2.0 * phi)) / (PI_2 * k * k * k * k) * tweak
	return result if is_finite(result) else 0.0


static func phillips_parameters(wind_speed: float, wind_direction_degrees: float) -> Dictionary:
	var theta := wind_direction_degrees * PI / 180.0
	var wind_direction := Vector2(cos(theta), sin(theta))
	var length := wind_speed * wind_speed / GRAVITY
	var length_squared := length * length
	var damping := 0.001
	return {
		"wind_direction": wind_direction,
		"length_squared": length_squared,
		"damped_length_squared": length_squared * damping * damping,
		"amplitude": 0.02
	}


static func phillips_sample(kx: float, ky: float, parameters: Dictionary) -> float:
	var wind_direction: Vector2 = parameters["wind_direction"]
	var rotated_x := kx * wind_direction.x - ky * wind_direction.y
	var rotated_y := kx * wind_direction.y + ky * wind_direction.x
	var wave_number := sqrt(rotated_x * rotated_x + rotated_y * rotated_y)
	if wave_number < 0.000001:
		return 0.0

	var wave_number_squared := wave_number * wave_number
	var wave_number_fourth := wave_number_squared * wave_number_squared
	rotated_x /= wave_number
	rotated_y /= wave_number
	var k_dot_w := rotated_x
	var k_dot_w_sixth := pow(k_dot_w, 6.0)
	var length_squared: float = parameters["length_squared"]
	var damped_length_squared: float = parameters["damped_length_squared"]
	var result := (
		float(parameters["amplitude"])
		* exp(-1.0 / (wave_number_squared * length_squared))
		/ wave_number_fourth
		* k_dot_w_sixth
		* exp(-wave_number_squared * damped_length_squared)
	)
	return result if is_finite(result) else 0.0


## Returns row-major Vector4 frequencies, with unused grid channels left at zero.
static func build_w_table(size: int, grid_sizes: Vector4, num_grids: int) -> PackedVector4Array:
	assert(size > 0, "WTable size must be positive")
	assert(num_grids >= 1 and num_grids <= 4, "Ceto supports one through four grids")
	var sizes := [grid_sizes.x, grid_sizes.y, grid_sizes.z, grid_sizes.w]
	for grid in range(num_grids):
		assert(sizes[grid] > 0.0, "Grid sizes must be positive")

	var inverse_grid_sizes_squared: Array[float] = []
	for grid in range(4):
		var inverse := PI_2 * float(size) / sizes[grid]
		inverse_grid_sizes_squared.append(inverse * inverse)

	var output := PackedVector4Array()
	output.resize(size * size)
	for y in range(size):
		for x in range(size):
			var st_x := float(x) / float(size)
			var st_y := float(y) / float(size)
			if st_x > 0.5:
				st_x -= 1.0
			if st_y > 0.5:
				st_y -= 1.0
			var radial_squared := st_x * st_x + st_y * st_y
			var frequencies := Vector4.ZERO
			for grid in range(num_grids):
				var wave_number := sqrt(radial_squared * inverse_grid_sizes_squared[grid])
				frequencies[grid] = dispersion_omega(wave_number)
			output[x + y * size] = frequencies
	return output
