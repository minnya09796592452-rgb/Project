# Ceto → Godot Rebuild — Dependency Audit 01

**Stage:** 01 — spectrum / FFT dependency audit  
**Reference:** `main` (read-only)  
**Work branch:** `ceto-rebuild`  
**Audit scope:** spectrum condition generation, GPU and CPU displacement paths, FFT buffers, derived slope/foam buffers, and wave-query parity.

## 1. Critical correction: CPU and GPU initialization are separate

The source confirms two different execution paths. `InitSpectrumDisplacementsTask` is **CPU displacement initialization only**: its constructor requires `DisplacementBufferCPU`. It is not the GPU initializer.

- **CPU displacement:** `DisplacementBufferCPU.Initilize` creates/resets `InitSpectrumDisplacementsTask`; that task builds frequency-domain displacement arrays, then `FourierTask` runs `FourierCPU`.
- **GPU displacement:** `WaveSpectrumBufferGPU.Initilize` binds spectrum and frequency textures to an initialization material; `Shaders/InitDisplacement.shader` writes the initial GPU buffers; `FourierGPU` transforms those buffers.
- **Slopes and Jacobian/foam:** both use `WaveSpectrumBufferGPU` and their own initialization shaders, regardless of the CPU/GPU displacement selection.

This distinction is important for a faithful port. A single shared initializer would not reproduce the original architecture.

## 2. Source-backed dependency graph

```text
Ocean.Update()
  └─ WaveSpectrum.Update()
      ├─ CreateBuffers()
      │   ├─ DisplacementBufferCPU OR DisplacementBufferGPU
      │   ├─ WaveSpectrumBufferGPU (2 buffers)  -> slopes
      │   └─ WaveSpectrumBufferGPU (3 buffers)  -> Jacobians / foam
      ├─ CreateRenderTextures()
      ├─ CreateConditions()
      │   └─ WaveSpectrumCondition
      │       └─ SpectrumTask
      │           ├─ ISpectrum implementation (Unified / Phillips / Custom)
      │           ├─ frequency spectrum arrays
      │           └─ WTable
      ├─ UpdateSpectrumScheduler()
      ├─ GenerateDisplacement(time)
      │   ├─ CPU: DisplacementBufferCPU
      │   │   ├─ InitSpectrumDisplacementsTask
      │   │   └─ FourierTask -> FourierCPU
      │   └─ GPU: DisplacementBufferGPU
      │       └─ WaveSpectrumBufferGPU
      │           ├─ InitDisplacement.shader
      │           └─ FourierGPU -> Fourier.shader
      ├─ GenerateSlopes(time)
      │   └─ WaveSpectrumBufferGPU
      │       ├─ InitSlope.shader
      │       └─ FourierGPU -> Fourier.shader
      └─ GenerateFoam(time)
          └─ WaveSpectrumBufferGPU
              ├─ InitJacobians.shader
              └─ FourierGPU -> Fourier.shader

Wave-query branch:
  WaveSpectrum.QueryWaves()
    └─ IDisplacementBuffer.QueryWaves()
        └─ QueryDisplacements.QueryWaves()
            └─ InterpolatedArray2f data (3 channels per grid)
```

## 3. Condition generation contract

### Confirmed source behavior

- `WaveSpectrumCondition` owns `Spectrum01`, optional `Spectrum23`, `WTable`, matching CPU-side `Color[]` arrays, grid sizes, choppiness, wave amplitudes, and a completion flag.
- `SpectrumTask.Start()` creates the condition textures and marks the condition incomplete.
- `SpectrumTask.Run()` calls `CreateWTable()` and `GenerateWavesSpectrum()`.
- `SpectrumTask.End()` uploads the generated arrays with `Condition.Apply(...)`, records `LastUpdated`, and marks the condition done.
- `WaveSpectrum.CreateConditions()` creates the initial condition synchronously; changed conditions can be scheduled asynchronously and swapped into the active slot after completion. Conditions are cached by a condition key.
- `UnifiedSpectrumCondition` supports 1–4 grids. For four grids its configured grid sizes are `(1372, 392, 28, 4)`, with choppiness `(2.3, 2.1, 1.6, 0.9)`.

