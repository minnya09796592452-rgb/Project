# Ceto → Godot conversion project

This folder is a Godot 4.7.2 project assembled from the existing starter project and converted Ceto source behavior. The original Ceto tree under `Extracted/Ceto-master/` remains unchanged and is the source of truth.

## Current contents

- `project.godot`, `node_3d.tscn`, and `icon.svg`: copied from the existing Godot starter project.
- `assets/demo/`: original Ceto demo mask and edge-foam PNGs.
- `assets/textures/`: original Ceto textures, including the Caustics map copied by CI.
- `assets/source_models/Ship.3DS`: unchanged original 3DS source model.
- `assets/models/Ship.glb`: converted from the original 3DS by Assimp in CI. The source model referenced two external texture files that are absent from the archive, so those broken texture links are stripped while retaining mesh geometry and material properties.
- `scripts/ceto_fourier.gd`: CPU radix-2 2D FFT port following Ceto's butterfly table, bit reversal, X-then-Y stages, and unnormalized convention. Also creates RGBAF lookup textures.
- `scripts/ceto_spectrum.gd`: Ceto Unified and Phillips spectrum equations plus the dispersion WTable.
- `scripts/ceto_gpu_pass_runner.gd`: sequential Godot SubViewport render-pass scheduler for Fourier and other single-target Ceto shader passes; every output texture is retained to avoid read/write feedback.
- `scripts/ceto_gpu_ocean_pipeline.gd`: GPU spectrum-to-displacement, slope, and Jacobian initialization plus displacement/slope/foam copy passes.
- `shaders/ceto_fourier_stage.gdshader`: Godot single-render-target Fourier stage.
- `shaders/ceto_init_displacement.gdshader`: Ceto spectrum-to-height/horizontal-displacement initialization, split into selectable single-target passes to replace Unity MRT.
- `shaders/ceto_init_slope.gdshader`: Ceto slope initialization, split into selectable single-target passes.
- `shaders/ceto_init_jacobians.gdshader`: Ceto Jacobian/foam precursor initialization, split into selectable single-target passes.
- `shaders/ceto_foam_copy.gdshader`: Ceto foam Jacobian composition for one through four grids.
- `shaders/ceto_displacement_copy.gdshader`: Ceto packed height/horizontal displacement texture assembly.
- `shaders/ceto_slope_copy.gdshader`: Ceto slope buffer copy.
- `tests/test_ceto_fourier.gd`: headless CPU tests for FFT, lookup textures, spectrum equations, WTable, displacement initialization, and wave queries.
- `tests/test_ceto_gpu_fourier.gd`: GPU render-pass comparison against the CPU FFT reference, including pass-count and numeric-error gates.
- `tests/test_ceto_gpu_displacement.gd`: GPU InitDisplacement, InitSlope, and InitJacobians outputs compared against independent CPU references for four grids.
- `tests/test_ceto_gpu_copy.gd`: displacement packing, slope copy, and foam composition compared against CPU reference calculations.

## Verification

The `Ceto Godot Conversion Tests` workflow downloads the official Godot 4.7.2 binary, imports the project headlessly, runs the CPU numerical suite, runs CPU numerical tests on every CI run. GPU parity scripts execute only when a RenderingDevice is available; the CI Compatibility renderer reports an explicit SKIP because it cannot provide the HDR float targets required for reliable numeric parity. The project GPU path requires a Forward+ or Mobile renderer for full precision. CI also launches the CPU preview scene headlessly, copies the remaining original Caustics texture, and converts the original Ship.3DS to GLB. It removes the generated editor cache after the run.

## GPU validation boundary

The sequential GPU pass runner and initialization/copy pipeline are implemented, but they are not yet connected to the live preview update loop. The CI host's OpenGL Compatibility renderer cannot provide HDR 2D float targets; GPU numeric tests therefore report SKIP there rather than a false PASS. Run those parity checks on a Godot Forward+ or Mobile RenderingDevice backend before treating GPU parity as verified.

## Not yet a complete ocean port

The current project is a verified numerical and asset-conversion foundation, not a complete feature-parity Ceto ocean. The following remain:

1. Port spectrum condition creation, deterministic .NET `System.Random(0)` sequence, and the complete packed spectrum-generation task.
2. Port time-dependent displacement initialization and CPU query interpolation.
3. Extend the Fourier pass runner to the complete multi-buffer lifecycle and connect it to spectrum/displacement buffer ownership.
4. Integrate the verified slope, Jacobian, displacement-copy, slope-copy, and foam-copy passes into the live ocean update loop; finish remaining texture packing and render pipeline.
5. Port ocean mesh, material, camera integration, reflections, underwater effects, and query APIs.
6. Convert remaining Unity C# behavior, shader includes, compute paths, scenes, prefabs, and materials without silently approximating custom ocean effects.
7. Verify numerical and visual parity against the original Ceto implementation in Godot.

No Unity source files are edited. The converted project is isolated under `Rebuild/Ceto-Godot/04_Godot_Project/`.
