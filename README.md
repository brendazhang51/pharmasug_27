# Robust Covariate Adjustment under CAR in SAS

SAS implementations of continuous-outcome AIPW inference, joint calibration,
CAR variance and treatment contrasts, checked against RobinCar **1.2.0**.
This is an independent methodological research project.

## Start here

Read [the quick start](doc/quickstart.md). Use one generated SAS run file per
workflow; each embeds its configuration and macro dependencies for submission
from VS Code to Viya. A server-side checkout of this repository is not required.

Your current local configuration is `utilities/config.local.json` (not committed).
For a new checkout:

```bash
python run/project.py init
# Edit the Viya paths in utilities/config.local.json.
python run/project.py build smoke
```

Open the generated `run/run_smoke.sas` in VS Code and submit the **entire file**
through the SAS extension. The terminal command builds it; SAS executes on Viya.
Require `CAR_TEST_FAILURES=0` and no unexpected errors.

| Workflow | Terminal command | File to submit in SAS/Viya |
|---|---|---|
| Synthetic tests | `python run/project.py build smoke` | `run/run_smoke.sas` |
| Program 02 and optional R comparison | `python run/project.py build outcome_models` | `run/run_outcome_models.sas` |
| ANCOVA example and complete RobinCar comparison | `python run/project.py build inference` | `run/run_inference.sas` |

Program 03 uses a manual workflow: run Programs 01–03 and then
`validation/test_aipw_estimation.sas` in one SAS session. See
[Program 03 setup and validation](doc/quickstart.md#4-validate-program-03-aipw-point-estimates).
The builder does not yet support `build aipw` or `reference aipw`.

Generate references with the same configuration, then upload their CSVs to the
configured Viya directories:

```bash
python run/project.py reference outcome_models
python run/project.py reference inference
```

The first command uses base R; the second requires RobinCar 1.2.0.
Rebuild a SAS entry point whenever its sources or configuration change.

## Implementation and validation

User-provided Viya logs confirm Program 02's three-model base-R comparison,
the 04–07 smoke tests, and the full three-arm ANCOVA/simple/type-1/95% CI
comparison against RobinCar 1.2.0 passed. These results predate this layout
refactor. The newly generated entry points and the combined PR #7 Program 02
report still require Viya execution; see [the verification record](doc/validation_status.md).

Program 03 provides AIPW point estimates and was successfully tested on
2026-10-14, as confirmed by the user. The continuous example supplies an ANCOVA
and AIPW bridge for checking 04–07. Permuted-block and two-arm synthetic tests
have passed; complete data-based SAS/R comparisons for those settings remain pending.

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
| [sas/](sas/README.md) | Analysis programs, macro definitions and input contracts |
| [run/](run/README.md) | Entry-point builder and generated SAS submissions |
| [utilities/](utilities/README.md) | Configuration template and shared helpers |
| [data/](data/README.md) | Versioned example input CSV |
| [validation/](validation/README.md) | Test implementations, comparison suite and R exporters |
| [examples/](examples/README.md) | Continuous bridge and experimental binomial example |
| [notebooks/](notebooks/README.md) | Interactive notes and exploration |
| [doc/](doc/README.md) | Quick start, methodology, program summaries and verification record |
| `output/` | Generated references and build manifests; ignored by Git |

See [the methodology](doc/methodology.md) for statistical background.
The five-arm binomial/MI example is experimental and has not been numerically
validated. Current continuous inference uses normal approximations and does
not address missing outcomes, nonlinear contrasts or multiplicity adjustment.