### Port requirement

Preserve deterministic condition keys, cache invalidation, condition-completion transitions, frequency spectrum data, WTable values, and grid configuration. Thread scheduling may be redesigned, but must not expose partially generated condition data to rendering.

## 4. GPU buffer / FFT contract

### Buffer lifecycle

- Each logical GPU buffer owns two RenderTexture slots (read/write ping-pong).
- The enabled buffer set is rebuilt before each run.
- For every enabled slot, `CreateTextures()` releases prior temporary textures and requests two new temporary textures of the configured FFT size.
- Temporary textures use `ARGBFloat`, linear read/write, point filtering, and clamp wrapping while FFT is executing.
- The initialization material writes initial values into slot `[1]`.
- FFT stages alternate writes between slot `[0]` and slot `[1]`; the final returned index is retained as the read texture.
- During sampling, the read texture changes to bilinear/repeat; after sampling it returns to point/clamp.

### FFT math / dispatch

- `FourierGPU` rejects non-power-of-two sizes.
- Number of stages per axis is `log2(size)`; it performs all X stages, then all Y stages: total `2 * log2(size)` fullscreen passes per transform.
- A butterfly lookup texture is generated for each stage. Each texel stores two source coordinates (normalized by `size - 1`) and a complex twiddle factor `(cos θ, sin θ)`; the first stage uses bit-reversed source indices.
- The shader combines packed complex pairs in a `float4`.
- The shader has distinct X/Y variants for 1, 2, 3, and 4 render targets. The C# dispatcher rejects hardware with fewer render targets than the active output count.
- GPU FFT input is read from the opposite ping-pong slot from the output slot on each stage.

### Buffer counts in WaveSpectrum

| Output | GPU logical buffers | Initialization shader |
|---|---:|---|
| Displacement (GPU mode) | 3 | `InitDisplacement.shader` |
| Slope | 2 | `InitSlope.shader` |
| Jacobian / foam | 3 | `InitJacobians.shader` |

The displacement output copy stage repacks height and horizontal displacement into the final per-grid maps. Slope and Jacobian outputs are copied into their own maps.

## 5. CPU displacement path and parity

- `DisplacementBufferCPU` owns two sets of four interpolated displacement arrays and swaps read/write sets each run.
- It clears the write arrays, creates or resets `InitSpectrumDisplacementsTask`, and delegates to `WaveSpectrumBufferCPU`.
- `InitSpectrumDisplacementsTask` copies the condition's spectrum/WTable arrays when `LastUpdated` changes, then generates time-dependent initial complex displacement data and per-grid wave-number tables.
- `FourierTask` calls `FourierCPU`, repacks FFT output into texture colors and the three-channel interpolated displacement arrays.
- CPU displacement arrays are the direct source for `QueryDisplacements.QueryWaves`.

## 6. Wave-query limitation

- `WaveSpectrum.QueryWaves()` returns immediately when GPU displacement is active and `disableReadBack` is true.
- GPU readback is gated by the read shader, compute-buffer availability, shader model 5.0, and compute-shader support.
- The fourth grid readback in `WaveSpectrum.ReadFromGPU` is explicitly commented out in the source.
- Therefore visual GPU displacement and gameplay wave-query parity are not automatically equivalent. The Godot design must explicitly define whether queries use CPU FFT, GPU readback, or another verified sampling path.

## 7. Source files and immutable blob IDs

