#!/usr/bin/env python3
"""Independent reference tests for Ceto's radix-2, 2D butterfly FFT.

This models the source algorithm. It does not execute Unity shaders or claim
GPU-driver equivalence; those checks require a renderer-backed test later.
"""
import cmath
import math
import random
import unittest


def bit_reverse(index, size):
    total, weight, mask = 0, 1, size // 2
    while mask:
        bit = 1 if (index & mask) > mask - 1 else 0
        total += bit * weight
        weight *= 2
        mask //= 2
    return total


def butterfly_table(size):
    if size <= 0 or size & (size - 1):
        raise ValueError("size must be a positive power of two")
    passes = size.bit_length() - 1
    table = []
    for stage in range(passes):
        blocks = 1 << (passes - 1 - stage)
        half_inputs = 1 << stage
        row = [None] * size
        for block in range(blocks):
            for k in range(half_inputs):
                i1 = block * half_inputs * 2 + k
                i2 = block * half_inputs * 2 + half_inputs + k
                if stage == 0:
                    j1, j2 = bit_reverse(i1, size), bit_reverse(i2, size)
                else:
                    j1, j2 = i1, i2
                theta = 2.0 * math.pi * (k * blocks) / size
                twiddle = complex(math.cos(theta), math.sin(theta))
                row[i1] = (j1, j2, twiddle)
                row[i2] = (j1, j2, -twiddle)
        table.append(row)
    return table


def ceto_fft2(values, size):
    """Ceto's X-then-Y FFT; input is seeded into ping-pong slot 1."""
    if len(values) != size * size:
        raise ValueError("expected size*size complex values")
    lookup = butterfly_table(size)
    buffers = [[0j] * (size * size), list(values)]
    stage_index = 0
    passes = size.bit_length() - 1

    for axis in (0, 1):
        for stage in range(passes):
            write_index = stage_index % 2
            read_index = (stage_index + 1) % 2
            source = buffers[read_index]
            destination = buffers[write_index]

            if axis == 0:
                for x in range(size):
                    j1, j2, twiddle = lookup[stage][x]
                    for y in range(size):
                        index = x + y * size
                        destination[index] = (
                            source[j1 + y * size] + twiddle * source[j2 + y * size]
                        )
            else:
                for y in range(size):
                    j1, j2, twiddle = lookup[stage][y]
                    for x in range(size):
                        index = x + y * size
                        destination[index] = (
                            source[x + j1 * size] + twiddle * source[x + j2 * size]
                        )
            stage_index += 1

    return buffers[(stage_index - 1) % 2]


def direct_dft2(values, size):
    """Slow independent positive-exponent 2D DFT; no normalization."""
    output = []
    for fy in range(size):
        for fx in range(size):
            total = 0j
            for y in range(size):
                for x in range(size):
                    phase = 2j * math.pi * (fx * x + fy * y) / size
                    total += values[x + y * size] * cmath.exp(phase)
            output.append(total)
    return output


class CetoFftReferenceTests(unittest.TestCase):
    def assertComplexListsAlmostEqual(self, actual, expected, tolerance=1e-9):
        self.assertEqual(len(actual), len(expected))
        for index, (left, right) in enumerate(zip(actual, expected)):
            self.assertLessEqual(
                abs(left - right), tolerance,
                f"sample {index}: {left!r} != {right!r}"
            )

    def test_random_input_matches_independent_direct_dft(self):
        for size in (2, 4, 8):
            rng = random.Random(1000 + size)
            values = [
                complex(rng.uniform(-1, 1), rng.uniform(-1, 1))
                for _ in range(size * size)
            ]
            self.assertComplexListsAlmostEqual(
                ceto_fft2(values, size), direct_dft2(values, size), 1e-9
            )

    def test_impulse_is_flat_and_unnormalized(self):
        for size in (2, 4, 8, 16, 32):
            values = [0j] * (size * size)
            values[0] = 1 + 0j
            self.assertComplexListsAlmostEqual(
                ceto_fft2(values, size), [1 + 0j] * (size * size), 1e-9
            )

    def test_constant_input_maps_to_unnormalized_dc(self):
        for size in (2, 4, 8, 16, 32):
            actual = ceto_fft2([1 + 0j] * (size * size), size)
            expected = [0j] * (size * size)
            expected[0] = complex(size * size, 0)
            self.assertComplexListsAlmostEqual(actual, expected, 1e-8)

    def test_plane_wave_peak_and_axis_order(self):
        size, fx, fy = 8, 2, 3
        values = [
            cmath.exp(-2j * math.pi * (fx * x + fy * y) / size)
            for y in range(size) for x in range(size)
        ]
        actual = ceto_fft2(values, size)
        expected = [0j] * (size * size)
        expected[fx + fy * size] = complex(size * size, 0)
        self.assertComplexListsAlmostEqual(actual, expected, 1e-8)

    def test_gpu_normalized_lookup_coordinates_select_same_texel(self):
        # Ceto stores j/(N-1) in the lookup texture and samples point/clamp.
        for size in (2, 4, 8, 16, 32, 64, 128, 512):
            for index in range(size):
                uv = index / (size - 1)
                decoded = min(size - 1, int(uv * size))
                self.assertEqual(decoded, index, (size, index, uv, decoded))

    def test_non_power_of_two_is_rejected(self):
        with self.assertRaises(ValueError):
            butterfly_table(12)


if __name__ == "__main__":
    unittest.main(verbosity=2)
