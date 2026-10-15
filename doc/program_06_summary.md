# Program 06: Treatment Contrasts

`sas/06_treatment_contrasts.sas` defines `%car_contrast`. It requires SAS/IML
and uses treatment means and the complete covariance from Program 05.

Load `sas/00_car_common.sas` before this file. The file defines its macro without
running an analysis. Outputs are temporary WORK datasets by default. Check
`CAR_RC` before proceeding: 0 means success and 1 means failure. A failed call
clears its specified public outputs after output names have been validated;
unsafe names cause failure without deleting datasets. Internal `_CAR_*` tables
may remain for diagnosis.

The coefficient dataset contains `CONTRAST_ID`, `LABEL`, `ARM_INDEX`,
`COEFFICIENT`, and `NULL_VALUE`. Specify every arm once per contrast, including
zero coefficients. For arm 1 minus arm 0, use coefficients -1 and 1 in the
corresponding arm-map order. Labels and null values must be consistent within
a contrast.

```text
contrast estimate = C theta
contrast covariance = C V C'
z = (estimate - null_value) / SE
```

The full covariance, including off-diagonal elements, is retained. The macro
checks complete matrix keys, symmetry, missing values, positive semidefiniteness
and coefficient validity. `alpha=0.05` gives 95% marginal normal intervals;
p-values are two-sided normal tests. These intervals do not provide simultaneous
coverage. Nonlinear contrasts are outside this implementation.

| Default WORK output | Contents |
|---|---|
| CAR_CONTRAST_RESULTS | Labels, estimates, SEs, limits, z statistics, p-values and status |
| CAR_CONTRAST_VCOV | Complete contrast-by-contrast covariance |

A zero SE is reported as `ZERO_SE`; its z statistic and p-value are missing.
Negative variance or invalid covariance causes failure rather than adjustment.

## Validation

`validation/smoke_04_07.sas` tests contrasts, off-diagonal covariance,
malformed matrices, coefficients and zero SE. The full reference suite compares
against `robincar_contrast(..., contrast_h="diff")`, using explicit arm order
and the same confidence level. See
[the verification record](validation_status.md) for completed checks
and [validation instructions](../validation/README.md) for entry points.
