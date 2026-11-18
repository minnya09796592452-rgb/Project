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
- `scripts/ceto_gpu_ocean_pipeline.gd`: GPU spectrum-to-displacement, slope, and Jacobian initialization, multi-buffer FFT scheduling, displacement assembly, and foam composition.
- `scripts/ceto_gpu_ocean_preview.gd` + `ceto_gpu_ocean_preview.tscn`: optional GPU-driven preview controller and scene; requires a Forward+ or Mobile RenderingDevice backend.
- `shaders/ceto_fourier_stage.gdshader`: Godot single-render-target Fourier stage.
- `shaders/ceto_init_displacement.gdshader`: Ceto spectrum-to-height/horizontal-displacement initialization, split into selectable single-target passes to replace Unity MRT.
- `shaders/ceto_init_slope.gdshader`: Ceto slope initialization, split into selectable single-target passes.
- `shaders/ceto_init_jacobians.gdshader`: Ceto Jacobian/foam precursor initialization, split into selectable single-target passes.
- `shaders/ceto_foam_copy.gdshader`: Ceto foam Jacobian composition for one through four grids.
- `shaders/ceto_displacement_copy.gdshader`: Ceto packed height/horizontal displacement texture assembly.
- `shaders/ceto_slope_copy.gdshader`: Ceto slope buffer copy.
- `shaders/ceto_ocean_surface.gdshader`: Godot preview surface material that consumes the generated per-grid displacement, slope, and foam textures; it is a presentation approximation, not a full port of Ceto's original ocean material.
- `shaders/ceto_copy_depth.gdshader`, `ceto_normal_fade.gdshader`, and `ceto_blur_cone_taps.gdshader`: additional Ceto depth-copy, world-normal fade, and four-tap blur translations.
- `shaders/ceto_wave_overlay.gdshader` and `ceto_ocean_mask_decode.gdshader`: wave overlay channel packing and ocean mask decoding. Overlay max-compositing still requires host-side blend configuration.
- `shaders/ceto_ocean_mask.gdshader`, `ceto_ocean_depth.gdshader`, and `ceto_underwater_post.gdshader`: projected-grid mask output, generic ocean depth replacement, and a Godot underwater post-process approximation.
- `tests/test_ceto_fourier.gd`: headless CPU tests for FFT, lookup textures, spectrum equations, WTable, displacement initialization, and wave queries.
- `tests/test_ceto_gpu_fourier.gd`: GPU render-pass comparison against the CPU FFT reference, including pass-count and numeric-error gates.
- `tests/test_ceto_gpu_displacement.gd`: GPU InitDisplacement, InitSlope, and InitJacobians outputs compared against independent CPU references for four grids.
- `tests/test_ceto_gpu_copy.gd`: displacement packing, slope copy, and foam composition compared against CPU reference calculations.
- `tests/test_ceto_gpu_pipeline.gd`: full four-grid update orchestration; checks 61 scheduled passes and all returned GPU texture dimensions.

## Verification

The `Ceto Godot Conversion Tests` workflow downloads the official Godot 4.7.2 binary, imports the project headlessly, runs the CPU numerical suite, and launches the CPU preview smoke test. It also runs GPU Fourier, displacement/slope/Jacobian initialization, copy/foam parity checks, and the integrated 61-pass ocean update on the Godot Mobile renderer using the runner's Vulkan llvmpipe device. The optional GPU preview requires a Forward+ or Mobile renderer. CI copies the remaining original Caustics texture and converts the original Ship.3DS to GLB, then removes the generated editor cache.

## GPU validation boundary

The sequential GPU pass runner, multi-buffer FFT scheduler, initialization/copy pipeline, optional GPU preview scene, and additional mask/depth/underwater shader translations are implemented. The CI host exposes a Vulkan llvmpipe RenderingDevice, so GPU numeric tests are configured to run against the CPU reference. A successful CI run validates the tested FFT and initialization/copy stages only; the full Unity visual parity is still outstanding.

## Not yet a complete ocean port

The current project is a verified numerical and asset-conversion foundation, not a complete feature-parity Ceto ocean. The following remain:

1. Connect the optional GPU preview to the full original Ceto ocean material and validate its per-grid vertex displacement, normals, and foam visually.
2. Complete the remaining GPU buffer ownership, texture packing, and update scheduling against the original Ceto lifecycle.
3. Replace the current approximate underwater post effect and preview surface with complete Ceto reflection/refraction, caustics, absorption, scattering, and scene/prefab integration.
4. Convert the remaining Unity C# behavior, shader includes, compute paths, scenes, prefabs, and materials.
5. Verify CPU and GPU numerical parity and visual parity against the original Ceto implementation in Godot.

No Unity source files are edited. The converted project is isolated under `Rebuild/Ceto-Godot/04_Godot_Project/`.
