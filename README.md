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

For a two-arm randomized trial with continuous outcomes, the project will examine three linear working models.

**ANOVA — Unadjusted model**

\[
Y_i=\beta_0+\beta_1 A_i+\epsilon_i
\]

**ANCOVA — Common-slope adjustment**

\[
Y_i=\beta_0+\beta_1 A_i+\beta_2^T X_i+\epsilon_i
\]

**ANHECOVA — Heterogeneous-slope adjustment**

\[
Y_i=\beta_0+\beta_1 A_i+\beta_2^T X_i+
\beta_3^T(A_iX_i)+\epsilon_i
\]

where:

- \(Y_i\): Observed continuous outcome
- \(A_i\): Treatment assignment
- \(X_i\): Baseline covariates
- \(\epsilon_i\): Regression error

ANHECOVA allows the relationship between baseline covariates and outcomes to differ across treatment arms.

### 3. Augmented Inverse Probability Weighting

The treatment-specific AIPW estimator considered in this project is:

\[
\hat\theta_a^{AIPW}
=
\bar Y_a
-\frac{1}{n_a}\sum_{i:A_i=a}\hat\mu_a(X_i)
+\frac{1}{n}\sum_{i=1}^{n}\hat\mu_a(X_i)
\]

where \(\hat\mu_a(X_i)\) is the working model prediction under treatment arm \(a\).

For two treatment arms, the adjusted treatment effect is estimated as:

\[
\widehat{ATE}=\hat\theta_1^{AIPW}-\hat\theta_0^{AIPW}
\]

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

Particular attention will be given to the treatment-allocation dependence introduced by covariate-adaptive randomization.

## Planned SAS Implementation

The implementation will primarily use standard SAS procedures, including:

| SAS Procedure | Intended Purpose |
|---|---|
| `PROC REG` | Linear working outcome models |
| `PROC GLM` | ANCOVA and ANHECOVA |
| `PROC SQL` | Data aggregation and AIPW estimation |
| `DATA Step` | Data preparation and prediction calculations |
| `PROC IML` | Matrix calculations and robust variance estimation |
| `PROC COMPARE` | Numerical validation and quality control |

The implementation may be organized into reusable SAS macros.

## Proposed Repository Structure

The following structure is planned and may evolve during development.

```text
.
├── README.md
├── sas/
│   ├── 01_data_preparation.sas
│   ├── 02_outcome_models.sas
│   ├── 03_aipw_estimation.sas
│   ├── 04_joint_calibration.sas
│   ├── 05_variance_estimation.sas
│   └── 06_treatment_contrasts.sas
├── examples/
│   └── worked_example.sas
├── validation/
│   ├── robincar_reference.R
│   └── compare_results.sas
└── docs/
    └── methodology.md
```

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

- Two-arm parallel-group randomized trials
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
