# Supported Features and Limits

The macro APIs, generated workflow and numerical validation have different
scopes. A macro option being implemented does not mean it is selectable in
JSON or has been checked against RobinCar in SAS.

| Feature | SAS implementation | Generated workflow / validation |
|---|---|---|
| Continuous ANOVA, ANCOVA, ANHECOVA | Programs 02/03 fit and score all three | All three fit; downstream inference and reference CLI use `analysis_model` (default ANCOVA) |
| Original and calibrated mean inference | Programs 04–06 accept `model=` and native 03/04 tables | Integrated ANCOVA/simple run passed in the 2026-10-15 supplied log |
| Treatment arms | Model/matrix macros operate on numeric arm labels | Program 01 accepts source arms 0/1/2 and subsets; this is not a general arbitrary-K importer |
| Simple randomization | Type-1 variance implemented | Three-arm data-based SAS/R comparison passed |
| Stratified permuted blocks | Type-1 variance implemented; every arm-by-stratum cell must be populated | Synthetic SAS and R exporter checks passed; full data-based SAS/R comparison pending |
| Two-arm subset | Supported by model/matrix macros and workflow configuration | Synthetic checks passed; full data-based SAS/R inference comparison pending |
| Calibration | `joint=YES/NO`, numeric `add_x=`, SVD rank/estimability checks | Pipeline/reference suite fixed to joint YES, no extra covariates |
| Contrasts | Program 06 supports user-supplied linear coefficient tables and null values | Pipeline makes each arm minus the lowest numeric arm; no JSON control-arm/custom-contrast setting |
| Inference level | Configurable alpha, marginal normal intervals and two-sided z tests | Default .05; no simultaneous intervals or multiplicity adjustment |
| Numerical validation | Program 07 generic keyed numeric comparisons | Suite pinned to RobinCar 1.2.0, joint YES/no extra covariates; CLI reference uses the selected model |
| Export | Eight final/context CSVs, full HTML, procedure graphics and four result plots | Successful supplied SAS log; failure details/QC CSVs conditional |
| Binary outcome / MI | Independent five-arm logistic/MI example only | Not part of the main build; no numerical equivalence established |

## Data and fitting restrictions

- Program 01 is an example-specific adapter: source names are fixed, including
  `A`, `y`, `x1`, `x3`, `z1`, `z2`, `strata_cross`, `y0`, `y1`, `y2`.
  It validates all source rows before arm selection. Missing values in an
  excluded arm can therefore stop the run. Missing analysis values are rejected;
  the main workflow does not impute or automatically drop incomplete rows.
- IDs are generated from source row order. Keep local and server CSV content
  and ordering identical when generating references. Arbitrary ID, treatment,
  outcome and covariate mappings are not configurable in JSON.
- Working models use fixed `X1_ANALYSIS` and `X3_ANALYSIS` covariates; randomization
  strata enter joint calibration and design variance, not the initial regression.
  Adding more model covariates or changing formulas requires source changes.
- At least two observations per arm are necessary, but not sufficient. Program
  02 also requires full identifiable rank and positive residual degrees of
  freedom. The automatic Program 03 driver requests ALL models, so an ANHECOVA
  failure stops the pipeline even when ANCOVA alone would fit.
- Program 04 can accommodate collinear calibration predictors through SVD, but
  rejects no residual degrees of freedom and non-estimable predictions. This
  does not relax Program 02's original working-model rank checks.
- The JSON loader accepts ascending integer arm lists; the current importer
  still limits source labels to 0/1/2. Unsupported labels can pass JSON syntax
  checks and subsequently fail SAS data QC. Lower-level macros have a wider
  numeric-label interface than the generated data adapter.

## Not implemented in the main workflow

- Logistic/binomial, Poisson/count, survival/time-to-event, longitudinal/MMRM,
  mixed-effect and machine-learning outcome model interfaces.
- Missing-outcome analysis, MI generation/pooling, observational propensity-score
  estimation, cross-fitting or clustered/repeated-observation inference.
- Randomization schemes other than simple or stratified permuted blocks;
  variance types other than 1.
- Risk ratios, odds ratios and other nonlinear contrasts; joint/global tests,
  multiplicity corrections, t/finite-sample or bootstrap inference.
- Arbitrary JSON formula selection, user-selected reference arm, arbitrary contrast
  matrices, `joint=NO`, extra calibration covariates or export profiles.
- Automatic server upload/submission/download, remote directory creation,
  automatic SAS log capture, PDF/Excel export or versioned output directories.
  Commands build local artifacts and references; SAS code executes separately in the server session.

## Remaining engineering improvements

1. Model selection is now connected consistently in JSON, pipeline and R
   reference generation. Extend contrast/calibration options separately and
   verify newly selectable models in SAS before widening validation claims.
2. Add full SAS/R data-based runs for two-arm and permuted-block settings and
   manual ANOVA/ANHECOVA inference; establish binary/MI references separately.
3. Execute the new Program 01 failure-protection regression script in SAS:
   import-status guards, reserved-output cleanup, schema types and empty-input
   rejection are implemented, but require runtime confirmation there.
4. Verify early QC export and report closure under both writable and unwritable
   destinations. These failure handlers are implemented; CSV preservation is
   best effort and old exported files remain on disk.
5. Improve report/export status reporting: a directory-open check confirms
   accessibility, not writability; plotting/export messages do not replace
   ODS error inspection or the independent `CAR_SUITE_RC` verification result.
6. Preserve source/configuration manifests and SAS logs beside exported results
   when archiving a run. WORK matrices and predictions remain available for
   optional export; the compact bundle does not include all intermediate data.

See [verification evidence](validation_status.md) and
[the run guide](../run/README.md). Historical files under `sas/deprecated/` and
exploratory notebooks are not build dependencies.
