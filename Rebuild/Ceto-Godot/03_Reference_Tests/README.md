# Stage 03 — Independent FFT Reference Tests

Run with Python 3:

```sh
python3 Rebuild/Ceto-Godot/03_Reference_Tests/test_ceto_fft_reference.py
```

The test suite models the Ceto CPU radix-2 butterfly implementation and compares it with an independent direct 2D DFT for small random inputs. It also checks impulse, constant/DC amplitude, plane-wave bin placement, normalized GPU lookup coordinate decoding, and rejection of non-power-of-two sizes.

**Scope boundary:** these are CPU reference tests, not a Unity or Godot GPU shader test. A passing run validates the reference FFT algorithm and several mathematical invariants only. It does not establish CPU/GPU floating-point equivalence, Godot renderer compatibility, or visual ocean correctness.

Expected result: 6 tests pass.
