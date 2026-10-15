#!/usr/bin/env python3
"""Build self-contained SAS submissions and matching R references (stdlib only)."""

import argparse
import hashlib
import json
import math
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
COMMON = [
    "sas/00_car_common.sas",
    "sas/04_joint_calibration.sas",
    "sas/05_variance_estimation.sas",
    "sas/06_treatment_contrasts.sas",
    "sas/07_validation.sas",
    "validation/test_inference_reference.sas",
]
RECIPES = {
    "smoke": COMMON + ["validation/test_inference_smoke.sas"],
    "outcome_models": [
        "sas/01_data_preparation.sas",
        "sas/02_outcome_models.sas",
        "validation/test_outcome_models.sas",
    ],
    # Program 03's unchanged driver runs immediately and requests ALL methods.
    "inference": [
        COMMON[0],
        "sas/01_data_preparation.sas",
        "sas/02_outcome_models.sas",
        "sas/inference_pipeline.sas",
        "sas/03_aipw_estimation.sas",
    ]
    + COMMON[1:],
}


def load_config(path):
    if not path.is_file():
        raise ValueError("Run 'python run/project.py init', then edit the local configuration.")
    cfg = json.loads(path.read_text())
    if isinstance(cfg, dict):
        cfg.setdefault("analysis_model", "ANCOVA")
    expected = {
        "input_csv", "server_input_csv", "server_outcome_reference_dir",
        "server_inference_reference_dir", "server_export_dir",
        "analysis_arms", "analysis_model", "car_scheme", "alpha",
    }
    if not isinstance(cfg, dict) or set(cfg) != expected:
        raise ValueError("Configuration keys must match utilities/config.example.json.")
    for key in ("server_input_csv", "server_outcome_reference_dir",
                "server_inference_reference_dir", "server_export_dir"):
        value = cfg[key]
        if not isinstance(value, str) or not value.startswith("/") or value != value.strip():
            raise ValueError(f"{key} must be an absolute server path without surrounding spaces.")
        if any(c in value for c in "\r\n\t;%&'\"()") or len(value) > 4096:
            raise ValueError(f"{key} contains unsupported SAS path characters or is too long.")
        if "/your/viya/" in value:
            raise ValueError(f"Replace the example path in {key} with your server path.")
    if cfg["analysis_model"] not in ("ANOVA", "ANCOVA", "ANHECOVA"):
        raise ValueError("analysis_model must be ANOVA, ANCOVA, or ANHECOVA.")
    arms = cfg["analysis_arms"]
    if (not isinstance(arms, list) or len(arms) < 2
            or any(type(a) is not int for a in arms)
            or len(set(arms)) != len(arms)):
        raise ValueError("analysis_arms must contain at least two distinct integer labels.")
    # Matrix calculations sort treatments; the R factor uses the same order.
    if arms != sorted(arms):
        raise ValueError("Use ascending analysis_arms for the current SAS inference workflow.")
    if cfg["car_scheme"] not in ("simple", "permuted-block"):
        raise ValueError("car_scheme must be simple or permuted-block.")
    alpha = cfg["alpha"]
    if (type(alpha) not in (int, float) or not math.isfinite(alpha)
            or not 0 < alpha < 1 or not 0 < 1 - alpha / 2 < 1):
        raise ValueError("alpha must produce a finite normal quantile with 0 < alpha < 1.")
    if not isinstance(cfg["input_csv"], str) or not cfg["input_csv"]:
        raise ValueError("input_csv must be a local CSV path.")
    if not (ROOT / cfg["input_csv"]).is_file():
        raise ValueError("Local input_csv does not exist; relative paths start at the repository root.")
    return cfg


def sas_config(cfg):
    values = [
        ("csv_path", cfg["server_input_csv"]),
        ("arms", " ".join(map(str, cfg["analysis_arms"]))),
        ("model", cfg.get("analysis_model", "ANCOVA")),
        ("scheme", cfg["car_scheme"]),
        ("alpha", str(cfg["alpha"])),
        ("outcome_reference_dir", cfg["server_outcome_reference_dir"]),
        ("inference_reference_dir", cfg["server_inference_reference_dir"]),
        ("export_dir", cfg["server_export_dir"]),
    ]
    return "%car_config(\n" + ",\n".join(
        f"    {key}=%nrstr({value})" for key, value in values
    ) + "\n);\n"


