# Program 01: Data Preparation

`sas/01_data_preparation.sas` imports, checks, standardizes, and summarizes the
RobinCar example CSV for subsequent outcome modeling.

Use the generated outcome-model or inference entry point from
[the quick start](quickstart.md). It embeds `%car_config` and its call from
`utilities/config.local.json` before submitting Program 01. Manual callers
must call `%car_config` first in the same SAS session.

The program:

1. Imports the CSV and checks that all ten required source columns exist.
2. Generates a row-based `USUBJID` and standardizes treatment (`TRT`), observed
   outcome (`AVAL`), covariates (`X1_ANALYSIS`, `X3_ANALYSIS`), and strata (`STRATA`).
3. Records missing analysis values, invalid treatment levels, and inconsistent
   stratum labels in `QC_ISSUES`, stopping when these errors are found.
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
