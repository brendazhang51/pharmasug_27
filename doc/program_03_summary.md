# Program 03: AIPW Point Estimates

Run `utilities.SAS`, `01_data_preparation.sas`, `02_outcome_models.sas`, and
`03_aipw_estimation.sas` in that order in one SAS session. Program 03 uses the
PROC GLM item stores saved by Program 02. Its default driver calls
`%car_aipw(data=work.analysis_data,method=ALL)` and prints the arm means.
After loading the file, the macro can also be called for just `ANOVA`,
`ANCOVA`, or `ANHECOVA`. `CAR_AIPW_RC=0` means success; `1` means failure.

For each method and target arm, `PROC PLM` scores **every participant** after
setting `TRT` to that target arm. The original assignment is preserved as
`OBSERVED_TRT`. The estimate is

```math
\widehat\theta_a = \frac{1}{n}\sum_i\widehat m_a(X_i)
  + \frac{1}{n_a}\sum_{i:A_i=a}\{Y_i-\widehat m_a(X_i)\}.
```

This matches the equivalent expression
`observed_mean - mean_pred_arm + mean_pred_all` in the project README.
The source columns `y0`, `y1`, and `y2` are never used as outcomes for this
calculation. Strata are not included in the working models or this point
estimator. No standard errors, confidence intervals, joint calibration, or
formal treatment contrasts are calculated here.

| WORK output | Contents |
|---|---|
| `AIPW_PREDICTIONS` | `MODEL`, `USUBJID`, `OBSERVED_TRT`, `TARGET_TRT`, `AVAL`, `PREDICTED`, and `OBSERVED_RESIDUAL`; one row per subject, target arm, and model. `OBSERVED_RESIDUAL` is missing when target and observed arms differ. |
| `AIPW_MEANS` | `MODEL`, `TARGET_TRT`, `N_TOTAL`, `N_ARM`, observed and predicted means, arm residual mean, and `AIPW_MEAN`; one row per target arm and model. |

All treatment levels present in the input are scored; the original example
has 500 subjects and three arms, producing 4,500 prediction rows and nine
mean rows. The macro requires complete `USUBJID`, `TRT`, `AVAL`, `X1_ANALYSIS`,
and `X3_ANALYSIS` values, unique IDs, at least two arms, at least two subjects
per arm, and matching Program 02 fitted results and item stores. A failed
call removes the public Program 03 outputs. The model stores must have been
fitted on the same population passed to `%car_aipw`.

## Validation

The SAS test `validation/test_aipw_estimation.sas` checks population sizes,
complete predictions, the AIPW arithmetic identity, that ANOVA AIPW means
reproduce the observed arm means, and a two-arm subset. It restores the
three-arm models and outputs afterward. It also compares with independent
base-R calculations when `reference_dir` is set. Generate the R files from
the repository root:

```sh
Rscript validation/reference_aipw.R robincar_example_data.csv reference_output
```

Upload `reference_aipw_predictions.csv` and `reference_aipw_means.csv` from
that directory to a folder accessible to the SAS server. Then, in the SAS
session used for Programs 01 through 03, set the folder path and run the
validation script:

```sas
%let reference_dir=/your/server/reference_output;
/* Submit validation/test_aipw_estimation.sas in this same session. */
```

The R reference script also writes a provenance text file containing its R
version, input MD5, selected arms, and row count. The comparison tolerance
is `1e-8 + 1e-8*abs(R value)`. When R files are supplied, the SAS test prints
the nine SAS and R arm means side by side in `WORK.P03_R_MEAN_COMPARE`.
The optional R script argument `0,1` selects
two arms for separate manual analysis; the automated SAS test expects the
original 500-row, three-arm example.

R reference generation succeeded locally, but the new SAS Program 03 and its
test have not yet been executed on a SAS server. SAS/R numerical agreement
remains to be confirmed there.
