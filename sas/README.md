# Analysis Programs and Macros

Use [the quick start](../doc/quickstart.md) and generated files in `run/` for
complete submissions. `sas/` is the implementation layer. Program 01 runs its
data preparation on submission; Program 03 automatically calls `%car_aipw()`
on submission after Program 02 has been fitted. Program 02 and 04–07 define macros without
automatically running analyses. Load `00_car_common.sas` before calling 04–07.

Programs 04–06 require SAS/IML. Program 02 and the continuous example require
SAS/STAT. Configuration comes from `utilities/config.local.json` through the
entry-point builder; `%car_config` is available for manual SAS workflows.

## Input contracts

Each macro call handles **one population, one model, one estimator**. Filter
stacked inputs before calling; join/store outputs with your analysis identifiers
afterwards. Variable names use standard SAS V7 identifiers.

| Input | Required fields |
|---|---|
| Analysis | Character `usubjid strata`; numeric `trt aval`; complete unique subjects |
| Arm map | Numeric `arm_index trt n_arm pi_hat`; indices 1…K, unique treatments, n_arm≥2, pi_hat=n_arm/n |
| Predictions | Character `usubjid`; numeric `arm_index mu_tilde`; exactly n×K unique pairs |
| Mean estimates | Numeric `arm_index estimate`; exactly one row per arm, matching mean(mu_tilde) |
| Mean covariance | Numeric `arm_i arm_j covariance`; every ordered pair in 1…K |
| Contrast coefficients | Character `contrast_id label`; numeric `arm_index coefficient null_value`; every arm per contrast, including zero coefficients |

`strata` must encode the complete joint randomization strata. `add_x` is a
space-separated list of additional **numeric** calibration covariates.
Missing analysis values are rejected. Prediction centering is
`mu_tilde=mu_raw+mean(Y-mu_raw | observed arm=prediction arm)`.

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

`validation/inference_suite.sas` defines `%car_test_inference` and its typed
CSV imports. It checks settings/population identity, raw and centered predictions,
original/calibrated means, complete covariance, SEs, CIs, contrasts and p-values.
The generated inference run computes the example before invoking this suite.

See [validation implementations](../validation/README.md),
[program summaries](../doc/README.md) and the
[verification record](../doc/validation_status.md). Passing the earlier synthetic
and three-arm ANCOVA/simple comparisons does not validate untested configurations
or the newly assembled entry points before their Viya rerun.

Program 03 has a [manual setup and validation workflow](../doc/quickstart.md#4-validate-program-03-aipw-point-estimates),
using `%car_fit()` followed by `03_aipw_estimation.sas`. It requires SAS/STAT
and is not yet included in generated entry points. Its output tables differ
from the 04–07 input contracts above; the continuous example still constructs
its own bridge. See [Program 03](../doc/program_03_summary.md) for details.
