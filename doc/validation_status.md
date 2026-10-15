# Verification Record

This record distinguishes observed checks from unexecuted configurations.
The SAS execution results below are based on user-provided logs reviewed on 2026-10-14
and 2026-10-15;
they are not new SAS executions in the development container.

| Area | Evidence and scope | Status |
|---|---|---|
| Program 02 before PR #7 report integration | Original 500-row, three-arm CSV; ANOVA/ANCOVA/ANHECOVA; base-R fitted values, residuals and diagnostics; invalid-input tests | Passed in SAS |
| Programs 04–07 smoke tests before layout refactor | Analytic two/three-arm fixtures, simple/PB, calibration, mapping, invalid inputs, overflow, stale-output clearing, reference rejection | `CAR_TEST_FAILURES=0` in SAS |
| Full RobinCar comparison before layout refactor | 500 subjects; arms 0,1,2; ANCOVA; simple; type 1; joint calibration; alpha .05; raw/centered predictions, means, covariance, SE, CI, contrasts and p-values | `CAR_SUITE_RC=0`; 38 summary rows and 8,085 numeric comparison rows; no ERROR/WARNING in supplied log |
| R exporter | RobinCar 1.2.0, three working models, two designs, two/three arms, reversed order and changed alpha | 15 scenarios passed locally before layout refactor |
| PR #7 report integration | Preserved local assertion/import error checks and added remote comparison tables/previews | Static checks only; SAS rerun pending |
| Local checks after layout refactor | 7 entry/config tests, R syntax/helper checks, 15 RobinCar exporter scenarios, unchanged base-R numeric CSVs, source hashes and Markdown links | Passed locally |
| Generated inference run after layout refactor | 500 participants, three arms, ANCOVA/simple, native 03 inputs, reference suite and compact export | Passed in supplied 2026-10-15 SAS log; outcome-model-only report rerun remains separate |
| Full data-based two-arm or PB SAS/R comparison | Regenerated references and corresponding SAS run required | Pending |
| Program 03 AIPW point estimates | User confirmed successful testing on 2026-10-14; no new SAS execution in the development container | Passed (user-confirmed) |
| Native Program 03 interfaces and single run entry (2026-10-15) | Program 03 unchanged; 04/05 accept native predictions/means, 06 uses native means and treatment keys; updated smoke fixtures and reference-boundary checks | Integrated ANCOVA/simple path passed in supplied 2026-10-15 log; revised standalone smoke rerun remains pending |
| Local checks for native interfaces | 10 entry/configuration/interface tests; exact Program 03 source preservation; precision roundtrip; 15 RobinCar exporter scenarios with independent base-R prediction/mean agreement | Passed locally; these checks do not execute SAS |
| Inference orchestration relocation (2026-10-15) | Moved to `sas/inference_pipeline.sas`; renamed orchestration macros; 10 build/configuration/interface tests passed; generated inference bundle; verified SAS implementation preserved apart from macro names and diagnostic wording | Integrated pipeline passed in supplied 2026-10-15 log |
| Automatic compact export (2026-10-15) | 13 local configuration/build/interface checks, including invocation order and eight-table default export; inference bundle regenerated | Passed in supplied 2026-10-15 SAS log: 8 CSVs, 4 result plots and finalized full HTML report |
| Integrated inference evidence (2026-10-15) | Supplied log: CAR_FIT_RC=0, CAR_AIPW_RC=0, EXAMPLE_RC=0, CAR_SUITE_RC=0; 38 suite checks; no ERROR/WARNING log lines; 500 participants, arms 0/1/2, ANCOVA/simple/type 1/joint YES/alpha .05 | Passed for this configuration |
| Export-source consolidation after repository audit | Export macros moved unchanged from historical source into active inference pipeline; standalone deprecated copy excluded from builds | 14 Python tests, R syntax/helpers, 15 RobinCar integration scenarios and independent base-R exports passed; Markdown links valid; inference bundle regenerated; no new SAS execution claimed |
| Data preparation failure protection | 15 local Python checks; immediate import status, stale-output invalidation, schema/empty-input guards, QC export and guarded report closure; new standalone SAS failure fixtures | Local checks passed; SAS runtime failure scenarios and normal rerun pending |
| Configurable inference model | JSON analysis_model selects ANOVA/ANCOVA/ANHECOVA consistently across SAS stages, settings, plot labels and R reference invocation; older configs default to ANCOVA | 18 Python checks passed; real Python reference CLI produced 17 CSVs and matching model metadata for each of the three models; Markdown links valid; new selected-model SAS runs pending |
| Descriptive validation filenames | Renamed SAS smoke/reference tests and R inference exporter; updated builder, R tests and documentation references; 18 Python checks, R syntax/helpers and one real renamed reference export passed | Local checks passed; statistical logic unchanged |
| Experimental binomial/MI example | No numerical equivalence established | Pending |

Passing one configuration does not validate every model, randomization design,
arm ordering or data source. The package version is pinned to 1.2.0; any installed
RemoteSha is recorded, but a CRAN binary need not have a GitHub SHA.

The locally preserved references live in `output/outcome_models/` and
`output/inference/`. Moving them and the source CSV does not change their content
or the input hash. Build manifests are generated under `output/build/`.

Successful supplied logs are archived locally under
`output/verification/2026-10-14/` and `output/verification/2026-10-15/`;
the latter contains `inference_success.log` and its SHA256 summary. Generated
files and logs are ignored by Git. The supplied log predates the subsequent
source-only consolidation of export macros into `inference_pipeline.sas`.

The selected-model reference CLI check used temporary output directories and
preserved the existing local reference files. RobinCar emitted its warning
that specified strata are ignored for the simple-randomization design
adjustment; each reference command completed. This is separate from joint
calibration, which still uses strata.
