# Validation Implementations

Use [run/](../run/README.md) for complete, generated SAS submissions.
This directory contains the underlying tests, comparison suite and R exporters.
Shared helpers live in [utilities/](../utilities/README.md).

| File | Purpose |
|---|---|
| `reference_outcome_models.R` | Independent base-R working-model fit reference |
| `robincar_reference.R` | RobinCar 1.2.0 original and calibrated inference reference |
| `test_reference_export.R` | Base-R helper checks and 15 real RobinCar integration scenarios |
| `test_outcome_models.sas` | Program 02 assertions and optional R comparison reports |
| `smoke_04_07.sas` | Analytic and invalid-input fixtures for 04–07 |
| `inference_suite.sas` | Defines typed imports, metadata/population checks and complete numerical comparisons |
| `test_project.py` | Entry-point/configuration checks without SAS |

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
respective Viya directories from your local config. The server directories
need not have the same names as the local output folders.

## Viya checks

Build and submit the full `run/run_smoke.sas`, `run/run_outcome_models.sas`, or
`run/run_inference.sas` as described in [the quick start](../doc/quickstart.md).
The synthetic tests deliberately emit errors for invalid inputs; require all
assertions to pass and `CAR_TEST_FAILURES=0`, with no unexpected SAS errors.

For full inference, inspect `WORK.CAR_VALIDATION_SUITE`,
`WORK.CAR_VALIDATION_DETAILS` and `CAR_SUITE_RC` (0 success, 1 failure, 2 missing
reference). The suite checks model, design, variance type, arm order, alpha and
population identity before numeric comparisons. A failure stays a failure even
if later comparisons pass. Numeric defaults are `atol=1e-8`, `rtol=1e-6`.

See [the verification record](../doc/validation_status.md) for completed checks
and outstanding Viya runs after the layout refactor.
