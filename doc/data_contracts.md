# Native Program 03 Data Contracts

Programs 04–06 consume Program 03's tables directly. Program 03 is unchanged,
including its automatic ALL-method driver. There is no separate conversion
step or public arm-map table. Each downstream call selects `model=ANCOVA` by
default; stacked ANOVA/ANCOVA/ANHECOVA source tables can be supplied unchanged.

## Predictions and means

| Table | Required fields |
|---|---|
| Predictions | Character `MODEL USUBJID`; numeric `OBSERVED_TRT TARGET_TRT AVAL PREDICTED OBSERVED_RESIDUAL` |
| Means | Character `MODEL`; numeric `TARGET_TRT N_TOTAL N_ARM OBSERVED_MEAN MEAN_PRED_ALL MEAN_PRED_ARM MEAN_RESIDUAL_ARM AIPW_MEAN` |

For the selected model, predictions contain one row per subject and target
treatment; means contain one row per target treatment. `OBSERVED_RESIDUAL`
equals `AVAL-PREDICTED` on observed-target rows and is missing on other rows,
as in Program 03. This intentional missingness is accepted.

`PREDICTED` is the raw prediction. The shared input validator checks the whole
analysis population, treatment counts, residuals and every mean summary, then
uses `PREDICTED + MEAN_RESIDUAL_ARM` internally for calibration and variance.
`AIPW_MEAN` must equal `MEAN_PRED_ALL + MEAN_RESIDUAL_ARM`. Source tables are
read without alteration. At least two subjects per treatment are required.

Program 04 publishes `WORK.CAR_CAL_PREDICTIONS` and `WORK.CAR_CAL_MEANS` with
these same fields. The calibrated `PREDICTED` remains raw; its residual shift
is stored in `MEAN_RESIDUAL_ARM`. Pass these tables straight to Program 05.
Effective rank and estimability diagnostics are keyed by `MODEL TARGET_TRT`.

## Covariance and contrasts

Program 05 covariance uses `MODEL TARGET_TRT_I TARGET_TRT_J COVARIANCE` and
contains every ordered treatment pair. Its inference output uses
`MODEL TARGET_TRT N_ARM AIPW_MEAN SE ALPHA LCL UCL Z P_VALUE STATUS`.
Components use the same treatment-pair keys; residual summaries use
`MODEL STRATA TARGET_TRT`. Treatment labels remain actual labels throughout;
consecutive matrix indices are private implementation details.

Program 06 accepts native `means=`, `model=`, the Program 05 covariance and
coefficients with `CONTRAST_ID LABEL TARGET_TRT COEFFICIENT NULL_VALUE`.
Include every target treatment for each contrast, including zero coefficients.
Contrast outputs retain their contrast keys and include the selected `MODEL`.

## Calls after Program 03

Load `sas/00_car_common.sas` and Programs 04–07, then use:

```sas
/* Default inputs: WORK.AIPW_PREDICTIONS and WORK.AIPW_MEANS. */
%car_variance(model=ANCOVA, car_scheme=simple, alpha=0.05);
/* Check CAR_RC=0 before proceeding. */
%car_calibrate(model=ANCOVA);
/* Check CAR_RC=0 before proceeding. */
%car_variance(
    predictions=work.car_cal_predictions,
    means=work.car_cal_means,
    model=ANCOVA,
    car_scheme=simple,
    out_vcov=work.car_cal_vcov,
    out_inference=work.car_cal_inference,
    out_components=work.car_cal_components,
    out_residuals=work.car_cal_stratum_residuals
);
/* Check CAR_RC=0 before proceeding. */
```

Use the documented randomization design and confidence level for your analysis.
The complete example also constructs coefficients and runs original/calibrated
contrasts. Generate it with `python run/project.py build inference`, then submit
all of `run/run.sas`. Program 02 fits ALL methods before the unchanged Program
03 driver runs; downstream inference and the reference select the JSON
`analysis_model` (ANOVA, ANCOVA or ANHECOVA; default ANCOVA),
type 1, joint calibration and no extra calibration covariates.

This replaces the old public `arm_map=`, `estimates=`, `out_estimates=` and
`MU_TILDE` input interfaces. Use `means=`, `model=` and `out_means=` instead;
update custom coefficients and covariance keys to the actual treatment labels.
There are no compatibility aliases. Program 07 remains a generic keyed
numeric comparator and can compare native fields directly.

The existing 17 RobinCar reference CSV schemas remain unchanged. The validation
suite projects native SAS fields to private comparison tables at the reference
boundary, using the declared treatment order. No converted tables are passed
between analysis stages. Existing references remain usable when their input
hash, population, model, design, order, variance and alpha match.

After safe output-name checks, 04–06 clear old/partial public results on
failure. Invalid output names never trigger deletion. Check `CAR_RC`
immediately after every call. See [the quick start](quickstart.md) and
[the verification record](validation_status.md) for execution and current status.
