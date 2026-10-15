# Examples

This directory contains independent experimental examples. These files are not
included in the main `inference` workflow.

The continuous-outcome Programs 01–07 pipeline lives in
[`sas/inference_pipeline.sas`](../sas/inference_pipeline.sas). Build it with
`python run/project.py build inference`, then submit the generated `run/run.sas`.
See [the run guide](../run/README.md) for the execution order.

## Experimental five-arm binomial example with multiple imputation

`binomial_gcomp_mi.sas` preserves the author-supplied SAS/IML example for a
binomial-logit working model, re-centered treatment means, permuted-block
variance correction, active-minus-placebo risk differences, and separate
Rubin-rule pooling of each mean and contrast using PROC MIANALYZE.

This is an experimental extension beyond the main continuous-outcome workflow
(the current default example has three arms). It does not implement joint calibration. Its comments
describe intended RobinCar correspondence, not verified numerical equivalence.

### Run

1. Use a SAS environment with SAS/IML and SAS/STAT (PROC MIANALYZE).
2. Load your completed, multiply imputed data into `WORK.COMPLETE` in the same
   SAS session. The program header contains an example library assignment;
   paths must be accessible to the SAS server.
3. Check the configuration block, especially `nimpute`, arm labels, stratum
   labels, response, and baseline. Imputations must be numbered 1 through
   `nimpute`. Five arms and four strata are fixed by the explicit mappings,
   coefficient labels, and contrast definitions; changing only `k` or `nstrata`
   does not generalize this example.
4. Submit `binomial_gcomp_mi.sas` and inspect the SAS log before using outputs.

### Input contract

One row per participant per imputation, with these variables:

| Variable | Requirement |
|---|---|
| `_IMPUTATION_` | Integer from 1 through `nimpute` (default 10) |
| `ARMCD` | Character: CP, C10K, C13K, C16K, C20K |
| `STRATUM` | Character: F <40, F >=40, M <40, M >=40 |
| `WT5` | Numeric binary response, 0 or 1 |
| `BASE` | Numeric continuous baseline covariate |

CP is the reference arm. Factor ordering must match the R reference analysis.
No missing analysis values are allowed. Every treatment-by-stratum cell must
be populated in every imputation, with at least two observations per arm.
The model also requires a full-rank design and a finite, converged logistic fit;
separation and ill-conditioned fits need investigation in the SAS log.
`_obsid` identifies the input row within an imputation, not a stable subject ID.

### Outputs in WORK

- `fit_main`, `fit_contrast`: all imputations, identified by `_IMPUTATION_`.
- `fit_main1` through `fit_main10`, and corresponding `fit_contrast` tables:
  individual imputation estimates (suffix range follows `nimpute`).
- `fit_g_estimate<i>`, `fit_main_varcov<i>`, `fit_contrast_varcov<i>`,
  `fit_model_parameters<i>`, `fit_mu_a<i>`: diagnostics for imputation `<i>`.
- `final_gcomp_arm_means`, `final_gcomp_risk_differences`: pooled univariate
  estimates from PROC MIANALYZE. No pooled covariance matrix or joint test is
  produced. Re-running replaces these WORK tables.

### Validation status

The program has not been executed in the development workspace because SAS is
unavailable. Numerical agreement of predictions, means, covariance matrices,
and contrasts with a pinned RobinCar version remains to be established using
identical input data and settings. No clinical data or reference results are
included.
