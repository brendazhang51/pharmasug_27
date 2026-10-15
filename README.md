# Robust Covariate Adjustment under CAR in SAS

All SAS code in this repository is run using SAS Viya.

SAS implementations of continuous-outcome AIPW inference, joint calibration,
CAR variance and treatment contrasts, checked against RobinCar **1.2.0**.
This is an independent methodological research project.

## Start here

Read [the quick start](doc/quickstart.md). Use the single generated `run/run.sas` entry point; each embeds its configuration and macro dependencies for submission
to the SAS session. A server-side checkout of this repository is not required.

Your current local configuration is `utilities/config.local.json` (not committed).
For a new checkout:

```bash
python run/project.py init
# Edit the server paths in utilities/config.local.json.
python run/project.py build smoke
```

Submit the **entire generated `run/run.sas` file** to the SAS session.
The terminal command builds the file; the SAS session executes it.
Require `CAR_TEST_FAILURES=0` and no unexpected errors.

| Workflow | Terminal command | File to submit in SAS |
|---|---|---|
| Synthetic tests | `python run/project.py build smoke` | `run/run.sas` |
| Program 02 and optional R comparison | `python run/project.py build outcome_models` | `run/run.sas` |
| Programs 01–07, selected-model/RobinCar comparison and automatic export | `python run/project.py build inference` | `run/run.sas` |

Each build replaces `run/run.sas`; build and submit one workflow at a time.
The inference run includes Program 03 unchanged. Programs 04–06 directly use
the selected model predictions and means; see [the native data contracts](doc/data_contracts.md).
Standalone Program 03 tests still use the
[manual workflow](doc/quickstart.md#4-validate-program-03-aipw-point-estimates);
there is no separate `build aipw` or `reference aipw` command.

Generate references with the same configuration, then upload their CSVs to the
configured server directories:

```bash
python run/project.py reference outcome_models
python run/project.py reference inference
```

The first command uses base R; the second requires RobinCar 1.2.0.
Rebuild a SAS entry point whenever its sources or configuration change.

## Implementation and validation

The SAS execution log dated 2026-10-15 confirms the integrated workflow passed
for 500 participants, arms 0/1/2, ANCOVA, simple randomization, type-1 variance,
joint calibration and 95% intervals. Model fitting, AIPW computation, inference
and the reference suite returned 0; the suite produced 38 checks. Eight CSVs,
four result plots and the full HTML report were saved without ERROR/WARNING
log lines. Earlier standalone Program 02/base-R and 04–07 smoke checks also
passed; see [the verification record](doc/validation_status.md).

Program 02/03 support ANOVA, ANCOVA and ANHECOVA; the generated inference and
reference commands select `analysis_model` (default ANCOVA). Permuted-block and two-arm synthetic tests
have passed; complete data-based SAS/R inference comparisons for those settings
remain pending. See [supported features and limits](doc/support_matrix.md) for
macro capabilities, workflow restrictions and remaining validation work.

| Source | Role | Details |
|---|---|---|
| Program 01 | Import and prepare the analysis population | [Summary](doc/program_01_summary.md) |
| Program 02 | ANOVA, ANCOVA, ANHECOVA working-model fits | [Summary](doc/program_02_summary.md) |
| Program 03 | Arm-specific predictions and AIPW point estimates | [Summary](doc/program_03_summary.md) |
| Program 04 | Linear/joint calibration | [Summary](doc/program_04_summary.md) |
| Program 05 | Type-1 CAR covariance and mean inference | [Summary](doc/program_05_summary.md) |
| Program 06 | Linear contrasts using complete covariance | [Summary](doc/program_06_summary.md) |
| Program 07 | Keyed comparison with mixed tolerances | [Summary](doc/program_07_summary.md) |

## Repository layout

| Directory | Contents |
|---|---|
| [sas/](sas/README.md) | Analysis programs, inference pipeline, macro definitions and input contracts |
| [run/](run/README.md) | Entry-point builder and generated SAS submission |
| [utilities/](utilities/README.md) | Configuration template and shared helpers |
| [data/](data/README.md) | Versioned example input CSV |
| [validation/](validation/README.md) | Test implementations, comparison suite and R exporters |
| [examples/](examples/README.md) | Independent experimental binomial/MI example |
| [notebooks/](notebooks/README.md) | Interactive notes and exploration |
| [doc/](doc/README.md) | Quick start, methodology, program summaries and verification record |
| `output/` | Generated references and build manifests; ignored by Git |

See [the methodology](doc/methodology.md) for statistical background.
The five-arm binomial/MI example is experimental and has not been numerically
validated. Current continuous inference uses normal approximations and does
not address missing outcomes, nonlinear contrasts or multiplicity adjustment.
