extends RefCounted
class_name CetoDotNetRandom

## Compatibility implementation of the legacy System.Random subtractive PRNG
## used by Unity's .NET Framework-era Ceto source. This preserves the seed-0
## NextDouble sequence used by SpectrumTask; it is not Godot's RNG algorithm.

const BIG := 2147483647
const SEED := 161803398

var _seed_array := PackedInt32Array()
var _inext := 0
var _inextp := 21


func _init(seed_value: int = 0) -> void:
	_seed_array.resize(56)
	var subtraction: int = BIG if seed_value == -2147483648 else absi(seed_value)
	var mj: int = SEED - subtraction
	if mj < 0:
		mj += BIG
	_seed_array[55] = mj
	var mk := 1

	for i in range(1, 55):
		var ii := (21 * i) % 55
		_seed_array[ii] = mk
		mk = mj - mk
		if mk < 0:
			mk += BIG
		mj = _seed_array[ii]

	for _pass in range(4):
		for i in range(1, 56):
			var index := 1 + (i + 30) % 55
			_seed_array[i] -= _seed_array[index]
			if _seed_array[i] < 0:
				_seed_array[i] += BIG


func _internal_sample() -> int:
	var next_index := _inext + 1
	if next_index >= 56:
		next_index = 1
	var next_pair_index := _inextp + 1
	if next_pair_index >= 56:
		next_pair_index = 1

	var result := _seed_array[next_index] - _seed_array[next_pair_index]
	if result == BIG:
		result -= 1
	if result < 0:
		result += BIG

	_seed_array[next_index] = result
	_inext = next_index
	_inextp = next_pair_index
	return result


func next_double() -> float:
	return float(_internal_sample()) / float(BIG)