def build(mode, config_path):
    sources = list(RECIPES[mode])
    cfg = None if mode == "smoke" else load_config(config_path)
    if mode == "outcome_models" and cfg["analysis_arms"] != [0, 1, 2]:
        raise ValueError("Program 02's automated fixture requires the original three arms [0, 1, 2].")
    if cfg is not None:
        sources.insert(0, "utilities/utilities.SAS")
    text = [
        f"/* GENERATED FILE: {mode}. Rebuild after source/configuration changes.\n",
        "   Submit this ENTIRE file to the SAS session.\n",
        "   It embeds all dependencies; no server-side source checkout is needed.\n",
        "   Regenerates WORK outputs. Start with a healthy/new SAS session. */\n\n",
    ]
    hashes = {}
    for name in sources:
        if mode == "inference" and name == "sas/03_aipw_estimation.sas":
            text.append("\n%_car_pipeline_prepare;\n")
        data = (ROOT / name).read_bytes()
        hashes[name] = hashlib.sha256(data).hexdigest()
        text.extend([f"\n/* ===== Source: {name} ===== */\n", data.decode(), "\n"])
        if name == "utilities/utilities.SAS":
            text.append(sas_config(cfg))
            if mode == "inference":
                text.append("\n%car_report_start;\n")
    if mode == "smoke":
        text.append("\n%put NOTE: CAR_TEST_FAILURES=&car_test_failures;\n")
    if mode == "inference":
        text.append("\n%_car_pipeline_finish;\n%car_export_results;\n%car_report_finish;\n")
    output = ROOT / "run" / "run.sas"
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text("".join(text))
    manifest = {
        "mode": mode, "source_sha256": hashes,
        "bundle_sha256": hashlib.sha256(output.read_bytes()).hexdigest(),
    }
    if cfg is not None:
        manifest["configuration"] = cfg
        manifest["input_sha256"] = hashlib.sha256((ROOT / cfg["input_csv"]).read_bytes()).hexdigest()
    logdir = ROOT / "output" / "build"
    logdir.mkdir(parents=True, exist_ok=True)
    (logdir / f"{mode}.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"Built {output.relative_to(ROOT)}")
    print(f"Mode: {mode}. Open run/run.sas and submit the entire file to the SAS session.")


def reference(mode, config_path):
    cfg = load_config(config_path)
    rscript = shutil.which("Rscript")
    if not rscript:
        raise ValueError("Rscript is not installed or is not on PATH.")
    output = ROOT / "output" / mode
    arms = ",".join(map(str, cfg["analysis_arms"]))
    if mode == "outcome_models":
        args = ["validation/reference_outcome_models.R", cfg["input_csv"], str(output), arms]
    else:
        args = ["validation/reference_inference.R", cfg["input_csv"], str(output),
                cfg["analysis_model"], cfg["car_scheme"], arms, str(cfg["alpha"])]
    subprocess.run([rscript, *args], cwd=ROOT, check=True)
    server_key = "server_outcome_reference_dir" if mode == "outcome_models" else "server_inference_reference_dir"
    print(f"Reference written to {output.relative_to(ROOT)}")
    print(f"Upload its CSVs to the SAS server directory: {cfg[server_key]}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, default=ROOT / "utilities/config.local.json")
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("init", help="Create personal configuration without overwriting existing settings")
    builder = commands.add_parser("build", help="Generate a self-contained SAS run file")
    builder.add_argument("mode", choices=RECIPES)
    ref = commands.add_parser("reference", help="Generate an R reference using the same settings")
    ref.add_argument("mode", choices=("outcome_models", "inference"))
    args = parser.parse_args()
    try:
        if args.command == "init":
            if args.config.exists():
                print(f"Configuration already exists; kept unchanged: {args.config}")
            else:
                args.config.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(ROOT / "utilities/config.example.json", args.config)
                print(f"Edit the server paths in {args.config}")
        elif args.command == "build":
            build(args.mode, args.config)
        else:
            reference(args.mode, args.config)
    except (ValueError, OSError, subprocess.CalledProcessError) as exc:
        parser.exit(1, f"Error: {exc}\n")


if __name__ == "__main__":
    main()
