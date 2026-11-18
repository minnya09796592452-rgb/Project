#!/usr/bin/env python3
"""One-click, source-preserving Ceto -> Godot conversion pipeline.

Run from anywhere inside the repository:
    python3 Rebuild/Ceto-Godot/04_Godot_Project/Tools/ceto_oneclick_pipeline.py

The original Unity Ceto source is read-only. All generated files and reports stay
inside Rebuild/Ceto-Godot/04_Godot_Project/.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

PROJECT_REL = Path("Rebuild/Ceto-Godot/04_Godot_Project")
SOURCE_REL = Path("Extracted/Ceto-master/Ceto-master/Assets/Ceto")
TEXTURE_MAP = {
    "Textures": "assets/textures",
    "DemoScene": "assets/demo",
}
SHADER_EXT = {".shader", ".cginc", ".compute", ".hlsl", ".glsl"}
SCENE_EXT = {".unity", ".prefab", ".mat", ".asset"}
ASSET_EXT = {".png", ".jpg", ".jpeg", ".tga", ".psd", ".3ds", ".fbx", ".obj", ".dae", ".blend"}
CSHARP_EXT = {".cs"}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def locate_repo() -> Path:
    here = Path.cwd().resolve()
    for candidate in (here, *here.parents):
        if (candidate / SOURCE_REL).is_dir() and (candidate / PROJECT_REL).is_dir():
            return candidate
    script = Path(__file__).resolve()
    for candidate in (script, *script.parents):
        if (candidate / SOURCE_REL).is_dir() and (candidate / PROJECT_REL).is_dir():
            return candidate
    raise SystemExit(
        "Repository root not found. Run this script inside the Project repository "
        "containing Extracted/Ceto-master and Rebuild/Ceto-Godot."
    )


def run_command(command: list[str], cwd: Path, log_path: Path) -> tuple[int, str]:
    started = time.time()
    result = subprocess.run(
        command, cwd=cwd, text=True, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, errors="replace"
    )
    output = result.stdout or ""
    log_path.parent.mkdir(parents=True, exist_ok=True)
    log_path.write_text(
        "$ " + " ".join(command) + "\n\n" + output +
        f"\n[exit={result.returncode}; elapsed={time.time() - started:.2f}s]\n",
        encoding="utf-8"
    )
    return result.returncode, output


def main() -> int:
    parser = argparse.ArgumentParser(description="Run the Ceto -> Godot one-click pipeline.")
    parser.add_argument("--no-assets", action="store_true", help="Do not copy/convert source assets.")
    parser.add_argument("--no-godot", action="store_true", help="Do not run Godot import/tests/smoke test.")
    args = parser.parse_args()

    repo = locate_repo()
    source = repo / SOURCE_REL
    project = repo / PROJECT_REL
    reports = project / "reports" / "oneclick"
    logs = reports / "logs"
    reports.mkdir(parents=True, exist_ok=True)
    logs.mkdir(parents=True, exist_ok=True)

    if not (project / "project.godot").is_file():
        raise SystemExit(f"Godot project.godot missing: {project}")

    files = sorted(p for p in source.rglob("*") if p.is_file() and not p.name.endswith(".meta"))
    inventory: dict[str, list[str]] = {"csharp": [], "shaders": [], "unity_scenes": [], "assets": [], "other": []}
    for item in files:
        relative = item.relative_to(source).as_posix()
        ext = item.suffix.lower()
        if ext in CSHARP_EXT:
            inventory["csharp"].append(relative)
        elif ext in SHADER_EXT:
            inventory["shaders"].append(relative)
        elif ext in SCENE_EXT:
            inventory["unity_scenes"].append(relative)
        elif ext in ASSET_EXT:
            inventory["assets"].append(relative)
        else:
            inventory["other"].append(relative)

    tools = {
        "python": sys.version.split()[0],
        "assimp": shutil.which("assimp"),
        "godot": shutil.which("godot") or shutil.which("godot4"),
        "dotnet": shutil.which("dotnet"),
        "unity_editor": shutil.which("Unity") or shutil.which("unity"),
    }
    # Existing ports are tracked per original source file. A present output is not
    # treated as feature parity; runtime/numerical parity remains a separate gate.
    shader_ports = {
        "Shaders/Fourier.shader": ["shaders/ceto_fourier_stage.gdshader"],
        "Shaders/InitDisplacement.shader": ["shaders/ceto_init_displacement.gdshader"],
        "Shaders/InitSlope.shader": ["shaders/ceto_init_slope.gdshader"],
        "Shaders/InitJacobians.shader": ["shaders/ceto_init_jacobians.gdshader"],
        "Shaders/FoamCopy.shader": ["shaders/ceto_foam_copy.gdshader"],
        "Shaders/DisplacementCopy.shader": ["shaders/ceto_displacement_copy.gdshader"],
        "Shaders/SlopeCopy.shader": ["shaders/ceto_slope_copy.gdshader"],
    }
    csharp_ports = {
        "Scripts/Spectrum/Fourier/FourierCPU.cs": ["scripts/ceto_fourier.gd"],
        "Scripts/Spectrum/Conditions/UnifiedSpectrum.cs": ["scripts/ceto_spectrum.gd"],
        "Scripts/Spectrum/Conditions/PhillipsSpectrum.cs": ["scripts/ceto_spectrum.gd"],
        "Scripts/Spectrum/Conditions/WaveSpectrumCondition.cs": ["scripts/ceto_spectrum_generator.gd"],
        "Scripts/Spectrum/Tasks/InitSpectrumDisplacementsTask.cs": ["scripts/ceto_displacement.gd"],
        "Scripts/Spectrum/Tasks/FourierTask.cs": ["scripts/ceto_fourier.gd", "scripts/ceto_displacement.gd"],
        "Scripts/Spectrum/Buffers/QueryDisplacements.cs": ["scripts/ceto_wave_query.gd", "scripts/ceto_interpolated_array_2d.gd"],
    }
    def present_ports(mapping: dict[str, list[str]], domain: str) -> dict[str, list[str]]:
        found = {}
        for source_file, outputs in mapping.items():
            if source_file in inventory[domain] and all((project / output).is_file() for output in outputs):
                found[source_file] = outputs
        return found

    present_shader_ports = present_ports(shader_ports, "shaders")
    present_csharp_ports = present_ports(csharp_ports, "csharp")
    routing = [
        ("C# logic", len(inventory["csharp"]), "C# dependency review + Godot GDScript behavior ports",
         f"{len(present_csharp_ports)} PARTIAL_PORT_OUTPUTS_PRESENT",
         "Mapped files are behavior ports, not a complete line-by-line C# conversion or parity claim."),
        ("ShaderLab/HLSL", len(inventory["shaders"]), "Ceto-specific Godot shader translation",
         f"{len(present_shader_ports)} PORT_OUTPUTS_PRESENT",
         "Mapped shader outputs are separate Godot single-target passes; the remaining source shaders stay queued."),
        ("Unity scenes/materials", len(inventory["unity_scenes"]), "Audited Unity scene/prefab converter",
         "SCENE_CONVERSION_QUEUE",
         "Requires an audited Unity YAML converter; custom ocean materials must not be silently approximated."),
        ("Textures/models", len(inventory["assets"]), "Byte-hash verification + Assimp",
         "ASSET_PIPELINE",
         "Copy raster textures byte-for-byte; convert supported 3D formats with Assimp."),
    ]

    results: list[dict[str, object]] = []

    def record(stage: str, status: str, detail: str, **extra: object) -> None:
        row: dict[str, object] = {"stage": stage, "status": status, "detail": detail}
        row.update(extra)
        results.append(row)
        print(f"[{status}] {stage}: {detail}")

    # Source inventory and per-domain routing manifest.
    (reports / "source_inventory.json").write_text(
        json.dumps({
            "source_root": SOURCE_REL.as_posix(),
            "source_is_read_only": True,
            "file_counts": {key: len(value) for key, value in inventory.items()},
            "files": inventory,
            "detected_tools": tools,
        }, indent=2), encoding="utf-8"
    )
    with (reports / "tool_routing.csv").open("w", newline="", encoding="utf-8") as stream:
        writer = csv.writer(stream)
        writer.writerow(["domain", "source_file_count", "selected_tool_class", "status", "routing_reason"])
        writer.writerows(routing)
    record("inventory", "PASS", f"{len(files)} source files classified; original source remains read-only.")

    # Asset lane: preserve texture bytes and use Assimp for the 3DS model.
    if not args.no_assets:
        copied = 0
        copy_errors = []
        for source_dir, destination_dir in TEXTURE_MAP.items():
            folder = source / source_dir
            if not folder.is_dir():
                continue
            for item in sorted(folder.iterdir()):
                if not item.is_file() or item.suffix.lower() not in {".png", ".jpg", ".jpeg", ".tga"}:
                    continue
                target = project / destination_dir / item.name
                target.parent.mkdir(parents=True, exist_ok=True)
                try:
                    if not target.is_file() or sha256(item) != sha256(target):
                        shutil.copy2(item, target)
                    if sha256(item) != sha256(target):
                        raise RuntimeError("SHA-256 mismatch after copy")
                    copied += 1
                except Exception as exc:
                    copy_errors.append(f"{item}: {exc}")
        if copy_errors:
            record("texture_sync", "FAIL", "; ".join(copy_errors))
        else:
            record("texture_sync", "PASS", f"{copied} raster textures copied/verified byte-for-byte.")

        ship = source / "Mesh" / "Ship.3DS"
        assimp = tools["assimp"]
        if ship.is_file() and assimp:
            intermediate = reports / "CetoShip.obj"
            target = project / "assets" / "models" / "Ship.glb"
            target.parent.mkdir(parents=True, exist_ok=True)
            code1, out1 = run_command([str(assimp), "export", str(ship), str(intermediate), "-f", "objnomtl"], repo, logs / "assimp_obj.log")
            if code1 == 0 and intermediate.is_file():
                code2, out2 = run_command([str(assimp), "export", str(intermediate), str(target), "-f", "glb2"], repo, logs / "assimp_glb.log")
                if code2 == 0 and target.is_file() and target.stat().st_size > 20:
                    info_code, info_out = run_command([str(assimp), "info", str(target)], repo, logs / "assimp_verify.log")
                    if info_code == 0:
                        record("ship_model", "PASS", f"Assimp converted Ship.3DS to {target.relative_to(project)}.")
                    else:
                        record("ship_model", "FAIL", "Assimp generated GLB but could not inspect it.")
                else:
                    record("ship_model", "FAIL", "Assimp GLB export failed.", output=out2[-1200:])
            else:
                record("ship_model", "FAIL", "Assimp OBJ intermediate export failed.", output=out1[-1200:])
        elif ship.is_file():
            record("ship_model", "SKIP", "Ship.3DS found; Assimp is not installed or not on PATH.")
        else:
            record("ship_model", "SKIP", "No source Mesh/Ship.3DS found.")

    # Build a truthful per-file conversion manifest and queue only unmapped files.
    queue_dir = reports / "queues"
    queue_dir.mkdir(parents=True, exist_ok=True)
    conversion_manifest = []
    queue_specs = [
        ("csharp", "csharp_semantic_port.json", csharp_ports, present_csharp_ports,
         "PARTIAL_BEHAVIOR_PORT_REQUIRES_PARITY"),
        ("shaders", "shader_translation.json", shader_ports, present_shader_ports,
         "GODOT_SHADER_OUTPUT_PRESENT_REQUIRES_PARITY"),
        ("unity_scenes", "unity_scene_conversion.json", {}, {},
         "NOT_CONVERTED"),
    ]
    for key, filename, mapping, present, output_status in queue_specs:
        pending = []
        for source_file in inventory[key]:
            outputs = mapping.get(source_file, [])
            if outputs and source_file in present:
                conversion_manifest.append({
                    "domain": key, "source": source_file, "outputs": outputs,
                    "status": output_status,
                })
            else:
                pending.append(source_file)
                conversion_manifest.append({
                    "domain": key, "source": source_file, "outputs": [],
                    "status": "QUEUED_NOT_CONVERTED",
                })
        (queue_dir / filename).write_text(
            json.dumps({
                "domain": key,
                "status": "PENDING" if pending else "NO_PENDING_FILES",
                "source_root": SOURCE_REL.as_posix(),
                "pending_files": pending,
                "mapped_output_count": len(present),
                "existing_godot_project": PROJECT_REL.as_posix(),
                "policy": "Original Unity source is read-only. Output presence is not proof of feature parity.",
            }, indent=2), encoding="utf-8"
        )
    (reports / "conversion_manifest.json").write_text(
        json.dumps(conversion_manifest, indent=2), encoding="utf-8"
    )
    record("conversion_queues", "INFO",
           f"C# mapped={len(present_csharp_ports)}/{len(inventory['csharp'])}; "
           f"shaders mapped={len(present_shader_ports)}/{len(inventory['shaders'])}; "
           f"Unity scenes/materials pending={len(inventory['unity_scenes'])}.")

    # Godot lane: import, numerical tests, then preview smoke test.
    if not args.no_godot:
        godot = tools["godot"]
        if not godot:
            record("godot_validation", "SKIP", "Godot executable not found on PATH; run again where Godot 4.7.2+ is available.")
        else:
            version_code, version_out = run_command([str(godot), "--version"], repo, logs / "godot_version.log")
            if version_code != 0:
                record("godot_validation", "FAIL", "Could not query Godot version.")
            else:
                import_code, import_out = run_command(
                    [str(godot), "--headless", "--editor", "--path", str(project), "--quit"],
                    repo, logs / "godot_import.log"
                )
                if import_code != 0 or any(token in import_out for token in ("SCRIPT ERROR", "Parse Error", "Compile Error")):
                    record("godot_import", "FAIL", f"Project import failed under {version_out.strip()}.")
                else:
                    record("godot_import", "PASS", f"Project imported under {version_out.strip()}.")
                    test_script = project / "tests" / "test_ceto_fourier.gd"
                    if test_script.is_file():
                        test_code, test_out = run_command(
                            [str(godot), "--headless", "--path", str(project),
                             "--script", "res://tests/test_ceto_fourier.gd"],
                            repo, logs / "godot_numerics.log"
                        )
                        if test_code == 0 and "CETO GODOT NUMERICS: 13/13 PASS" in test_out and not any(
                            token in test_out for token in ("SCRIPT ERROR", "Parse Error", "Compile Error", "ERROR:")
                        ):
                            record("godot_numerics", "PASS", "13/13 numerical test groups passed.")
                        else:
                            record("godot_numerics", "FAIL", "Numerical test suite did not meet strict 13/13 PASS gate.")
                    preview_code, preview_out = run_command(
                        [str(godot), "--headless", "--path", str(project), "--quit-after", "2"],
                        repo, logs / "godot_preview.log"
                    )
                    if preview_code == 0 and not any(
                        token in preview_out for token in ("SCRIPT ERROR", "Parse Error", "Compile Error", "ERROR:")
                    ):
                        record("godot_preview", "PASS", "Headless ocean preview smoke test passed.")
                    else:
                        record("godot_preview", "FAIL", "Headless ocean preview smoke test reported errors.")

    summary = {
        "project": PROJECT_REL.as_posix(),
        "source": SOURCE_REL.as_posix(),
        "source_modified": False,
        "detected_tools": tools,
        "source_counts": {key: len(value) for key, value in inventory.items()},
        "results": results,
        "complete_ceto_feature_parity": False,
        "note": "A PASS applies only to the named stage. Present C# and shader outputs are partial ports and still require full feature-parity validation; unmapped files remain queued.",
    }
    (reports / "run_summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    with (reports / "run_summary.txt").open("w", encoding="utf-8") as stream:
        stream.write("CETO -> GODOT ONECLICK PIPELINE\n")
        stream.write("=" * 36 + "\n")
        for result in results:
            stream.write(f"[{result['status']}] {result['stage']}: {result['detail']}\n")
        stream.write("\nFull reports: reports/oneclick/\n")
        stream.write("Original Unity source modified: NO\n")
        stream.write("Complete Ceto feature parity: NOT CLAIMED\n")

    failures = [item for item in results if item["status"] == "FAIL"]
    print(f"\nREPORT: {reports.relative_to(repo)}")
    print(f"RESULT: {len(results) - len(failures)} non-failing stages; {len(failures)} failed stages.")
    print("Mapped C# and shader outputs are partial ports requiring parity checks; unmapped files remain queued.")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
