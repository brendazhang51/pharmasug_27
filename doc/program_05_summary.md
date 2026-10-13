# Program 05: CAR Variance Estimation

`sas/05_variance_estimation.sas` defines `%car_variance` for original or
calibrated AIPW treatment means. It requires SAS/IML and supports only
`variance_type=1`, with explicit `car_scheme=simple` or `permuted-block`.

Load `sas/car_common.sas` before this file. The file defines its macro without
running an analysis. Outputs are temporary WORK datasets by default. Check
`CAR_RC` before proceeding: 0 means success and 1 means failure. A failed call
clears its specified public outputs after output names have been validated;
unsafe names cause failure without deleting datasets. Internal `_CAR_*` tables
may remain for diagnosis.

Inputs are the analysis population, re-centered predictions (`MU_TILDE`),
treatment estimates and the arm map. Every arm needs at least two rows.
Predictions must be re-centered within observed arms, and estimates must
agree with population prediction means. Permuted-block calculations require
every arm-by-stratum cell to be populated. The design is supplied by the
caller; it is not inferred from observed counts.

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

`validation/smoke_04_07.sas` includes analytic covariance fixtures, unequal
allocation, reordered inputs, centering errors and empty permuted-block cells.
`validation/test_inference.sas` compares complete original and calibrated
covariance and inference against RobinCar 1.2.0. See
[validation instructions](../validation/README.md). SAS runtime validation
remains pending.
