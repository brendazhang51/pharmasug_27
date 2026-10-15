# Quick Start

## Prerequisites for each colleague

- Python 3 for generating the SAS submission files; no extra Python packages
  are required.
- VS Code with the SAS extension, connected to Viya using your own account and
  connection profile. The SAS environment must provide SAS/STAT and SAS/IML.
- R with `Rscript` available in the terminal for reference generation. Program
  02's reference uses base R; the inference reference requires RobinCar 1.2.0.
  R and RobinCar are not needed for the synthetic smoke test.

Clone the repository, or update your existing checkout, before following the
steps below. For a new checkout:

```bash
git clone https://github.com/brendazhang51/pharmasug_27.git
cd pharmasug_27
```

Each colleague uses their own local configuration. `utilities/config.local.json`,
generated `run/run_*.sas` files and the entire `output/` directory are ignored
by Git: they do **not** arrive when you clone or pull the repository. Generate
them locally using the commands below. You do not need to edit the analysis
programs in `sas/` to change your server paths.

## 1. Configure once

From a terminal at repository root:

```bash
python run/project.py init
```

Edit `utilities/config.local.json`. An existing file is kept unchanged by `init`.
`input_csv` is the local R input, normally `data/robincar_example_data.csv`.
The three `server_*` paths refer to files/directories on the Viya server,
not `/workspaces/...` paths. Your existing server CSV and uploaded reference
directories can stay where they are; moving local output folders does not move
server files.

For the standard example, change only these three fields to directories/files
accessible to your own Viya account:

| Configuration field | Your value |
|---|---|
| `server_input_csv` | Full server path to the uploaded original CSV, including its filename |
| `server_outcome_reference_dir` | Server directory for the two Program 02 reference CSVs |
| `server_inference_reference_dir` | Server directory for the 17 inference reference CSVs |

Keep the remaining fields at their validated example settings initially:

```json
{
  "input_csv": "data/robincar_example_data.csv",
  "analysis_arms": [0, 1, 2],
  "car_scheme": "simple",
  "alpha": 0.05
}
```

This fragment shows the unchanged fields only; keep all three `server_*` fields
in your configuration too. Upload `data/robincar_example_data.csv` unchanged to
the location specified by `server_input_csv` before running either data-based
SAS entry point. Create the two server reference directories as needed; the
local R commands cannot create directories on the remote Viya server.

`analysis_arms`, `car_scheme` and `alpha` are shared by the generated SAS run
and R reference commands. The bridge uses ANCOVA, type-1 variance, joint
calibration and no extra calibration covariates. Arm labels must be distinct
integers in ascending order. The standard example uses `[0, 1, 2]`, `simple`
and `0.05`; the design is an explicit algorithm demonstration setting unless
verified from trial documentation.

## 2. Run synthetic tests

```bash
python run/project.py build smoke
```

Open `run/run_smoke.sas`, select its entire contents and submit through the
VS Code SAS extension. This entry point embeds all dependencies, uses its own
fixtures, and requires no data upload, local configuration or RobinCar.
Require `CAR_TEST_FAILURES=0`. Errors deliberately emitted for invalid inputs
must be followed by passing assertions; unexpected SAS errors require review.

## 3. Validate Program 02

```bash
python run/project.py reference outcome_models
python run/project.py build outcome_models
```

Upload the two CSVs from `output/outcome_models/` to the configured
`server_outcome_reference_dir`. Open and submit all of
`run/run_outcome_models.sas`. It imports the server CSV, defines Program 02,
and runs its tests and R comparison. The automated fixture requires the original
500-row CSV and all three arms. Require the R comparison success message,
no failed assertions, and no unexpected SAS errors. Inspect `WORK.P02_R_SUMMARY`
and the `WORK.P02_R_*_COMPARE` tables.

## 4. Validate the continuous inference example

```bash
python run/project.py reference inference
python run/project.py build inference
```

The reference command requires RobinCar **1.2.0** in the R library used by
`Rscript`. You can check that prerequisite in the terminal:

```bash
Rscript -e 'stopifnot(as.character(packageVersion("RobinCar")) == "1.2.0")'
```

If this fails, install RobinCar 1.2.0 and its dependencies in that R environment
before generating the reference. Upload all **17 CSVs** in `output/inference/` to
`server_inference_reference_dir`; retain `sessionInfo.txt` with the local record.
Open and submit all of `run/run_inference.sas`. It imports the data, loads
all macros, runs the ANCOVA/AIPW bridge and compares the complete results.
A server-side copy of the SAS sources is not needed.

| Check | Expected result |
|---|---|
| Example computation | `EXAMPLE_RC=0` |
| Complete reference comparison | `CAR_SUITE_RC=0` |
| `WORK.CAR_VALIDATION_SUITE` | All checks PASS |
| SAS log | No unexpected ERROR or WARNING |

`CAR_SUITE_RC=1` means failure; 2 means the reference is unavailable and the
run is not validated. A calculation success alone does not establish SAS/R
agreement. The driver prints up to 50 detail rows on failure; full details remain
in `WORK.CAR_VALIDATION_DETAILS`.

## 5. Keep a verification record

Save the SAS log and summary for each configuration, together with the reference
settings, input hash and session information. `output/build/` records source
hashes, bundle hashes and configuration for each generated entry point. Files
are overwritten when rebuilding the same mode; copy completed runs into a dated
subdirectory under `output/` if they need to be retained. Results are local and
ignored by Git.

Rebuild after any source/configuration change. Use a healthy SAS session; after
an unexpected parser/runtime error, a fresh session is the most predictable way
to restart. Each generated entry point contains everything needed for its run,
so macros do not have to be loaded manually. No SAS execution happens in the
Codespaces terminal.

After pulling later source changes, rebuild the SAS run files before submitting
them. Your ignored local configuration is retained. If a configuration change
affects the population, design or alpha, also regenerate and upload the matching
R references.

For another inference setting, change the shared config, regenerate the R
reference, upload all CSVs, rebuild the inference run and submit it. Never compare
new SAS results against an older reference with different settings.
