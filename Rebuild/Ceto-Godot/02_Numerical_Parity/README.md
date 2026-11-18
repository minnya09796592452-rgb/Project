# Ceto → Godot Rebuild — Numerical Parity Audit 02

**Stage:** 02 — spectrum initialization and FFT numerical contract  
**Reference branch:** `main` (read-only)  
**Work branch:** `ceto-rebuild`  
**Scope:** deterministic spectrum inputs, dispersion frequencies, CPU/GPU displacement initialization, butterfly FFT, and data packing.

## 1. Spectrum generation: confirmed numerical contract

### Frequency-grid indexing

For a square transform of size `N`:

- Linear index: `idx = x + y * N`.
- Signed frequency-bin coordinates: `i = x` when `x < N/2`, otherwise `i = x - N`; likewise for `j`.
- Each grid uses `dk = 2π / gridSize`.
- The spectrum sampler receives `(i * dk, j * dk)`.
- Frequencies below the per-grid low-frequency threshold are excluded.
- The spectral amplitude is `sqrt(S(kx, ky) * 0.5) * dk`; NaN and infinity are replaced with zero.

### Random phase and packed channels

`SpectrumTask` initializes `System.Random(0)`, so phase generation is deterministic for a fixed iteration order and runtime math behavior.

For each active grid, a random phase `φ` is generated over `[0, 2π)`; the complex coefficient is:

`amplitude * (cos(φ), sin(φ)) * sqrt(2)`

Packing:
- Grid 1 → `Spectrum01.rg`
- Grid 2 → `Spectrum01.ba`
- Grid 3 → `Spectrum23.rg`
- Grid 4 → `Spectrum23.ba`

**Port requirement:** preserve the exact iteration order and number of random draws for every grid count. Replacing the PRNG or changing the order of the grid loops changes the generated ocean even when the spectrum formula is unchanged.

## 2. WTable / dispersion relation

The source computes:

- `inverseGridSize = 2π * N / gridSize`
- Signed normalized coordinate `st = (x/N, y/N)`, wrapped into the negative half-range when a coordinate is greater than 0.5.
- Wave-number magnitude `k = length(st * inverseGridSize)`
- Angular frequency `ω = sqrt(g * k * (1 + k² / k_m²))`

Constants in `SpectrumTask`:
- `g = 9.818286`
- `k_m = 370.0`

The WTable stores one angular frequency per active grid in RGBA channels. It is used by both CPU and GPU initializers.

## 3. CPU/GPU displacement initialization comparison

### Shared operations confirmed

Both `InitSpectrumDisplacementsTask` and `InitDisplacement.shader` implement the same high-level sequence:

1. Map texture/grid coordinates to signed `st`.
2. Read the spectrum coefficient at the current coordinate and its mirrored coordinate `(-x mod N, -y mod N)`.
3. Read the per-grid angular frequency from WTable.
4. Apply time evolution using cosine and sine of `ω * time`.
5. Combine multiple grid components into packed complex displacement channels.
6. Compute horizontal displacement from the complex height and wave vector, scaled by inverse wave-number magnitude; zero wave number maps to zero inverse magnitude.

The CPU mirror index is explicitly:
`j = ((N - x) % N) + ((N - y) % N) * N`.

The GPU shader samples the mirrored coordinate using `Ceto_Offset - uv`; `WaveSpectrumBufferGPU` sets `Ceto_Offset = (1 + 0.5/N, 1 + 0.5/N)`. This is intended to address texel-center sampling while wrapping the mirrored sample.

### Grid combination / packing

- One grid: height complex pair and its horizontal-displacement pair.
- Two grids: height uses `h1 + i*h2`; the two horizontal displacement pairs occupy the second output.
- Three grids: grids 1+2 share the first packed height pair; grid 3 occupies the second; displacement data is split across two further packed outputs.
- Four grids: grids 1+2 and 3+4 are combined in pairs for height; horizontal displacement for each grid is packed across the three output buffers.

The CPU and GPU expressions are algebraically aligned in the inspected one-, two-, three-, and four-grid paths. This is a **source-level parity assessment**, not yet a measured bitwise or tolerance-based numerical pass.

### Items still requiring numerical tests

- Shader UV/texel-center behavior for all coordinates, especially 0 and N−1.
- Repeat/clamp sampler behavior for the mirrored spectrum coordinate.
- Float precision differences between CPU `Mathf` and GPU shader `sin/cos/length`.
- Output channel packing for each grid count.
- Cancellation and partially completed CPU tasks must never publish output buffers.

## 4. FFT parity

### Butterfly table

