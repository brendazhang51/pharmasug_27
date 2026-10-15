# Analysis Programs and Macros

Use [the quick start](../doc/quickstart.md) and generated files in `run/` for
complete submissions. `sas/` is the implementation layer. Program 01 runs its
data preparation on submission; Program 03 automatically calls `%car_aipw()`
on submission after Program 02 has been fitted. Program 02 and 04–07 define macros without
automatically running analyses. Load `00_car_common.sas` before calling 04–07.

Programs 04–06 require SAS/IML. Program 02 and the inference pipeline require
SAS/STAT. Configuration comes from `utilities/config.local.json` through the
entry-point builder; `%car_config` is available for manual SAS workflows.

## Input contracts

Each call selects one population, model and estimator. Supply Program 03's
stacked tables directly and select `model=ANOVA`, `ANCOVA` (default) or
`ANHECOVA`. Source tables are read without alteration.

| Input | Required fields |
|---|---|
| Analysis | Character `usubjid strata`; numeric `trt aval`; complete unique subjects |
| Predictions | Character `model usubjid`; numeric `observed_trt target_trt aval predicted observed_residual` |
| Means | Character `model`; numeric `target_trt n_total n_arm observed_mean mean_pred_all mean_pred_arm mean_residual_arm aipw_mean` |
| Mean covariance | Character `model`; numeric `target_trt_i target_trt_j covariance`; all ordered target pairs |
| Contrast coefficients | Character `contrast_id label`; numeric `target_trt coefficient null_value`; every treatment per contrast |

Predictions and means use the exact Program 03 schema. Observed residuals are
missing only for non-observed targets. Raw `predicted` is re-centered internally
using the validated `mean_residual_arm`; there is no external arm map or
pre-centering step. Program 04 publishes the same prediction/mean fields in
`work.car_cal_predictions` and `work.car_cal_means` for direct reuse by 05/06.
See [the data contracts](../doc/data_contracts.md) for calls and API migration.

`strata` encodes the complete joint randomization strata. `add_x` is a
space-separated list of numeric calibration covariates. Missing analysis
values are rejected; each treatment needs at least two observations.

`%car_calibrate(joint=YES)` uses all prediction columns plus S−1 stratum
dummies in each arm-specific regression. `joint=NO` omits strata. SVD handles
aliases; the macro rejects predictions outside the fitted row space and fits
with no residual degrees of freedom. Inspect effective ranks and aliases.

`%car_variance(car_scheme=...,variance_type=1)` supports `simple` and
`permuted-block` only. PB requires every arm×stratum cell. Covariance uses R's
sample denominators n−1 / n_arm−1 and empirical allocation probabilities.
Components `v_sr` and `v_omega` are **not divided by n**; `covariance` is.
Materially non-PSD matrices or any negative diagonal fail rather than being
silently corrected. Zero SE produces `ZERO_SE` and missing z/p-value.

`%car_contrast()` implements `C theta` and `C V C'`. The null is per contrast;
CIs and p-values are marginal normal approximations without multiplicity
adjustment. Ratios and nonlinear contrasts are not implemented.

Always check global **`CAR_RC` immediately after each call**: 0 success,
1 failure, 2 missing reference (`NOT_RUN`). After output names pass checks,
04–06 remove previous outputs and clear partial results on failure. Only the
specified output tables are invalidated; internal diagnostic tables remain.
Names must be distinct, must not overwrite inputs, and must not use reserved
`_CAR_` names. Unsafe names return an error **without deleting any tables**.
Use explicit two-level input/output names when the SAS USER option/library is set.
Only plain V7 names are accepted; dataset options on inputs are not supported.
Numeric arguments must be finite literals; blank, special missing and expression
values are rejected. Success is published only after every output step passes.
Output names must differ from input tables. `WORK._CAR_*` is reserved for
temporary tables; calls are sequential and not re-entrant.

## References and verification

`validation/test_inference_reference.sas` defines `%car_test_inference` and its typed
CSV imports. It checks settings/population identity, raw and centered predictions,
original/calibrated means, complete covariance, SEs, CIs, contrasts and p-values.
The generated inference run computes inference before invoking this suite.

See [validation implementations](../validation/README.md),
[program summaries](../doc/README.md) and the
[verification record](../doc/validation_status.md). Passing the earlier synthetic
and three-arm ANCOVA/simple comparisons does not validate untested configurations
or later source changes. The integrated three-arm ANCOVA/simple workflow
passed in the user-supplied 2026-10-15 SAS log.

## Automatic result export

The compact export macros live in `inference_pipeline.sas`. The builder calls
`%car_export_results` after validation, while the full ODS report remains open.
It writes eight core CSVs and four result plots, with additional CSVs for failed
validation or nonempty QC. `deprecated/export_results.sas` is a historical copy;
it is not loaded by the build. See
[saving results](../doc/quickstart.md#save-result-tables-and-graphics).

## Inference pipeline

[`inference_pipeline.sas`](inference_pipeline.sas) defines orchestration macros
for the complete Programs 01–07 workflow. Loading it does not execute analysis.
The builder in `run/project.py` embeds it into `run/run.sas` and inserts the
preparation and inference/validation calls around Program 03. See the
[run guide](../run/README.md) for the execution order.

## Program 03 integration

Program 03 remains unchanged and automatically calls its ALL-method driver.
The generated inference entry point fits ALL Program 02 methods before
submitting Program 03, then calls 04–06 directly with the JSON-selected model outputs (default ANCOVA).
Standalone Program 03 validation retains its
[manual workflow](../doc/quickstart.md#4-validate-program-03-aipw-point-estimates).
