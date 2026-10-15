# Program 04: Joint Calibration

`sas/04_joint_calibration.sas` defines `%car_calibrate`, which fits an
arm-specific linear model using all arms' re-centered predictions, then
re-centers the calibrated predictions and estimates treatment means.

Load `sas/00_car_common.sas` before this file. The file defines its macro without
running an analysis. Outputs are temporary WORK datasets by default. Check
`CAR_RC` before proceeding: 0 means success and 1 means failure. A failed call
clears its specified public outputs after output names have been validated;
unsafe names cause failure without deleting datasets. Internal `_CAR_*` tables
may remain for diagnosis.

Provide the analysis population and native Program 03 predictions and means,
selecting `model=ANCOVA` by default. The macro checks source summaries and
re-centers raw `PREDICTED` internally using `MEAN_RESIDUAL_ARM`. No arm map or
converted prediction table is needed.

`joint=YES` adds joint-stratum indicators; `joint=NO` performs linear
calibration without these indicators. `add_x=` optionally adds numeric
covariates. Each arm's model includes an intercept and all prediction columns.
SVD supports collinear predictors; `rank_tol=1e-10` controls rank and prediction
estimability checks. Empty effective rank, missing matrix results, or
predictions outside an arm's estimable design space cause failure.

| Default WORK output | Contents |
|---|---|
| CAR_CAL_PREDICTIONS | Native Program 03 prediction schema with raw calibrated PREDICTED |
| CAR_CAL_MEANS | Native Program 03 mean schema including calibrated AIPW_MEAN |
| CAR_CAL_DIAGNOSTICS | Effective rank, alias count, fit and estimability diagnostics |

For each arm, re-centering adds the observed-arm mean residual to every
participant's raw prediction. The treatment mean is the population average
of these re-centered predictions. Program 04 does not estimate covariance;
pass its outputs directly as `predictions=` and `means=` to Program 05.

## Validation

`validation/test_inference_smoke.sas` covers linear/joint calibration, collinear
predictions and non-estimable predictions. The RobinCar reference calls
`robincar_calibrate(..., joint=TRUE)` and compares predictions and means,
rather than requiring identical coefficients for aliased designs.

See [the native contracts](data_contracts.md) for input fields and calls.
See [the running guide](../sas/README.md) and
[the verification record](validation_status.md) for complete submissions,
the successful integrated ANCOVA/simple run and remaining untested settings.
