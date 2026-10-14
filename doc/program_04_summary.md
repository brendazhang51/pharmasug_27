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

Provide one complete analysis population, an explicit arm map, and one
`USUBJID`–`ARM_INDEX` prediction per participant and arm. The prediction value
is `MU_TILDE`, not the working model's raw prediction. The arm map contains
`ARM_INDEX`, `TRT`, `N_ARM`, and empirical `PI_HAT`.

`joint=YES` adds joint-stratum indicators; `joint=NO` performs linear
calibration without these indicators. `add_x=` optionally adds numeric
covariates. Each arm's model includes an intercept and all prediction columns.
SVD supports collinear predictors; `rank_tol=1e-10` controls rank and prediction
estimability checks. Empty effective rank, missing matrix results, or
predictions outside an arm's estimable design space cause failure.

| Default WORK output | Contents |
|---|---|
| CAR_CAL_PREDICTIONS | Participant-by-arm raw and re-centered calibrated predictions |
| CAR_CAL_ESTIMATES | Calibrated treatment means and arm sample sizes |
| CAR_CAL_DIAGNOSTICS | Effective rank, alias count, fit and estimability diagnostics |

For each arm, re-centering adds the observed-arm mean residual to every
participant's raw prediction. The treatment mean is the population average
of these re-centered predictions. Program 04 does not estimate covariance;
pass its outputs to Program 05 using the same arm map.

## Validation

`validation/smoke_04_07.sas` covers linear/joint calibration, collinear
predictions and non-estimable predictions. The RobinCar reference calls
`robincar_calibrate(..., joint=TRUE)` and compares predictions and means,
rather than requiring identical coefficients for aliased designs.

Use [the running guide](../sas/README.md) for the current example bridge;
Program 03 remains unimplemented. See
[the verification record](validation_status.md) for passed fixtures, the
validated ANCOVA/simple configuration and the pending generated-run rerun.
