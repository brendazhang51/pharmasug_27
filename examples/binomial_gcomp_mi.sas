/*----------------------------------------------------------------------------
  SAS/IML implementation of

    robincar_glm(
      df              = sorted_g,
      treat_col       = "ARMCD",
      response_col    = "WT5",
      formula         = WT5 ~ ARMCD + STRATUM + BASE,
      car_strata_cols = "STRATUM",
      car_scheme      = "permuted-block",
      g_family        = binomial(link = "logit"),
      contrast_h      = "diff",
      variance_type   = 1
    )

  Requires SAS/IML.

  Experimental example supplied by the project author; not yet validated
  against RobinCar. This extends the initial two-arm continuous-outcome scope.

  Outputs in WORK (auxiliary tables have an imputation-number suffix)
    fit_main             Main RobinCar result: treat, estimate, se, pval
    fit_main_varcov<i>      Main covariance matrix in long form
    fit_contrast         RobinCar diff contrast result
    fit_contrast_varcov<i>  Contrast covariance matrix in long form
    fit_g_estimate<i>       Raw g-computation means (main$g.estimate)
    fit_mu_a<i>             mu_hat and re-centered mu_tilde for each person/arm
    fit_model_parameters<i> Logistic working-model coefficients
----------------------------------------------------------------------------*/
/* Prepare WORK.COMPLETE before running this file. For example:
   libname source "/path/on/sas/server" access=readonly;
   data work.complete; set source.complete; run;
   Required variables: _IMPUTATION_, ARMCD, STRATUM, WT5, BASE.
   No participant data are included in this repository.
*/

%let response = WT5;  /*5% weight loss at Week 76 (binomial)*/
%let baseline = BASE;  /*Baseline weight (continuous)*/
%let k        = 5;  /*Number of arms*/
%let nstrata  = 4;  /*Number of strata*/
%let nimpute  = 10;  /*Number of imputations; numbered 1 through nimpute*/

/* R factor levels for ARMCD: CP must be first for treatment minus placebo. */
%let arm1 = CP;
%let arm2 = C10K;
%let arm3 = C13K;
%let arm4 = C16K;
%let arm5 = C20K;

/* R factor levels for STRATUM, in their exact R order. */
%let stratum1 = F <40;
%let stratum2 = F >=40;
%let stratum3 = M <40;
%let stratum4 = M >=40;

%macro gcomp();
%local i _rc_bad_n _rc_n;
%if not %sysfunc(exist(work.complete)) %then %do;
  %put ERROR: Create WORK.COMPLETE before running this example.;
  %abort cancel;
%end;
%do i = 1 %to &nimpute.;
/* Map the R factor levels to numeric reference-cell coding. */
data _rc_analysis;
  set work.complete(where = (_IMPUTATION_ = &i.));
  _obsid = _n_;
  length armidx stratumidx 8;

  select (strip(ARMCD));
    when ("&arm1") armidx=1;
    when ("&arm2") armidx=2;
    when ("&arm3") armidx=3;
    when ("&arm4") armidx=4;
    when ("&arm5") armidx=5;
    otherwise      armidx=.;
  end;

  select (strip(STRATUM));
    when ("&stratum1") stratumidx=1;
    when ("&stratum2") stratumidx=2;
    when ("&stratum3") stratumidx=3;
    when ("&stratum4") stratumidx=4;
    otherwise          stratumidx=.;
  end;
run;

proc sort data = _rc_analysis; by armidx; run;

proc sql noprint;
  select count(*) into :_rc_n trimmed from _rc_analysis;
  select count(*) into :_rc_bad_n trimmed
  from _rc_analysis
  where missing(&response) or missing(&baseline)
     or missing(armidx) or missing(stratumidx);
quit;

%if &_rc_n = 0 %then %do;
  %put ERROR: No observations for imputation &i.;
  %abort cancel;
%end;
%if &_rc_bad_n > 0 %then %do;
  %put ERROR: &_rc_bad_n observations have missing analysis values or unmapped factor levels.;
  %put ERROR: Correct the ARMCD/STRATUM level macros so they match R exactly.;
  %abort cancel;
%end;

