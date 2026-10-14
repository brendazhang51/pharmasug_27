# Programs 04–07

These are initial implementations, with SAS execution and numerical equivalence
to RobinCar still pending. Programs 04–06 require SAS/IML; the bridge example
also requires SAS/STAT. Program 07 uses DATA steps and PROC SQL.

## Load and run in Viya

Run the full files in this order in the **same SAS session**:

1. `car_common.sas`
2. `04_joint_calibration.sas`
3. `05_variance_estimation.sas`
4. `06_treatment_contrasts.sas`
5. `07_validation.sas`

These files define macros; loading them does not run an analysis. In VS Code,
open and submit each file. Alternatively upload them to an accessible SAS
server directory and use `%include` with that server's paths.
No Codespaces or local-machine path is assumed to exist on Viya.

To check the implementation, first load `validation/test_inference.sas` (it defines
macros without running them), then submit `validation/smoke_04_07.sas`.
It uses synthetic data with analytic reference values, plus deliberate invalid
inputs. Require `CAR_TEST_FAILURES=0`; expected errors are labelled by the tests.
This fixture does not establish RobinCar equivalence.

For the project CSV, run `utilities/utilities.SAS`, then `01_data_preparation.sas`, then
load `examples/continuous_04_07.sas` and invoke:

```sas
/* Use the actual, documented randomization design. */
%car_worked_example(car_scheme=simple);
```

The example constructs an ANCOVA fit and AIPW tables to bridge the currently
missing general-purpose 03 macro. Program 02 is now available; this bridge
still fits its own ANCOVA for a self-contained test, without modifying 02. `simple` is an explicit demonstration
setting unless independently verified for the dataset. To compare two arms,
set `analysis_arms=0 1` in 01 and use the same subset in R; never just discard
rows from a prediction matrix fitted on a different analysis population.

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

## R reference and validation

With RobinCar **1.2.0** installed, generate independently fitted reference
tables, explicitly selecting the same analysis model/design/arm order:

```bash
Rscript validation/robincar_reference.R robincar_example_data.csv /tmp/car_reference ANCOVA simple 0,1
```

The optional final argument is alpha (default `0.05`), e.g. append `0.10`
for 90% intervals. Both stages' means and contrasts use the selected alpha.
The script uses `sprintf("%.17g", ...)`, rejects nonfinite values, and exports
`analysis.csv` and `settings.csv` alongside the numeric results.

The script pins the package version, records any installed RemoteSha,
session information and CSV hash. For a GitHub installation, pin a reviewed
commit before installing; source links on `main` can change.
The bridge example's calibration uses `add_x` empty, matching this reference.

Upload **all** generated CSVs to one accessible Viya server directory. After
running the continuous example successfully, load `validation/test_inference.sas`
and invoke:

```sas
%car_test_inference(
    reference_dir = YOUR_SERVER_REFERENCE_DIRECTORY,
    out_summary   = work.car_validation_suite,
    out_details   = work.car_validation_details
);
proc print data=work.car_validation_suite; run;
```

The suite uses explicit CSV schemas (`usubjid $12`, contrast IDs `$12`, strata
`$40`) and rejects oversized prediction/population keys instead of truncating
silently. It checks saved run settings (`WORK.CAR_RUN_SETTINGS`), package
version, full population values, joint strata and arm mapping before comparing
all raw/centered predictions, original/calibrated means, covariance, SE, CI,
contrasts and contrast covariance. For manual macro workflows, supply the same
settings schema and the dataset parameters listed in the suite's signature.
The suite currently validates joint calibration with empty `add_x`, matching
the exporter. Custom source-data/model matching remains the caller's responsibility
when populating run settings; the bridge generates its settings automatically.

`CAR_SUITE_RC` and final `CAR_RC` are 0 only when **all** checks pass, 1 on
failure, and 2 when no reference directory/settings file is available. Missing
individual files in an otherwise configured suite are failures. Per-check
summaries and normalized row-level differences are retained across comparisons;
a later successful comparison cannot erase an earlier failure.

07 remains independently callable. The rule is
`abs(SAS−R) <= atol + rtol*abs(R)`; both missing values fail.
Default mixed tolerance is `atol=1e-8, rtol=1e-6`.
Duplicate/missing keys, empty comparisons and key-set mismatches fail.
`compare=YES` adds a PROC COMPARE report, but mixed-tolerance results are
authoritative. A missing reference dataset gives `NOT_RUN`, never `PASS`.
Input errors replace earlier reports with fresh failure reports.

Local base-R checks:

```bash
Rscript validation/test_reference_export.R --helpers-only
Rscript validation/reference_outcome_models.R robincar_example_data.csv /tmp/outcome_reference
```

The first command checks precision roundtrip, alpha parsing and rejected
nonfinite/empty exports. With RobinCar 1.2.0 installed, also run
`Rscript validation/test_reference_export.R` for the real exporter across all
three working models, both designs, two/three arms, reversed order and custom alpha. The second checks the merged PR's independent working
models; it does not establish 04–07 numerical equivalence. The full exporter
requires RobinCar 1.2.0; the SAS suite requires execution on Viya with SAS/IML.
Do not mark SAS runtime or RobinCar equivalence validated until those checks pass.

See the program summaries in [doc/](../doc/) for methods and output contracts.
