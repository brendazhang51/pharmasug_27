# Robust Covariate Adjustment under Covariate-Adaptive Randomization in SAS

## Overview

This repository contains a SAS-based implementation of covariate-adjusted treatment effect estimation for randomized clinical trials, with a focus on **augmented inverse probability weighting (AIPW)** and **joint calibration** under covariate-adaptive randomization (CAR).

The project is motivated by the methodology developed in *A General Form of Covariate Adjustment in Clinical Trials under Covariate-Adaptive Randomization* (Bannick et al., 2025) and the accompanying R package [RobinCar](https://github.com/mbannick/RobinCar).

The goal is to provide a transparent, reproducible SAS workflow for implementing these methods using standard SAS procedures, with particular attention to statistical inference, variance estimation, and practical applications in clinical trials.

**Project status:** Early development. The implementations and numerical validation described below are planned unless otherwise indicated.

## Objectives

The primary objectives of this project are to:

1. Implement AIPW estimators for treatment-specific mean outcomes and treatment effects in SAS.
2. Support commonly used linear working models, including ANOVA, ANCOVA, and ANHECOVA.
3. Implement joint calibration to improve the robustness and efficiency properties of covariate-adjusted estimators.
4. Implement appropriate asymptotic variance estimation under simple and covariate-adaptive randomization.
5. Validate SAS estimates, standard errors, and confidence intervals against the R package RobinCar.
6. Provide documented SAS programs that can be adapted to clinical trial statistical programming workflows.

## Statistical Background

### 1. Covariate-Adaptive Randomization

Covariate-adaptive randomization (CAR) aims to improve the balance of important baseline characteristics across treatment groups.

The initial implementation will consider:

- Simple randomization
- Stratified permuted block randomization

Additional randomization schemes, such as Pocock–Simon minimization, may be considered in future extensions.

### 2. Working Outcome Models

For a randomized trial with continuous outcomes, the project examines three linear working models. The current programs retain all selected treatment arms.

**ANOVA — Unadjusted model**

$$
Y_i=\beta_0+\beta_1 A_i+\epsilon_i
$$

**ANCOVA — Common-slope adjustment**

$$
Y_i=\beta_0+\beta_1 A_i+\beta_2^T X_i+\epsilon_i
$$

**ANHECOVA — Heterogeneous-slope adjustment**

$$
Y_i=\beta_0+\beta_1 A_i+\beta_2^T X_i+
\beta_3^T(A_iX_i)+\epsilon_i
$$

where:

- $Y_i$: Observed continuous outcome
- $A_i$: Treatment assignment
- $X_i$: Baseline covariates
- $\epsilon_i$: Regression error

ANHECOVA allows the relationship between baseline covariates and outcomes to differ across treatment arms.

### 3. Augmented Inverse Probability Weighting

The treatment-specific AIPW estimator considered in this project is:

```math
\begin{aligned}
\widehat{\theta}_a^{\mathrm{AIPW}}
&= \overline{Y}_a
-\frac{1}{n_a}\sum_{i:A_i=a}\widehat{\mu}_a(X_i) \\
&\quad +\frac{1}{n}\sum_{i=1}^{n}\widehat{\mu}_a(X_i)
\end{aligned}
```

where $\widehat{\mu}_a(X_i)$ is the working model prediction under treatment arm $a$.

For two treatment arms, the adjusted treatment effect is estimated as:

```math
\widehat{\mathrm{ATE}}
= \widehat{\theta}_1^{\mathrm{AIPW}}
- \widehat{\theta}_0^{\mathrm{AIPW}}
```

The estimator combines observed outcomes with model-based predictions to adjust for baseline covariate imbalances.

### 4. Joint Calibration

Joint calibration uses treatment-specific predictions and randomization strata to construct calibrated outcome predictions.

Under the theoretical conditions established by Bannick et al., joint calibration provides a universally applicable asymptotic variance formulation and guarantees no loss of asymptotic efficiency relative to the unadjusted estimator.

The SAS implementation will reproduce the calibration procedure described in the paper and compare the resulting estimates with RobinCar.

### 5. Variance Estimation and Statistical Inference

The project will implement variance estimators appropriate for the specified randomization design.

Planned outputs include:

- Treatment-specific adjusted means
- Adjusted treatment differences
- Estimated standard errors
- Variance-covariance matrices
- 95% confidence intervals
- Wald-type hypothesis tests



## Planned SAS Implementation

The project will implement the core functionality of the R package **RobinCar** using standard SAS procedures. Each program will focus on a specific component of the estimation workflow, with reusable SAS macros developed where appropriate.

### Program-to-Function Mapping

Program summaries for 04–07 (inputs, methods, outputs and validation): [Program 04](doc/program_04_summary.md), [05](doc/program_05_summary.md),
[06](doc/program_06_summary.md), and [07](doc/program_07_summary.md).
Initial implementations of programs 04–07 are now available; SAS runtime and
RobinCar numerical validation remain pending. See [loading instructions and
input contracts](sas/README.md).

| SAS Program | Proposed SAS Macro | RobinCar Function | Description |
|---|---|---|---|
| `01_data_preparation.sas` | `%car_prepare()` | Data preprocessing within `robincar_linear()` / `robincar_glm()` | Prepare analysis datasets, treatment indicators, baseline covariates, and randomization strata. |
| `02_outcome_models.sas` | `%car_fit()` | `robincar_linear()` | Fit ANOVA, ANCOVA, and ANHECOVA working models using linear regression. |
| `03_aipw_estimation.sas` | `%car_aipw()` | `robincar_linear()` / `robincar_glm()` | Generate treatment-specific predictions and calculate AIPW-adjusted treatment means. |
| `04_joint_calibration.sas` | `%car_calibrate()` | `robincar_calibrate()` | Perform joint calibration using predicted outcomes and randomization strata. |
| `05_variance_estimation.sas` | `%car_variance()` | Variance estimation within `robincar_linear()` / `robincar_glm()` | Estimate the asymptotic variance-covariance matrix under the specified randomization scheme. |
| `06_treatment_contrasts.sas` | `%car_contrast()` | `robincar_contrast()` | Calculate treatment differences, standard errors, confidence intervals, and hypothesis tests. |
| `07_validation.sas` | `%car_validate()` | RobinCar reference outputs | Compare SAS estimates and inferential results against the R implementation. |



### SAS Procedures

| SAS Procedure | Intended Use |
|---|---|
| `PROC REG` | Fit linear working outcome models |
| `PROC GLM` | Implement ANCOVA and ANHECOVA |
| `PROC SQL` | Aggregate outcomes and predictions for AIPW estimation |
| `DATA Step` | Prepare analysis datasets and calculate predicted outcomes |
| `PROC IML` | Perform matrix calculations for calibration and variance estimation |
| `PROC COMPARE` | Validate SAS outputs against reference results |


## Repository Structure

- `sas/`: analysis macros.
- `doc/`: program summaries, following the Program 01 and 02 format.
- `examples/`: runnable analysis examples; Program 03 remains planned.
- `validation/`: R reference generators and SAS/R test entry points.
- `utilities/`: SAS data-path configuration and shared R validation/export helpers.

## Available Data Preparation Program

[`sas/01_data_preparation.sas`](sas/01_data_preparation.sas) implements the
supplied preparation code using the uploaded
[`robincar_example_data.csv`](robincar_example_data.csv) at the repository root.
Upload the CSV to an accessible directory on your SAS server. In
[`utilities/utilities.SAS`](utilities/utilities.SAS), edit the `csv_path` argument in the
`%car_config()` call to your full server file path (without quotation marks).
Run `utilities/utilities.SAS` first, then `01_data_preparation.sas`, then
`02_outcome_models.sas`, in the same SAS
session. Each colleague configures their own server path in `utilities/utilities.SAS`;
the preparation program reads the shared macro variable `input_csv`.
Repeat configuration when starting a new session. Import uses the uploaded
server file directly, without a GitHub HTTP request.

Submit the full program to import, validate, standardize, and summarize the
data. It creates `WORK.ANALYSIS_DATA`, `WORK.ALLOCATION_SUMMARY`,
`WORK.BASELINE_SUMMARY`, and `WORK.QC_ISSUES`. All three source arms (0, 1, 2)
are retained by default, following the supplied code. Set `analysis_arms` to
`0 1` only when using the matching two-arm R reference analysis. Randomization
design remains `NOT_VERIFIED` until supported by source documentation.
SAS execution and runtime validation remain pending.

## Available Outcome Models

[`sas/02_outcome_models.sas`](sas/02_outcome_models.sas) provides
`%car_fit(data=work.analysis_data, method=ALL)` for ANOVA, ANCOVA, and ANHECOVA
with categorical treatment and covariates `X1_ANALYSIS`, `X3_ANALYSIS`.
It retains all selected arms and saves fitted values, residuals, parameters,
diagnostics, and model item stores for later PROC PLM scoring. Final CAR
inference is handled in later stages. See the
[Program 02 summary and validation instructions](doc/program_02_summary.md).
SAS/R runtime validation remains pending.

## Available AIPW Point Estimates

[`sas/03_aipw_estimation.sas`](sas/03_aipw_estimation.sas) scores every
participant under every selected treatment arm using the Program 02 item
stores. `%car_aipw(data=work.analysis_data,method=ALL)` creates
`WORK.AIPW_PREDICTIONS` and `WORK.AIPW_MEANS`. The mean for each arm is its
mean predicted outcome across all participants plus the mean observed
residual in that arm. It supports all treatment arms present in the input
and calculates point estimates only; CAR-aware variance and formal contrasts
remain for later programs. Run Programs 01, 02, and 03 in the same SAS
session. See the [Program 03 summary and validation instructions](doc/program_03_summary.md).
SAS runtime validation remains pending.

To save the available Program 02 comparison tables and Program 03 results as
CSV files, submit [`sas/export_results.sas`](sas/export_results.sas) in the
same SAS session. Edit its `export_dir` setting to an existing SAS-server
directory. Missing tables are reported and skipped.

## Available Calibration, Inference, and Validation Programs

- [`sas/04_joint_calibration.sas`](sas/04_joint_calibration.sas): arm-specific
  calibration using all arm predictions and optional joint-stratum adjustment.
- [`sas/05_variance_estimation.sas`](sas/05_variance_estimation.sas): type-1
  robust covariance under simple or stratified permuted-block randomization.
- [`sas/06_treatment_contrasts.sas`](sas/06_treatment_contrasts.sas): linear
  contrasts, covariance, normal confidence intervals and Wald tests.
- [`sas/07_validation.sas`](sas/07_validation.sas): keyed numerical comparison
  against reference tables using absolute and relative tolerances.

Load [`sas/car_common.sas`](sas/car_common.sas) before these macro definitions.
Programs 04–06 require SAS/IML. The [continuous bridge example](examples/continuous_04_07.sas)
constructs ANCOVA predictions and AIPW inputs while general-purpose programs
03 remains planned. An [inference validation driver](validation/test_inference.sas), a [synthetic smoke suite](validation/smoke_04_07.sas) and
[RobinCar reference exporter](validation/robincar_reference.R) support validation.
These SAS programs have not yet been executed; numerical equivalence has not
been established. See [run instructions](sas/README.md).

## Available Experimental Example

[`examples/binomial_gcomp_mi.sas`](examples/binomial_gcomp_mi.sas) contains an
author-supplied five-arm binomial-logit example with multiple imputation and
Rubin-rule pooling. This extends beyond the initial scope below and does not
implement joint calibration. It has not yet been run or numerically validated
against RobinCar. See [example setup and input requirements](examples/README.md).

## Validation Strategy

The SAS implementation will be validated against the R package RobinCar using identical datasets, model specifications, treatment definitions, and randomization settings.

The validation will compare:

- Treatment-specific predicted outcomes
- AIPW-adjusted treatment means
- Jointly calibrated estimates
- Treatment effect estimates
- Estimated variance-covariance matrices
- Standard errors and confidence intervals

The emphasis will be on **numerical reproducibility and implementation accuracy**, rather than a large-scale simulation study.

## Scope and Limitations

The initial implementation is restricted to:

- Two or more treatment arms for working-model fitting and AIPW point estimates; planned CAR inference initially focuses on two arms
- Continuous outcomes
- Linear working outcome models
- Simple and stratified permuted block randomization
- AIPW and joint calibration
- Large-sample statistical inference

Binary outcomes, time-to-event outcomes, machine learning-based outcome models, and cross-fitting are outside the initial scope.

This repository is intended for methodological demonstration and research. The SAS programs will require appropriate validation before use in regulated clinical trial analyses.

## Reference Implementation

This project draws on the R package **RobinCar**, which provides methods for robust covariate adjustment in randomized clinical trials.

- [RobinCar GitHub Repository](https://github.com/mbannick/RobinCar)
- [RobinCar Documentation](https://marlenabannick.com/RobinCar/)

The SAS implementation is an independent educational and research project and is not an official SAS translation of RobinCar.

## References

Bannick, M. et al. (2025). *A General Form of Covariate Adjustment in Clinical Trials under Covariate-Adaptive Randomization*. Biometrics.

U.S. Food and Drug Administration. (2023). *Adjusting for Covariates in Randomized Clinical Trials for Drugs and Biological Products: Guidance for Industry*.

## Project Development

This project is being developed as a potential contribution to PharmaSUG, focusing on practical SAS implementation of modern statistical methods for randomized clinical trials.

Further documentation, example programs, and validation results will be added as development progresses.
