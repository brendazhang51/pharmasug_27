# Statistical Background

### 1. Covariate-Adaptive Randomization

Covariate-adaptive randomization (CAR) aims to improve the balance of important baseline characteristics across treatment groups.

The implemented design settings are:

- Simple randomization
- Stratified permuted block randomization

Additional randomization schemes, such as Pocock–Simon minimization, may be considered in future extensions.

### 2. Working Outcome Models

The project implements three linear working models for continuous outcomes
with categorical treatment. The equations below use binary treatment notation
for illustration; the default example has three arms, fitted using treatment
indicators and, for ANHECOVA, their covariate interactions.

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

The first prediction-average term is g-computation (standardization); the
observed-arm residual mean is the augmentation. With the current in-sample OLS
fits including treatment indicators, arm-specific residual means are zero up
to numerical error, so the uncalibrated AIPW and g-computation point estimates
coincide. Inference still uses the separately implemented CAR covariance.

### 4. Joint Calibration

Joint calibration uses treatment-specific predictions and randomization strata to construct calibrated outcome predictions.

The cited paper motivates the asymptotic properties of joint calibration
under its assumptions. Numerical agreement with RobinCar checks implementation
agreement for the tested configurations; it does not establish a finite-sample
efficiency guarantee for every dataset.

The SAS implementation follows the calibration procedure described in the paper and compares the resulting estimates with RobinCar.

### 5. Variance Estimation and Statistical Inference

The project implements variance estimators appropriate for the specified randomization design.

Outputs include:

- Treatment-specific adjusted means
- Adjusted treatment differences
- Estimated standard errors
- Variance-covariance matrices
- 95% confidence intervals
- Wald-type hypothesis tests

The main workflow supports type-1 variance under simple and stratified
permuted-block designs. It uses marginal normal intervals, configurable alpha
and linear contrasts; the pipeline selects ANOVA/ANCOVA/ANHECOVA through `analysis_model`, uses joint
calibration and compares
each nonreference arm with the lowest numeric arm. See the
[support matrix](support_matrix.md) for data restrictions and unimplemented
models, designs and inference methods.

## Reference implementation

The SAS code is an independent research implementation. The reference exporter
requires RobinCar 1.2.0; see the [upstream package](https://github.com/mbannick/RobinCar)
and [function documentation](https://marlenabannick.com/RobinCar/).
See [validation status](validation_status.md) for the configurations actually checked.
The design setting in an example does not establish the source trial's design.

## Further reading

Bannick et al. (2025), *A General Form of Covariate Adjustment in Clinical
Trials under Covariate-Adaptive Randomization*, motivates this implementation.

FDA (2023), *Adjusting for Covariates in Randomized Clinical Trials for Drugs
and Biological Products: Guidance for Industry*, provides related background.
