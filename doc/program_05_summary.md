# Program 05: CAR Variance Estimation

`sas/05_variance_estimation.sas` defines `%car_variance` for original or
calibrated AIPW treatment means. It requires SAS/IML and supports only
`variance_type=1`, with explicit `car_scheme=simple` or `permuted-block`.

Load `sas/00_car_common.sas` before this file. The file defines its macro without
running an analysis. Outputs are temporary WORK datasets by default. Check
`CAR_RC` before proceeding: 0 means success and 1 means failure. A failed call
clears its specified public outputs after output names have been validated;
unsafe names cause failure without deleting datasets. Internal `_CAR_*` tables
may remain for diagnosis.

Inputs are the analysis population and Program 03's predictions and means,
with `model=ANCOVA` by default. Supply `means=`; no `arm_map=` is needed.
The macro validates all source summaries, then re-centers raw `PREDICTED`
internally using `MEAN_RESIDUAL_ARM`. Every arm needs at least two rows.
Program 04's calibrated tables use the same schema and can be supplied directly.
Permuted-block calculations require every arm-by-stratum cell to be populated.
The caller supplies the design; it is not inferred from observed counts.

Covariance keys are `MODEL TARGET_TRT_I TARGET_TRT_J`; mean inference uses
`MODEL TARGET_TRT AIPW_MEAN` with SE/CI/test fields. See
[the data contracts](data_contracts.md) for the complete schemas.

Let Q[a,b] be Cov(Y, MU_TILDE_b | A=a), Sigma the population prediction
sample covariance, and pi the empirical allocation proportions. The engine
uses sample covariance denominators n_a-1 and n-1:

```text
V_SR = diag((var(Y | A=a) - 2 Q[a,a] + Sigma[a,a]) / pi[a])
       + Q + Q' - Sigma
Cov(theta) = (V_SR - V_Omega) / n
```

For simple randomization, V_Omega is zero. For permuted blocks, it is the
stratum-weighted sum of R_s (diag(pi) - pi pi') R_s, where R_s has diagonal
entries equal to arm-by-stratum mean residuals divided by pi. This is the
RobinCar type-1 correction with Omega_s=0.

| Default WORK output | Contents |
|---|---|
| CAR_MEAN_VCOV | Complete arm-by-arm treatment-mean covariance |
| CAR_MEAN_INFERENCE | Means, SEs and normal confidence limits |
| CAR_VARIANCE_COMPONENTS | Unscaled variance components, minimum eigenvalue and check tolerance |
| CAR_STRATUM_RESIDUALS | Arm-by-stratum residual summaries |

`alpha=0.05` gives 95% marginal intervals. Missing intermediate values,
negative variances and materially non-positive-semidefinite matrices fail;
variances are not clipped or replaced with another estimator.

## Validation

`validation/test_inference_smoke.sas` includes analytic covariance fixtures, unequal
allocation, reordered inputs, centering errors and empty permuted-block cells.
`validation/test_inference_reference.sas` compares complete original and calibrated
covariance and inference against RobinCar 1.2.0. See
[validation instructions](../validation/README.md) and
[the verification record](validation_status.md) for completed checks and
pending configurations.
