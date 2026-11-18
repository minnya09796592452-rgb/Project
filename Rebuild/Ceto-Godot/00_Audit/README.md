# Ceto → Godot Rebuild — Read-only Source Audit

**Stage:** 00 — source reconnaissance  
**Source branch:** `main`  
**Rebuild branch:** `ceto-rebuild`  
**Source version:** Ceto 1.1.4  
**Unity project version:** 2020.1.6f1

## Safety boundary

- The original `Extracted/Ceto-master/` tree is reference-only.
- No source files in the original tree are edited, moved, or deleted.
- Rebuild work belongs under `Rebuild/Ceto-Godot/`, in separate folders created one stage at a time.
- This document records source evidence; it does not claim a working Godot port.

## Verified source layout

Reference root:

`Extracted/Ceto-master/Ceto-master/Assets/Ceto/`

Relevant source files confirmed in the Git tree:

- `Scripts/Ocean/Ocean.cs`
- `Scripts/Spectrum/WaveSpectrum.cs`
- `Scripts/Spectrum/Buffers/WaveSpectrumBufferGPU.cs`
- `Scripts/Spectrum/Buffers/DisplacementBufferGPU.cs`
- `Scripts/Spectrum/Fourier/FourierGPU.cs`
- `Scripts/Spectrum/Tasks/InitSpectrumDisplacementsTask.cs`
- `Scripts/Spectrum/Tasks/FourierTask.cs`
- `Shaders/Fourier.shader`

The Ceto source tree also contains separate Grids, Ocean Querys, Overlays, Reflections, UnderWater, Common, Utility, and shader/include subsystems. The source inventory contains 104 C# files, 20 shader files, 8 CG includes, and 1 compute shader.

## Confirmed execution responsibilities

### 1. Ocean coordinator

`Scripts/Ocean/Ocean.cs` declares `Ocean : MonoBehaviour` and documents its role as managing child components, storing per-camera data, and handling shared ocean behavior. It exposes shared ocean state and texture-name constants. This is Unity lifecycle/render-pipeline coupling, not a portable Godot controller.

### 2. Spectrum generation

`Scripts/Spectrum/WaveSpectrum.cs` documents the sequence:

1. Build a frequency spectrum from wind speed, wind direction, and wave age.
2. Transform frequency-domain data into spatial-domain data using FFT.
3. Produce displacement, slope, and foam textures.
4. Support CPU or GPU displacement transforms; slope and Jacobian/foam processing are GPU-oriented in the original implementation.

The source exposes settings such as Fourier size, spectrum type, grid count, choppiness, wind speed, wave age, and wave speed.

### 3. GPU buffer and FFT

`Scripts/Spectrum/Buffers/WaveSpectrumBufferGPU.cs` owns GPU buffers and constructs a `FourierGPU`. Its buffer model uses pairs of RenderTextures for read/write ping-pong during FFT stages. It supports one through four data buffers.

`Scripts/Spectrum/Fourier/FourierGPU.cs` is the GPU transform implementation. Its paired shader is `Shaders/Fourier.shader`.

`Shaders/Fourier.shader` uses a butterfly lookup texture and separate X/Y fragment stages. The shader has output variants for one, two, three, or four render targets and packs complex values into `float4`.

### 4. Displacement query path

`Scripts/Spectrum/Buffers/DisplacementBufferGPU.cs` extends the GPU spectrum buffer and implements `IDisplacementBuffer`. It keeps interpolated displacement arrays and delegates wave sampling to `QueryDisplacements.QueryWaves`. This means rendered displacement data and CPU-side wave queries are coupled and must be audited together.

## Initial dependency spine

```text
Ocean
  └─ WaveSpectrum
       ├─ spectrum conditions / spectrum tasks
       ├─ InitSpectrumDisplacementsTask
       ├─ WaveSpectrumBufferGPU
       │    └─ FourierGPU
       │         └─ Fourier.shader
       └─ DisplacementBufferGPU
            └─ QueryDisplacements / WaveQuery
```

This is an initial, source-supported spine, not the complete dependency graph. Exact call sites, lifecycle ordering, resource formats, and every referenced type still require line-by-line audit.

## Porting constraints identified

- Unity `MonoBehaviour`, `RenderTexture`, `Shader`, `Material`, `Graphics.Blit`, render callbacks, and Unity shader includes cannot be treated as Godot APIs.
- The FFT math and spectrum equations are candidates for a behavior-preserving port.
- Texture allocation, ping-pong scheduling, multi-target outputs, shader bindings, readback, and render ordering need a Godot-specific design.
- CPU wave-query parity must be retained if gameplay systems depend on buoyancy or height queries.

## Evidence links

- [Ocean.cs](../../Extracted/Ceto-master/Ceto-master/Assets/Ceto/Scripts/Ocean/Ocean.cs)
- [WaveSpectrum.cs](../../Extracted/Ceto-master/Ceto-master/Assets/Ceto/Scripts/Spectrum/WaveSpectrum.cs)
- [WaveSpectrumBufferGPU.cs](../../Extracted/Ceto-master/Ceto-master/Assets/Ceto/Scripts/Spectrum/Buffers/WaveSpectrumBufferGPU.cs)
- [FourierGPU.cs](../../Extracted/Ceto-master/Ceto-master/Assets/Ceto/Scripts/Spectrum/Fourier/FourierGPU.cs)
- [Fourier.shader](../../Extracted/Ceto-master/Ceto-master/Assets/Ceto/Shaders/Fourier.shader)

## Status

- [x] Repository and source tree inspected without modifying source files.
- [x] Core spectrum/FFT source paths located.
- [x] First-pass responsibility map recorded.
- [ ] Full dependency graph and call-site audit.
- [ ] Godot rendering backend design.
- [ ] First behavior-preserving Godot implementation.
- [ ] Godot editor/import/runtime verification.

**Next task:** audit the complete `WaveSpectrum → InitSpectrumDisplacementsTask → WaveSpectrumBufferGPU → FourierGPU` call chain, including resource formats, update order, and CPU/GPU parity, before writing implementation code.
