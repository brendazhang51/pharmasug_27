# Program 02: Continuous-Outcome Working Models

Use the generated `run/run.sas` from
[the quick start](quickstart.md). It configures paths, imports the data through
Program 01, defines Program 02 and runs its validation in one SAS submission.
Program 02 requires SAS/STAT and uses `WORK.ANALYSIS_DATA` without reading
another CSV.

TRT is categorical. All arms present in the input are retained (currently
three); X1_ANALYSIS and X3_ANALYSIS are used without centering. Stratum fields
remain in ANALYSIS_DATA for later stages and are not regression covariates.

| Method | Linear working model |
|---|---|
| ANOVA | AVAL = TRT |
| ANCOVA | AVAL = TRT + X1_ANALYSIS + X3_ANALYSIS |
| ANHECOVA | ANCOVA terms plus TRT-by-covariate interactions |

The file defines `%car_fit(data=work.analysis_data, method=ALL)` without
running it. Manual callers can request ALL, ANOVA, ANCOVA, or ANHECOVA. The
macro returns global `CAR_FIT_RC=0` on success and 1 on failure; check it before
proceeding. The generated validation run stops on failed assertions.

Validation checks required columns, numeric treatment/outcome/covariates,
missing values (including ID), unique IDs, nonempty data, at least two arms
and two rows per arm. All methods use the same complete population. Each fit
must have the expected identifiable rank and positive error degrees of freedom.
For K arms, expected ranks are K, K+2, and 3K respectively. A constant or
collinear covariate can fail these checks even if SAS can produce some fitted
values. GLM's redundant CLASS parameters alone are not a rank failure.

| WORK output | Contents |
|---|---|
| MODEL_PARAMETERS | Model label and SAS Parameter, Estimate, StdErr, tValue, Probt |
| MODEL_FITTED | MODEL, USUBJID, TRT, AVAL, PREDICTED, RESIDUAL |
| MODEL_DIAGNOSTICS | MODEL, N, EXPECTED_RANK, MODEL_RANK, ERROR_DF, SSE, MSE |
| CAR_MODEL_ANOVA / ANCOVA / ANHECOVA | Item stores for PROC PLM scoring in Program 03 |

Every call removes previous Program 02 outputs and stores, including methods
not requested in the new call. Failure removes partially generated public
outputs; WORK._CF_* scratch tables may remain for investigation. These output
and scratch names must not be used as input datasets. All outputs are temporary.

The predictions are for each participant's observed arm. Program 03 scores every participant under each possible arm. Program 02 does not calculate
AIPW, joint calibration, or final CAR inference. Parameter SEs and p-values are
ordinary GLM diagnostics, not CAR-adjusted treatment-effect inference. SAS and
R may use different coefficient coding; compare fitted values and SSE rather
than CLASS coefficients directly.

## Validation

Generate the independent base-R reference and a complete SAS submission:

```sh
python run/project.py reference outcome_models
python run/project.py build outcome_models
```

Upload the two CSVs from `output/outcome_models/` to the configured
`server_outcome_reference_dir`, then submit `run/run.sas` in full.
The automated fixture expects the original 500-row, three-arm CSV. It checks
sample sizes, ANOVA means, decomposition, PLM scoring, two-arm fitting,
single-method calls and invalid inputs, and restores default outputs afterward.

The comparison uses explicit CSV types, full joins and
`abs(SAS-R) <= 1e-8 + 1e-8*abs(R)`. Inspect `WORK.P02_R_SUMMARY`,
`WORK.P02_R_FITTED_COMPARE` and `WORK.P02_R_DIAGNOSTICS_COMPARE`.
The reference generator records R version, input MD5, arms and sample size.
The direct R script retains its optional arm-subset argument for manual checks.

The earlier Program 02/base-R comparison passed in SAS; PR #7 report integration
and the generated run file still need a SAS rerun. See
[the verification record](validation_status.md). This checks working-model fits,
not RobinCar's later CAR variance.