| Source file | Blob SHA |
|---|---|
| `Scripts/Spectrum/WaveSpectrum.cs` | `42e7ceb61c1771f298a99578b0b58eff92d6b6e6` |
| `Scripts/Spectrum/Conditions/WaveSpectrumCondition.cs` | `82eabff2e1cc5ffa4a236f60eca1e8ff51c7ece9` |
| `Scripts/Spectrum/Conditions/UnifiedSpectrumCondition.cs` | `8f5e56da6b172b879eb4f0b3df1c3204ff316af3` |
| `Scripts/Spectrum/Tasks/SpectrumTask.cs` | `48512fef8b70ac20bacc52bb9d5965269f5b7efe` |
| `Scripts/Spectrum/Tasks/InitSpectrumDisplacementsTask.cs` | `abb15f06d5841b996d30a3da7a9d874f37e0978b` |
| `Scripts/Spectrum/Buffers/WaveSpectrumBufferGPU.cs` | `ab037c7bed1ced3e0eae8b7779cb8ffdedd4b21c` |
| `Scripts/Spectrum/Fourier/FourierGPU.cs` | `c89c373b39c379c8aa72c0e6b996e3ea6db9fad6` |
| `Scripts/Spectrum/Buffers/DisplacementBufferCPU.cs` | `e0034323bc5f6c4403860f4f9e2d401ea34c3c9e` |
| `Scripts/Spectrum/Buffers/DisplacementBufferGPU.cs` | `64c700bf6c22bad50d62ee511d60103bc9296aaa` |
| `Scripts/Spectrum/Buffers/QueryDisplacements.cs` | `624c32d70a169110330bce51769f99ca3cef340b` |
| `Scripts/Spectrum/Tasks/FourierTask.cs` | `0b58cc4a24eba2879bcf2c9fbf2679ca342593b7` |
| `Scripts/Spectrum/Buffers/WaveSpectrumBufferCPU.cs` | `6464cd13f5ff381af809a6802cfdf7688a8aa1ee` |
| `Scripts/Spectrum/Fourier/FourierCPU.cs` | `6f19cb9a0032de17de8174d9dc39e4a6ae74f738` |
| `Shaders/InitDisplacement.shader` | `272019a930d59f32046326178c2e958940f360b7` |
| `Shaders/InitSlope.shader` | `92c5a3b533c0bdf05d1daf6fa66799dac23975cd` |
| `Shaders/InitJacobians.shader` | `1953e2ce81e2dc03a445f645c1f0cbf8919cf15f` |
| `Shaders/Fourier.shader` | `63465f5802019781dd7fdd5caac1604733d6c4d7` |
| `Shaders/DisplacementCopy.shader` | `e5c6f353692b7f24c0a56aeebd59d1714de5c91c` |
| `Scripts/Common/Unity/RTUtility.cs` | `e03ba81f8620dd329e1311335966661abd28c77a` |

## 8. Godot rebuild decisions still open

1. Select the GPU execution primitive for the target Godot renderer: compute shader, RenderingDevice compute, or raster multi-pass. Do not assume Unity MRT behavior maps one-to-one.
2. Decide storage formats and verify floating-point texture support on target Android GPU hardware.
3. Preserve FFT sign convention, butterfly indexing, axis order, normalization behavior, texture coordinate convention, and packed channel layout.
4. Decide how the four-grid displacement maps and three-channel query arrays remain synchronized.
5. Define a CPU fallback and a query path when compute/readback is unavailable.
6. Reconcile Unity's temporary texture lifetime and sampler-state transitions with explicit Godot resource ownership.

## 9. Status / next task

- [x] Source tree and source blobs confirmed on `main`.
- [x] Condition-generation lifecycle inspected.
- [x] CPU and GPU displacement paths separated correctly.
- [x] GPU buffer allocation, ping-pong, FFT stages, and MRT limits inspected.
- [x] Query/readback constraints recorded.
- [ ] Full numerical equivalence tests for CPU/GPU FFT.
- [ ] Godot renderer capability matrix on target Android device.
- [ ] Godot-side architecture and resource contract.
- [ ] First implementation and runtime verification.

**Next task:** audit the spectrum equations and exact CPU/GPU numerical equivalence: compare `InitSpectrumDisplacementsTask` against `InitDisplacement.shader`, `FourierCPU` against `FourierGPU + Fourier.shader`, and record normalization, channel packing, and coordinate conventions before implementation.
