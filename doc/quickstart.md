# Quick Start

## Prerequisites for each colleague

- Python 3 for generating the SAS submission files; no extra Python packages
  are required.
- Access to a SAS session with SAS/STAT and SAS/IML.
- R with `Rscript` available in the terminal for reference generation. Program
  02 and 03 references use base R; the inference reference requires RobinCar 1.2.0.
  R and RobinCar are not needed for the synthetic smoke test.

Clone the repository, or update your existing checkout, before following the
steps below. For a new checkout:

```bash
git clone https://github.com/brendazhang51/pharmasug_27.git
cd pharmasug_27
```

Each colleague uses their own local configuration. `utilities/config.local.json`,
generated `run/run.sas` files and the entire `output/` directory are ignored
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
The four `server_*` paths refer to files/directories on the SAS server,
not `/workspaces/...` paths. Your existing server CSV and uploaded reference
directories can stay where they are; moving local output folders does not move
server files.

For the standard example, change these four fields to directories/files
accessible to your own server account:

| Configuration field | Your value |
|---|---|
| `server_input_csv` | Full server path to the uploaded original CSV, including its filename |
| `server_outcome_reference_dir` | Server directory for the two Program 02 reference CSVs |
| `server_inference_reference_dir` | Server directory for the 17 inference reference CSVs |
| `server_export_dir` | Existing writable server directory for CSVs, HTML and PNGs |

Keep the remaining fields at their validated example settings initially:

```json
{
  "input_csv": "data/robincar_example_data.csv",
  "analysis_arms": [0, 1, 2],
  "analysis_model": "ANCOVA",
  "car_scheme": "simple",
  "alpha": 0.05
}
```

This fragment shows the unchanged fields only; keep all four `server_*` fields
in your configuration too. Upload `data/robincar_example_data.csv` unchanged to
the location specified by `server_input_csv` before running either data-based
SAS entry point. Create the two server reference directories and the export directory as needed; the
local R commands cannot create directories on the remote SAS server.

`analysis_arms`, `analysis_model`, `car_scheme` and `alpha` are shared by the generated SAS run
and R reference commands. The downstream inference uses the selected model (default ANCOVA), type-1 variance, joint
calibration and no extra calibration covariates. Arm labels must be distinct
integers in ascending order. The standard example uses `[0, 1, 2]`, `simple`
and `0.05`; the design is an explicit algorithm demonstration setting unless
verified from trial documentation.

Every `build` command below writes **the same `run/run.sas` file**. Build a
mode, submit it, then build the next mode. The file header shows its mode.

## 2. Run synthetic tests

```bash
python run/project.py build smoke
```

Submit the entire `run/run.sas` file to the SAS session. This entry point embeds all dependencies, uses its own
fixtures, and requires no data upload, local configuration or RobinCar.
The run includes 04–07 fixtures and native Program 03 input-contract
checks. Require `CAR_TEST_FAILURES=0`. Errors deliberately emitted for invalid inputs
must be followed by passing assertions; unexpected SAS errors require review.

## 3. Validate Program 02

```bash
python run/project.py reference outcome_models
python run/project.py build outcome_models
```

Upload the two CSVs from `output/outcome_models/` to the configured
`server_outcome_reference_dir`. Open and submit all of
`run/run.sas`. It imports the server CSV, defines Program 02,
and runs its tests and R comparison. The automated fixture requires the original
500-row CSV and all three arms. Require the R comparison success message,
no failed assertions, and no unexpected SAS errors. Inspect `WORK.P02_R_SUMMARY`
and the `WORK.P02_R_*_COMPARE` tables.

## 4. Validate Program 03 AIPW point estimates

Program 03 testing passed on 2026-10-14 (user-confirmed). Its workflow is
manual; `run/project.py` does not yet provide `build aipw` or `reference aipw`.
Use the original 500-row, three-arm CSV for the automated test.

Generate its independent base-R references from repository root:

```bash
Rscript validation/reference_aipw.R data/robincar_example_data.csv output/aipw
```

Upload `reference_aipw_predictions.csv` and `reference_aipw_means.csv` from
`output/aipw/` to an existing directory accessible to your server account.
Retain `reference_aipw_provenance.txt` locally. The generated references are
ignored by Git; you do not need a checked-in `reference_output/` directory.

Submit the following files and calls **in order, in the same SAS session**:

1. Submit `utilities/utilities.SAS` to define the configuration macro, then
   call it with your uploaded CSV path:

   ```sas
   %car_config(csv_path=/your/server/robincar_example_data.csv, arms=0 1 2);
   ```

2. Submit `sas/01_data_preparation.sas`.
3. Submit `sas/02_outcome_models.sas`, then run `%car_fit();` to fit all three
   working models. Loading Program 02 alone does not fit them.
4. Submit `sas/03_aipw_estimation.sas`. Its driver automatically calls
   `%car_aipw()` and prints the arm means.
5. Set the directory containing the two uploaded AIPW reference CSVs, then
   submit `validation/test_aipw_estimation.sas`:

   ```sas
   %let reference_dir=/your/server/aipw;
   ```

`reference_dir` is shared with Program 02's comparison. Set it to the AIPW
reference directory **after** any Program 02 tests; reset it to the Program 02
reference directory before rerunning those tests. If it is blank, the Program
03 R comparison is skipped, so the final test message alone does not establish
SAS/R agreement.

