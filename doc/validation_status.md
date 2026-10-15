# Verification Record

This record distinguishes observed checks from unexecuted configurations.
The Viya results below are based on user-provided logs reviewed on 2026-10-14;
they are not new SAS executions in the development container.

| Area | Evidence and scope | Status |
|---|---|---|
| Program 02 before PR #7 report integration | Original 500-row, three-arm CSV; ANOVA/ANCOVA/ANHECOVA; base-R fitted values, residuals and diagnostics; invalid-input tests | Passed in Viya |
| Programs 04–07 smoke tests before layout refactor | Analytic two/three-arm fixtures, simple/PB, calibration, mapping, invalid inputs, overflow, stale-output clearing, reference rejection | `CAR_TEST_FAILURES=0` in Viya |
| Full RobinCar comparison before layout refactor | 500 subjects; arms 0,1,2; ANCOVA; simple; type 1; joint calibration; alpha .05; raw/centered predictions, means, covariance, SE, CI, contrasts and p-values | `CAR_SUITE_RC=0`; 38 summary rows and 8,085 numeric comparison rows; no ERROR/WARNING in supplied log |
| R exporter | RobinCar 1.2.0, three working models, two designs, two/three arms, reversed order and changed alpha | 15 scenarios passed locally before layout refactor |
| PR #7 report integration | Preserved local assertion/import error checks and added remote comparison tables/previews | Static checks only; Viya rerun pending |
| Local checks after layout refactor | 7 entry/config tests, R syntax/helper checks, 15 RobinCar exporter scenarios, unchanged base-R numeric CSVs, source hashes and Markdown links | Passed locally |
| Generated SAS run files after layout refactor | Same statistical sources, embedded configuration and dependencies | Viya rerun pending |
| Full data-based two-arm or PB SAS/R comparison | Regenerated references and corresponding SAS run required | Pending |
| Program 03 AIPW point estimates | User confirmed successful testing on 2026-10-14; no new SAS execution in the development container | Passed (user-confirmed) |
| Experimental binomial/MI example | No numerical equivalence established | Pending |

Passing one configuration does not validate every model, randomization design,
arm ordering or data source. The package version is pinned to 1.2.0; any installed
RemoteSha is recorded, but a CRAN binary need not have a GitHub SHA.

The locally preserved references live in `output/outcome_models/` and
`output/inference/`. Moving them and the source CSV does not change their content
or the input hash. Build manifests are generated under `output/build/`.

Successful supplied logs are archived locally under
`output/verification/2026-10-14/`; generated files and logs are ignored by Git.
