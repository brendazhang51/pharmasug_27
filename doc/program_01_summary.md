# Program 01: Data Preparation

`sas/01_data_preparation.sas` imports, checks, standardizes, and summarizes the
RobinCar example CSV for subsequent outcome modeling.

Use the generated outcome-model or inference entry point from
[the quick start](quickstart.md). It embeds `%car_config` and its call from
`utilities/config.local.json` before submitting Program 01. Manual callers
must call `%car_config` first in the same SAS session.

The program:

1. Invalidates reserved prior-run outputs and success return codes before
   checking the new source. Checks that the CSV exists, captures import status
   immediately and rejects failed/empty imports. Checks all ten required source
   columns, numeric analysis inputs and character `strata_cross`.
2. Generates a row-based `USUBJID` and standardizes treatment (`TRT`), observed
   outcome (`AVAL`), covariates (`X1_ANALYSIS`, `X3_ANALYSIS`), and strata (`STRATA`).
3. Records missing analysis values, invalid treatment levels, and inconsistent
   stratum labels in `QC_ISSUES`. On QC failure it prints findings, attempts to
   export `qc_issues.csv` to the configured directory, closes the active report
   and cancels before any model fitting.
4. Selects the treatment arms listed in `analysis_arms`; the current default
   retains all three arms (0, 1, 2), unless already set by the run configuration.
5. Summarizes observed treatment allocation within strata and baseline
   covariates by treatment, and displays the results.

| Output in WORK | Contents |
|---|---|
| `ROBINCAR_RAW` | Imported source data |
| `STANDARDIZED_ALL` | Source data plus standardized variables |
| `QC_ISSUES` | Row-level data issues; empty when checks pass |
| `ANALYSIS_DATA` | Selected analysis population for subsequent programs |
| `ALLOCATION_SUMMARY` | Arm counts and observed proportions within strata |
| `BASELINE_SUMMARY` | Covariate sample sizes, means, SDs, minima, and maxima by arm |

All outputs are temporary and are removed when the SAS session ends. The
program retains `y0`, `y1`, and `y2` for traceability and uses `y` as the observed
outcome. It does not center covariates, fit models, estimate treatment effects,
or infer the randomization design; `car_scheme` remains `NOT_VERIFIED`.

## Failure protection

`CAR_DATA_RC=0` is printed only after preparation completes. A failed run sets
this code to 1 and invalidates previous model, AIPW, inference and validation
outputs in WORK, including model item stores. Unrelated WORK data and old files
on disk are not deleted. Successful previous exports must still be distinguished
by their run directory and log.

The import helper removes old `ROBINCAR_RAW` before checking the source path,
checks `SYSERR` immediately after `PROC IMPORT`, and removes partial imports on
failure. Missing required columns, incorrect analysis-column types, empty input
and an empty selected population stop the pipeline. Traceability-only columns
`y0/y1/y2` must exist but their types are not constrained.

Report closing is guarded so failure paths can call it without popping graphics
options twice. Saving a QC CSV is best effort: on write failure the WORK table
and log remain available. Other early failures do not manufacture QC findings.
See [standalone failure checks](../validation/README.md#data-preparation-failure-checks).