| Check | Expected result |
|---|---|
| Program 02 fits | `CAR_FIT_RC=0` |
| Program 03 computation | `CAR_AIPW_RC=0` |
| `WORK.AIPW_PREDICTIONS` | 4,500 rows across three models and three target arms |
| `WORK.AIPW_MEANS` | Nine arm/model rows |
| R comparison | Log contains `Program 03 SAS/R predictions and AIPW means agree.` |
| Test completion | Log contains `Program 03 tests passed.` and no failed assertions or unexpected errors |

Inspect `WORK.P03_R_MEAN_COMPARE` for the nine SAS/R arm-mean comparisons.
The test also checks a two-arm subset, then restores the full three-arm fits
and AIPW outputs. Program 03 produces point estimates; the generated inference
run below uses its selected-model outputs directly in Programs 04–06.

The inference run below saves the full displayed output and compact final
results automatically. Standalone Program 03 validation does not invoke the
inference exporter. See [saving results](#save-result-tables-and-graphics) for
what is retained and how the destination is configured.

## 5. Validate the continuous inference example

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
Open and submit all of `run/run.sas`. It imports the data, loads
all macros, runs Programs 02 and 03, directly uses the selected model outputs and compares the
complete original/calibrated inference. Program 03 is embedded unchanged: its
automatic driver requires ALL working models, so Program 02 fits ALL first.
Set `analysis_model` to `ANOVA`, `ANCOVA` or `ANHECOVA` for downstream inference
and the matching reference comparison. Older JSON files without this field
default to ANCOVA.
A server-side copy of the SAS sources is not needed. See
[the native data contracts](data_contracts.md) for input fields and checks.

| Check | Expected result |
|---|---|
| Data preparation | `CAR_DATA_RC=0` |
| Program 02 fitting | `CAR_FIT_RC=0` |
| Program 03 computation | `CAR_AIPW_RC=0` |
| Example computation | `EXAMPLE_RC=0` |
| Complete reference comparison | `CAR_SUITE_RC=0` |
| `WORK.CAR_VALIDATION_SUITE` | All checks PASS |
| SAS log | No unexpected ERROR or WARNING |

`CAR_SUITE_RC=1` means failure; 2 means the reference is unavailable and the
run is not validated. A calculation success alone does not establish SAS/R
agreement. The driver prints up to 50 detail rows on failure; full details remain
in `WORK.CAR_VALIDATION_DETAILS`.

## 6. Keep a verification record

Save the SAS log and summary for each configuration, together with the reference
settings, input hash and session information. `output/build/` records source
hashes, bundle hashes and configuration for each generated entry point. The single `run/run.sas` is replaced by every build, and each mode's manifest
is overwritten when rebuilding that mode; copy completed runs into a dated
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

## Save result tables and graphics

Set `server_export_dir` in `utilities/config.local.json` to an existing writable
server directory, then run:

```bash
python run/project.py build inference
```

Submit the **entire** `run/run.sas` to the SAS server. This single submission performs
analysis, validation and export. No separate submission of
`sas/export_results.sas` is needed. Active export macros live in
`sas/inference_pipeline.sas`; the builder embeds and calls them after the suite.
The copy in `sas/deprecated/` is historical and is not a build dependency.

Default CSV deliverables:

| File | Contents |
|---|---|
| `car_mean_inference.csv` | Original means, SEs, confidence limits and tests |
| `car_contrast_results.csv` | Original treatment differences and inference |
| `car_cal_inference.csv` | Calibrated means and inference |
| `car_cal_contrasts.csv` | Calibrated differences and inference |
| `car_run_settings.csv` | Model, design and analysis settings |
| `car_validation_suite.csv` | Final PASS/FAIL/NOT_RUN checks |
| `allocation_summary.csv` | Treatment allocation within strata |
| `baseline_summary.csv` | Baseline covariate summaries |

`car_validation_details.csv` is additionally exported when `CAR_SUITE_RC=1`;
`qc_issues.csv` is exported only when it contains findings. Intermediate
predictions, fitted values, variance components and covariance CSVs are not
exported by default. They remain available as WORK tables in the SAS session.

`full_results.html` captures all displayed output from Program 01 through the
suite, including MEANS/FREQ/GLM/PLM output and original procedure graphics.
The export step appends four result plots (`original_means.png`,
`original_contrasts.png`, `calibrated_means.png`, `calibrated_contrasts.png`),
then reprints the validation summary so PASS/FAIL checks remain the last table.
The procedure graphics use `analysis_plot*.png`. Download the HTML and all its
PNGs together into the same folder. No duplicate `inference_report.html` is
created. The report is not the SAS log; save the log separately.

Files are written on the **SAS server**, not the local workspace. Existing
names may be overwritten. Old extra files from earlier exports are not removed;
use a fresh directory for each run to keep deliverables distinct. If execution
aborts, outputs can be incomplete. Check `CAR_SUITE_RC`, the validation summary
and the log; export completion alone does not establish validation success.

Program 01 now invalidates previous WORK analysis outputs before importing a
new source. Import/schema/QC failures cancel before fitting; QC failures also
attempt to save `qc_issues.csv` and finalize the open HTML report. Earlier CSVs
on disk are not removed. Check the current log and `CAR_DATA_RC`; old files in
the directory do not establish that the current run succeeded.