proc iml;
  /* Read the exact rows supplied to the R call. */
  use _rc_analysis;
    read all var {"_obsid" "armidx" "stratumidx" "&response" "&baseline"}
      into d;
  close _rc_analysis;

  n        = nrow(d);
  k        = &k;
  nstrata  = &nstrata;
  obsid    = d[,1];
  arm      = d[,2];
  stratum  = d[,3];
  y        = d[,4];
  base     = d[,5];

  if any(y^=0 & y^=1) then do;
    print "ERROR: &response must contain only 0 and 1.";
    abort;
  end;

  /* Each arm needs at least two observations for sample variances. */
  do a = 1 to k;
    ia = loc(arm=a);
    if ncol(ia)<2 then do;
      print "ERROR: Each treatment arm requires at least two observations.";
      abort;
    end;
  end;

  /*
    R model.matrix for WT5 ~ ARMCD + STRATUM + BASE with treatment
    contrasts: intercept, levels 2:K of ARMCD, levels 2:S of STRATUM, BASE.
  */
  p = 1 + (k-1) + (nstrata-1) + 1;
  X = j(n, p, 1);
  col = 2;
  do a = 2 to k;
    X[,col] = (arm=a);
    col = col + 1;
  end;
  do s = 2 to nstrata;
    X[,col] = (stratum=s);
    col = col + 1;
  end;
  X[,p] = base;

  /*
    Fit the same binomial-logit working model as glm().  The initial values
    reproduce R's binomial mustart=(y+0.5)/2, followed by IRLS to a tighter
    tolerance than glm.control()'s default.
  */
  mustart = (y + 0.5) / 2;
  eta0    = log(mustart / (1-mustart));
  z0      = eta0 + (y-mustart)/(mustart#(1-mustart));
  beta    = solve(X`*X, X`*z0);

  do iter = 1 to 100;
    eta    = X*beta;
    pr     = 1 / (1 + exp(-eta));
    w      = pr # (1-pr);
    info   = X` * (X # repeat(w, 1, p));
    score  = X` * (y-pr);
    delta  = solve(info, score);
    beta   = beta + delta;
    if max(abs(delta)) < 1e-12 then leave;
  end;

  if iter>100 then do;
    print "ERROR: Logistic working model did not converge.";
    abort;
  end;

  eta  = X*beta;
  pobs = 1 / (1 + exp(-eta));
  w    = pobs # (1-pobs);
  info = X` * (X # repeat(w, 1, p));
  beta_vcov = inv(info);

  /* Predict the potential outcome under every treatment arm. */
  mu_hat = j(n, k, .);
  do a = 1 to k;
    Xa = X;
    Xa[,2:k] = 0;
    if a>1 then Xa[,a] = 1;
    mu_hat[,a] = 1 / (1 + exp(-(Xa*beta)));
  end;

  /* RobinCar get.mutilde(): re-center within observed treatment arm. */
  mu_tilde = mu_hat;
  do a = 1 to k;
    ia = loc(arm=a);
    center = mean(mu_hat[ia,a]) - mean(y[ia]);
    mu_tilde[,a] = mu_hat[,a] - center;
  end;

  estimate   = j(k,1,.);
  g_estimate = j(k,1,.);
  pi          = j(k,1,.);
  observed_mu = j(n,1,.);
  do a = 1 to k;
    ia = loc(arm=a);
    estimate[a]   = mean(mu_tilde[,a]);
    g_estimate[a] = mean(mu_hat[,a]);
    pi[a]         = ncol(ia)/n;
    observed_mu[ia] = mu_tilde[ia,a];
  end;

  /*
    RobinCar vcov_car(), variance_type=1.  cov() and the explicit variance
    calculations use R's usual n-1 sample denominators.
  */
  var_mu_tilde = cov(mu_tilde);
  cov_y_mu     = j(k,k,.);
  var_y        = j(k,1,.);
  diag_vec     = j(k,1,.);

  do a = 1 to k;
    ia = loc(arm=a);
    na = ncol(ia);
    ya = y[ia];
    ma = mu_tilde[ia,];
    yc = ya - mean(ya);
    mc = ma - repeat(mean(ma), na, 1);
    cov_y_mu[a,] = yc`*mc/(na-1);
    var_y[a] = sum(yc#yc)/(na-1);
    diag_vec[a] = var_y[a]/pi[a]
                + (var_mu_tilde[a,a] - 2*cov_y_mu[a,a])/pi[a];
  end;
  v_sr = diag(diag_vec) + cov_y_mu + cov_y_mu` - var_mu_tilde;

  /*
    RobinCar get.erb() for car_scheme="permuted-block":
    Omega_Z is zero, so the correction is R(B)*Omega_simple*R(B), averaged
    over the CAR strata.
  */
  omega_simple = diag(pi) - pi*pi`;
  erb = j(k,k,0);
  do s = 1 to nstrata;
    is = loc(stratum=s);
    prop_s = ncol(is)/n;
    rb = j(k,k,0);
    do a = 1 to k;
      ias = loc((arm=a)#(stratum=s));
      if ncol(ias)=0 then do;
        print "ERROR: An ARMCD by STRATUM cell is empty; RobinCar's covariance is undefined.";
        abort;
      end;
      rb[a,a] = mean(y[ias] - observed_mu[ias])/pi[a];
    end;
    erb = erb + prop_s * rb * omega_simple * rb;
  end;

  V = (v_sr - erb) / n;                 /* HC0 weight is 1 in RobinCar. */

  /* RobinCar format_results() for the main estimates. */
  se = j(k,1,.);
  do a = 1 to k;
    se[a] = sqrt(V[a,a]);
  end;
  z    = estimate / se;
  pval = 2 * probnorm(-abs(z));

  treat = {"&arm1", "&arm2", "&arm3", "&arm4", "&arm5"};
  create fit_main&i. var {treat estimate se pval};
    append;
  close fit_main&i.;

  create fit_g_estimate&i. var {treat g_estimate};
    append;
  close fit_g_estimate&i.;

  /* Equivalent to RobinCar's main$varcov, stored in a portable long layout. */
  row_treat = j(k*k,1,"                ");
  col_treat = j(k*k,1,"                ");
  covariance = j(k*k,1,.);
  q = 0;
  do a = 1 to k;
    do b = 1 to k;
      q=q+1;
      row_treat[q]=treat[a];
      col_treat[q]=treat[b];
      covariance[q]=V[a,b];
    end;
  end;
  create fit_main_varcov&i. var {row_treat col_treat covariance};
    append;
  close fit_main_varcov&i.;

  /* RobinCar contrast_h="diff": arm[2:K] - arm[1]. */
  H = -j(k-1,1,1) || I(k-1);
  contrast_estimate = H*estimate;
  Vcontrast = H*V*H`;
  contrast_se = j(k-1,1,.);
  do a = 1 to k-1;
    contrast_se[a]=sqrt(Vcontrast[a,a]);
  end;
  contrast_pval = 2*probnorm(-abs(contrast_estimate/contrast_se));
  contrast = {"&arm2 - &arm1",
              "&arm3 - &arm1",
              "&arm4 - &arm1",
              "&arm5 - &arm1"};
  estimate = contrast_estimate;
  se       = contrast_se;
  pval     = contrast_pval;
  create fit_contrast&i.
    var {contrast estimate se pval};
    append;
  close fit_contrast&i.;

  row_contrast = j((k-1)*(k-1),1,"                                ");
  col_contrast = j((k-1)*(k-1),1,"                                ");
  covariance = j((k-1)*(k-1),1,.);
  q=0;
  do a=1 to k-1;
    do b=1 to k-1;
      q=q+1;
      row_contrast[q]=contrast[a];
      col_contrast[q]=contrast[b];
      covariance[q]=Vcontrast[a,b];
    end;
  end;
  create fit_contrast_varcov&i.
    var {row_contrast col_contrast covariance};
    append;
  close fit_contrast_varcov&i.;

  /* The working-model coefficients, corresponding to main$mod$coefficients. */
  parameter = {"Intercept",
               "ARMCD=&arm2", "ARMCD=&arm3", "ARMCD=&arm4", "ARMCD=&arm5",
               "STRATUM=&stratum2", "STRATUM=&stratum3", "STRATUM=&stratum4",
               "BASE"};
  beta_se = j(p,1,.);
  do a=1 to p;
    beta_se[a]=sqrt(beta_vcov[a,a]);
  end;
  create fit_model_parameters&i. var {parameter beta beta_se};
    append;
  close fit_model_parameters&i.;

  /* Save both raw mu_hat and RobinCar's re-centered mu_a (mu_tilde). */
  long_n = n*k;
  obsid_long = j(long_n,1,.);
  treat_long = j(long_n,1,"                ");
  mu_hat_long = j(long_n,1,.);
  mu_tilde_long = j(long_n,1,.);
  q=0;
  do i=1 to n;
    do a=1 to k;
      q=q+1;
      obsid_long[q]=obsid[i];
      treat_long[q]=treat[a];
      mu_hat_long[q]=mu_hat[i,a];
      mu_tilde_long[q]=mu_tilde[i,a];
    end;
  end;
  create fit_mu_a&i.
    var {obsid_long treat_long mu_hat_long mu_tilde_long};
    append;
  close fit_mu_a&i.;
quit;

%if &i. = 1 %then %do;
data fit_main;
set fit_main&i.;
_IMPUTATION_ = &i.;
run;

data fit_contrast;
set fit_contrast&i.;
_IMPUTATION_ = &i.;
run;
%end;

%else %do;
data fit_main;
set fit_main fit_main&i.(in = inb);
if inb then _IMPUTATION_ = &i.;
run;

data fit_contrast;
set fit_contrast fit_contrast&i.(in = inb);
if inb then _IMPUTATION_ = &i.;
run;
%end;
%end;
%mend;

%gcomp();

/* Combine the estimates of each imputation using Rubin's Rule. */
proc sort data = fit_main; by treat; run;

proc mianalyze data = fit_main;
by treat;
  modeleffects estimate;
  stderr se;
  ods output ParameterEstimates = final_gcomp_arm_means;
run;

proc sort data = fit_contrast; by contrast; run;

proc mianalyze data = fit_contrast;
by contrast;
  modeleffects estimate;
  stderr se;
  ods output ParameterEstimates = final_gcomp_risk_differences;
run;