Both `FourierCPU` and `FourierGPU`:
- Require power-of-two transform size.
- Use `passes = log2(N)`.
- Compute `nBlocks = 2^(passes - 1 - stage)` and `nHInputs = 2^stage`.
- Apply bit-reversed indices only on stage zero.
- Compute twiddle factors from `θ = 2π * (k * nBlocks) / N`.
- Store the second branch with negated twiddle components.

GPU lookup data stores `j1/(N-1)`, `j2/(N-1)`, `cos θ`, and `sin θ` in an RGBAFloat, point-filtered, clamp-wrapped 1D texture for each stage. CPU stores integer indices and float twiddle values directly.

### Butterfly operation

For complex input `a`, `b`, and twiddle `w`, both paths compute `a + w*b`. Packed GPU `float4` handles two complex values; CPU `Vector4` double-packed mode does the same.

### Axis order and normalization

Both implementations execute all X-axis stages, then all Y-axis stages. The inspected FFT code contains no explicit division by `N` or `N²`; the transform is unnormalized at this layer. Do not add normalization during porting unless another downstream stage is shown to compensate for it.

### Numerical parity verdict

<verdict>PARTIAL — same algorithmic structure confirmed; no executable numerical comparison performed.</verdict>

A valid parity test must compare CPU and GPU output arrays for the same initial buffers and size, not compare rendered screenshots. Use absolute and relative error metrics and inspect every channel.

## 5. Required numerical test matrix

| Test | Input / configuration | Required assertion |
|---|---|---|
| Butterfly lookup | N = 32, 64, 128 | CPU integer indices match decoded GPU lookup indices |
| FFT impulse | One nonzero complex sample | CPU/GPU outputs match within declared tolerance |
| FFT constant | All samples equal | DC placement and unnormalized amplitude agree |
| FFT single-frequency | Known complex sinusoid | Peak bin and phase agree |
| Axis separation | X-only and Y-only inputs | X/Y stage orientation agrees |
| Grid packing | 1, 2, 3, 4 grids | Every packed channel maps to expected grid |
| Mirrored sampling | corners and edge coordinates | CPU mirrored index equals GPU sampled texel |
| Time evolution | time = 0 and nonzero time | CPU/GPU complex rotation agrees |
| Zero wave number | DC bin | No NaN/Inf; horizontal displacement is zero |
| Random phase | repeated same seed/configuration | generated spectrum arrays are deterministic |

Suggested numerical thresholds must be established empirically for the target precision and GPU; no tolerance is invented in this audit.

## 6. Source references and blob IDs

| Source file | Blob SHA |
|---|---|
| `Scripts/Spectrum/Tasks/SpectrumTask.cs` | `48512fef8b70ac20bacc52bb9d5965269f5b7efe` |
| `Scripts/Spectrum/Conditions/UnifiedSpectrum.cs` | `(verify from source tree before final manifest)` |
| `Scripts/Spectrum/Conditions/UnifiedSpectrumCondition.cs` | `8f5e56da6b172b879eb4f0b3df1c3204ff316af3` |
| `Scripts/Spectrum/Tasks/InitSpectrumDisplacementsTask.cs` | `abb15f06d5841b996d30a3da7a9d874f37e0978b` |
| `Scripts/Spectrum/Fourier/FourierCPU.cs` | `6f19cb9a0032de17de8174d9dc39e4a6ae74f738` |
| `Scripts/Spectrum/Fourier/FourierGPU.cs` | `c89c373b39c379c8aa72c0e6b996e3ea6db9fad6` |
| `Shaders/InitDisplacement.shader` | `272019a930d59f32046326178c2e958940f360b7` |
| `Shaders/Fourier.shader` | `63465f5802019781dd7fdd5caac1604733d6c4d7` |

The UnifiedSpectrum blob SHA is intentionally marked for verification rather than guessed.

## 7. Porting gate

Do not start translating the FFT shader into a Godot shader until:
- the CPU/GPU parity harness exists;
- the butterfly lookup decode test passes;
- FFT test vectors pass for at least N=32 and N=64;
- mirrored UV sampling and channel packing are validated;
- the Godot renderer's float texture and compute/MRT capabilities are measured on the target device.

## Status

- [x] Deterministic spectrum generation inspected.
- [x] Dispersion/WTable formula inspected.
- [x] CPU/GPU initialization expressions compared at source level.
- [x] CPU/GPU butterfly generation and FFT operation compared at source level.
- [ ] Numerical test harness.
- [ ] GPU precision/tolerance measurement.
- [ ] Target-device capability test.
- [ ] Godot implementation.

**Next task:** build the parity test harness specification and independent CPU reference vectors before writing the Godot GPU backend.
