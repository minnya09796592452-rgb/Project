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
- `shaders/ceto_fourier_stage.gdshader`: Godot single-render-target Fourier stage.
- `shaders/ceto_init_displacement.gdshader`: Ceto spectrum-to-height/horizontal-displacement initialization, split into selectable single-target passes to replace Unity MRT.
- `shaders/ceto_init_slope.gdshader`: Ceto slope initialization, split into selectable single-target passes.
- `shaders/ceto_init_jacobians.gdshader`: Ceto Jacobian/foam precursor initialization, split into selectable single-target passes.
- `tests/test_ceto_fourier.gd`: headless tests for FFT, lookup textures, spectrum equations, and WTable.

## Verification

The `Ceto Godot Conversion Tests` workflow downloads the official Godot 4.7.2 binary, imports the project headlessly, runs the GDScript numerical tests (including loading the translated shader resources), launches the preview scene headlessly, copies the remaining original Caustics texture, and converts the original Ship.3DS to GLB. It removes the generated editor cache after the run.

## Not yet a complete ocean port

The current project is a verified numerical and asset-conversion foundation, not a complete feature-parity Ceto ocean. The following remain:

1. Port spectrum condition creation, deterministic .NET `System.Random(0)` sequence, and the complete packed spectrum-generation task.
2. Port time-dependent displacement initialization and CPU query interpolation.
3. Implement the Godot GPU ping-pong/MRT equivalent and connect the Fourier stage shader to it.
4. Connect the translated displacement, slope, and Jacobian shaders to a Godot render-target scheduler; implement downstream foam composition and texture packing.
5. Port ocean mesh, material, camera integration, reflections, underwater effects, and query APIs.
6. Port GPU buffer ping-pong, slope/Jacobian/foam generation, and the original Unity material effects.
7. Verify numerical and visual parity against the original Ceto implementation in Godot.

No Unity source files are edited. The converted project is isolated under `Rebuild/Ceto-Godot/04_Godot_Project/`.
