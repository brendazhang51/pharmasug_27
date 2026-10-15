# Validation Implementations

Use [run/](../run/README.md) for complete, generated SAS submissions.
This directory contains the underlying tests, comparison suite and R exporters.
Shared helpers live in [utilities/](../utilities/README.md).

| File | Purpose |
|---|---|
| `reference_aipw.R` | Independent base-R Program 03 predictions and AIPW arm means |
| `test_data_preparation.sas` | Repeated-run cleanup, missing/unreadable CSV, missing/type-invalid schema and empty-input checks |
| `test_aipw_estimation.sas` | Program 03 assertions, two-arm checks and optional SAS/R comparison |
| `reference_outcome_models.R` | Independent base-R working-model fit reference |
| `reference_inference.R` | RobinCar 1.2.0 original and calibrated inference reference |
| `test_reference_export.R` | Helper checks and 15 RobinCar scenarios, including independent base-R AIPW output mapping |
| `test_outcome_models.sas` | Program 02 assertions and optional R comparison reports |
| `test_inference_smoke.sas` | Analytic, native 03 schema and invalid-input fixtures for 04–07 |
| `test_inference_reference.sas` | Defines typed imports, metadata/population checks and complete numerical comparisons |
| `test_project.py` | Entry-point/configuration checks, including exact unchanged Program 03 embedding |

## Naming

- `test_*.sas` files contain SAS validation code; the generated build controls
  loading and execution. `test_inference_reference.sas` defines the reference
  suite and does not execute on loading.
- `reference_*.R` files generate reference data.
- `test_*.py` and `test_*.R` files check the builder or reference exporters.

Names describe purpose; numbered production programs remain in `sas/` to show
analysis order. The renamed files are `test_inference_smoke.sas` (formerly
`smoke_04_07.sas`), `test_inference_reference.sas` (formerly
`inference_suite.sas`) and `reference_inference.R` (formerly
`robincar_reference.R`). Build commands and SAS macro names are unchanged.

## Local checks

```bash
python -m unittest discover -s validation -p 'test_project.py'
Rscript validation/test_reference_export.R --helpers-only
Rscript validation/test_reference_export.R
```

The full R test requires RobinCar **1.2.0**; the helpers-only test uses base R.
The integration scenarios cover three models, both supported designs, two/three
arms, reversed arm order and 90% versus 95% intervals. They check the exporter,
not SAS/R equivalence.

Generate references using the shared config:

```bash
python run/project.py reference outcome_models
python run/project.py reference inference
```

Outputs go to `output/outcome_models/` (two CSVs plus provenance) and
`output/inference/` (17 CSVs plus session information). Upload all CSVs to the
respective server directories from your local config. The server directories
need not have the same names as the local output folders.

## SAS execution checks

Build the required mode and submit the full `run/run.sas` as described in [the quick start](../doc/quickstart.md).
The synthetic tests deliberately emit errors for invalid inputs; require all
assertions to pass and `CAR_TEST_FAILURES=0`, with no unexpected SAS errors.

For full inference, inspect `WORK.CAR_VALIDATION_SUITE`,
`WORK.CAR_VALIDATION_DETAILS` and `CAR_SUITE_RC` (0 success, 1 failure, 2 missing
reference). The suite checks model, design, variance type, arm order, alpha and
population identity before numeric comparisons. A failure stays a failure even
if later comparisons pass. Numeric defaults are `atol=1e-8`, `rtol=1e-6`.

See [the verification record](../doc/validation_status.md) for completed checks
and outstanding model/design configurations.

## Program 03

Standalone Program 03 validation uses manual submission. Program 03 computation
is also included in the generated inference workflow. Follow
[the quick start](../doc/quickstart.md#4-validate-program-03-aipw-point-estimates)
for loading order, reference generation, upload paths and success checks.
Its references are generated in `output/aipw/` using base R. Set `reference_dir`
to the uploaded AIPW CSV directory before running `test_aipw_estimation.sas`;
it shares that macro variable with the Program 02 comparison. Testing passed
on 2026-10-14 (user-confirmed).

## Data preparation failure checks

`test_data_preparation.sas` exercises the import helpers in SAS; local Python
checks only verify assembly and the guard ordering, not SAS execution.

1. In a test SAS session, submit the generated inference run to load Program 01
   and confirm the baseline analysis succeeds.
2. Open `validation/test_data_preparation.sas` and submit the whole
   file in the same session. It intentionally clears reserved analysis outputs,
   creates temporary fixtures under WORK, and emits expected ERROR messages.
3. Require `CAR_DATA_TEST_FAILURES=0`. It covers valid import followed by stale
   output cleanup and missing input, PROC IMPORT failure with an existing
   directory as input, absent columns, wrong numeric-column types and header-only
   input. Rerun the full workflow afterward to restore actual analysis results.

Also verify the automatic cancellation path by changing `server_input_csv` to
an absent server file, rebuilding and submitting inference after a successful
run. Require `CAR_DATA_RC=1`, no model fitting/export completion for that run,
no previous public WORK results, and report closure. Restore the JSON path and
rebuild before continuing.

For QC preservation, use a separate server copy of the example CSV containing
one missing outcome among otherwise numeric outcomes. Submit a run pointing to
that copy. Require early cancellation, current `WORK.QC_ISSUES` and its CSV when
the export directory is writable; the failure report should be finalized. Keep
the original data unchanged and restore the original configuration afterward.
