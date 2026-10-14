# Shared Utilities

`utilities.SAS` configures the SAS server CSV path. Edit the `csv_path`
argument and run this file before Program 01 in the same SAS session.

`reference_helpers.R` provides finite-value checks, confidence-level validation
and CSV export with 17 significant digits. Both R reference generators in
`validation/` load it relative to their script location.

Keep executable reference generators and tests in `validation/`. Test these
helpers without installing RobinCar:

```sh
Rscript validation/test_reference_export.R --helpers-only
```
