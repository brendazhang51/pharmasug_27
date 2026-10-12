# Program 02: Continuous-Outcome Working Models

Run `utilities.SAS`, `01_data_preparation.sas`, and then
`02_outcome_models.sas` in the same SAS session. Program 02 requires SAS/STAT
and uses the existing `WORK.ANALYSIS_DATA`; it does not read another CSV.

TRT is categorical. All arms present in the input are retained (currently
three); X1_ANALYSIS and X3_ANALYSIS are used without centering. Stratum fields
remain in ANALYSIS_DATA for later stages and are not regression covariates.

| Method | Linear working model |
|---|---|
| ANOVA | AVAL = TRT |
| ANCOVA | AVAL = TRT + X1_ANALYSIS + X3_ANALYSIS |
| ANHECOVA | ANCOVA terms plus TRT-by-covariate interactions |

The file defines and immediately calls `%car_fit(data=work.analysis_data,
method=ALL)`. After that first run, call the macro again with ALL, ANOVA,
ANCOVA, or ANHECOVA. The macro returns global CAR_FIT_RC=0 on success, 1 on
failure. Check this code before proceeding; the file's default driver cancels
submission when the macro fails.

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

The predictions are for each participant's observed arm. Program 03 will
score every participant under each possible arm. Program 02 does not calculate
AIPW, joint calibration, or final CAR inference. Parameter SEs and p-values are
ordinary GLM diagnostics, not CAR-adjusted treatment-effect inference. SAS and
R may use different coefficient coding; compare fitted values and SSE rather
than CLASS coefficients directly.

## Validation

After running Programs 01 and 02 on the original three-arm CSV, submit
`validation/test_outcome_models.sas`. It checks 500 rows per model, 1,500 fitted
rows overall, ANOVA arm means, outcome decomposition, all three PLM stores,
two-arm fitting, single-method calls, and invalid inputs. Tests restore the
default successful outputs at the end.

For an independent base-R reference, run from repository root:

```sh
Rscript validation/reference_outcome_models.R robincar_example_data.csv reference_output
```

Upload the two reference CSVs to an accessible directory on the SAS server.
Before running the SAS test script, set:

```sas
%let reference_dir=/your/server/reference_output;
```

The test compares predictions, residuals, SSE, MSE, ranks, and sample sizes;
numeric comparisons use `abs(SAS-R) <= 1e-8 + 1e-8*abs(R)`. Without reference_dir,
the R comparison is skipped. The reference script records R version, input
MD5, selected arms and sample size. Its optional third argument `0,1` generates
a two-arm reference for manual follow-up comparisons; the automated test's
optional R comparison expects the original three-arm population.

SAS and R are unavailable in the development workspace. Static inspection and
independent Python checks of the source-data model ranks were performed;
execution of the supplied SAS/R scripts, PLM scoring, and SAS/R numerical
agreement remain to be verified in the target environments. The R reference
checks the working-model fit only, not RobinCar's later CAR variance calculation.
