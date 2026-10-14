# Program 07: Numerical Validation

`sas/07_validation.sas` defines `%car_validate`, a reusable comparator for
one numeric column in two keyed SAS datasets. Load `sas/car_common.sas` first.
It does not import reference CSVs or run comparisons automatically.

Supply `sas_data=`, `reference_data=`, `keys=`, and `value=`. Keys must be
complete and unique on each side, with matching sets. Missing numeric values,
including values missing on both sides, fail. Default tolerances are
`atol=1e-8` and `rtol=1e-6`:

```text
abs(SAS - reference) <= atol + rtol * abs(reference)
```

`compare=YES` adds PROC COMPARE output for inspection; the mixed-tolerance
comparison still determines the return status.

| Default WORK output | Contents |
|---|---|
| CAR_VALIDATION_RESULTS | Keyed numeric differences, tolerances and comparison status |
| CAR_VALIDATION_SUMMARY | Aggregate PASS, FAIL or NOT_RUN report |

`CAR_RC=0` means the comparison passed, 1 means failure, and 2 means no
reference result was available. Input errors refresh the failure reports so
an earlier PASS cannot be mistaken for the current result. Unsafe output
names are rejected without deleting datasets.

## Validation

`validation/test_inference.sas` defines `%car_test_inference`, which imports
reference CSVs using explicit numeric types and character lengths, checks
settings and population identity, and repeatedly invokes Program 07. It checks
model, randomization design, arm order, variance type and confidence level
before comparing predictions, means, covariance, SEs, limits, contrasts and
p-values. Review `WORK.CAR_VALIDATION_SUITE`, `WORK.CAR_VALIDATION_DETAILS`
and `CAR_SUITE_RC` (0/1/2 with the same meanings).

`validation/robincar_reference.R` generates the reference using RobinCar
1.2.0. It records the input hash, analysis population, package provenance and
session information, and writes finite numeric values with 17 significant
digits. Shared export helpers live in `utilities/reference_helpers.R`.

Run [the independent validation entry point](../validation/README.md) after
the analysis succeeds. Calculation success alone does not establish SAS/R
agreement. Local R exporter checks have passed; Viya smoke tests and full
SAS/R comparisons remain pending.
