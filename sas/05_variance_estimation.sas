/*==========================================================================
 Program : 05_variance_estimation.sas
 Project : Robust Covariate Adjustment under CAR (SAS / RobinCar)
 Purpose : Estimate type-1 treatment-mean covariance under simple or PB
           designs.
 Status  : See doc/validation_status.md for verified configurations.

 INPUT  : Analysis data, arm-recentered MU_TILDE predictions, treatment
          means, arm map and explicit randomization design.
 OUTPUT : Mean covariance, SEs/CIs, variance components, stratum residuals;
          CAR_RC.

 IMPORTANT:
 - Requires SAS/IML; load 00_car_common.sas first. Loading defines macros only.
 - Supports variance_type=1 and simple / permuted-block designs only.
 - Uses empirical allocation proportions and sample covariance denominators.
 - V_SR and V_OMEGA are unscaled; final covariance divides by total n.
 - Invalid covariance fails; no clipping or alternative variance is applied.
 - Reference: RobinCar/R/variance-linear.R and utils-car.R.
==========================================================================*/

/*==========================================================================
 Macro   : car_variance
 Purpose : Calculate CAR covariance and normal treatment-mean inference.

 INPUT  : DATA, PREDICTIONS, ESTIMATES, ARM_MAP; CAR_SCHEME, VARIANCE_TYPE,
          ALPHA.
 OUTPUT : OUT_VCOV, OUT_INFERENCE, OUT_COMPONENTS, OUT_RESIDUALS; CAR_RC.

 IMPORTANT:
 - MU_TILDE must be arm-recentered and agree with the supplied means.
 - PB requires populated arm-by-stratum cells; numerical failures return 1.
==========================================================================*/
%macro car_variance(
    data           = work.analysis_data,
    predictions    = work.car_aipw_predictions,
    estimates      = work.car_arm_estimates,
    arm_map        = work.car_arm_map,
    car_scheme     =,
    variance_type  = 1,
    alpha          = 0.05,
    out_vcov       = work.car_mean_vcov,
    out_inference  = work.car_mean_inference,
    out_components = work.car_variance_components,
    out_residuals  = work.car_stratum_residuals
);
    %global car_rc _car_error_rc;
    %let car_rc = 1;
    %let _car_error_rc = 0;
    %local scheme;
    %if not %sysmacexist(car_inputs) %then %do;
        %let car_rc = 1;
        %put ERROR: [CAR] Run 00_car_common.sas first.;
        %return;
    %end;

    %local _car_outputs _car_iml_ok;
    %let _car_outputs = &out_vcov &out_inference &out_components &out_residuals;
    %car_output_guard(
        inputs   = &data &predictions &estimates &arm_map,
        outputs  = &_car_outputs,
        expected = 4
    );
    %if &_car_error_rc %then %return;
    %car_clear(outputs=&_car_outputs);
    %if &_car_error_rc %then %goto variance_fail;

    %let scheme = %lowcase(&car_scheme);
    %if "%superq(scheme)" ne "simple" and "%superq(scheme)" ne "permuted-block" %then %do;
        %car_error(message=Specify CAR_SCHEME=simple or permuted-block based on the design.);
        %goto variance_fail;
    %end;

    %car_number(
        name    = VARIANCE_TYPE,
        value   = %superq(variance_type),
        lower   = 1,
        upper   = 1,
        integer = YES
    );
    %if &_car_error_rc %then %goto variance_fail;
    %car_alpha(value=%superq(alpha));
    %if &_car_error_rc %then %goto variance_fail;

    %car_inputs(
        data        = &data,
        predictions = &predictions,
        arm_map     = &arm_map
    );
    %if &_car_error_rc %then
        %goto variance_fail;
    %car_estimates(estimates = &estimates);
    %if &_car_error_rc %then
        %goto variance_fail;
    %let _car_iml_ok = 0;

    proc iml;
        /* Keep the complete calculation in one module: RETURN skips all
           remaining matrix work and leaves _CAR_IML_OK=0 on failure. */
        start _car_compute;
            use work._car_data;
            read all var {trt aval} into dat;
            read all var {strata} into strata;
            close work._car_data;

            use work._car_arms;
            read all var {arm_index trt n_arm pi_hat} into arms;
            close work._car_arms;

            use work._car_grid;
            read all var {mu_tilde} into p;
            close work._car_grid;

            n = nrow(dat);
            k = nrow(arms);
            mu = shape(p, n, k);
            pi = arms[, 4];
            meanMu = mu[:,];
            mc = mu - repeat(meanMu, n, 1);
            sigma = mc` * mc / (n - 1);
            if any(sigma = .) then do;
                print "ERROR: [CAR] Missing prediction covariance after matrix arithmetic.";
                return;
            end;
            q = j(k, k, .);
            vy = j(k, 1, .);
            resid = j(n, 1, .);

            do a = 1 to k;
                idx = loc(dat[, 1] = arms[a, 2]);
                ya = dat[idx, 2];
                ma = mu[idx,];
                yc = ya - mean(ya);
                mac = ma - repeat(ma[:,], nrow(ma), 1);
                /* SUM skips missing values, including results of overflow.
                   Check before squaring and before reducing the vector. */
                if any(yc = .) | any(mac = .) then do;
                    print "ERROR: [CAR] Missing centered outcomes or predictions." a;
                    return;
                end;
                if max(abs(yc)) > sqrt(constant("BIG")) then do;
                    print "ERROR: [CAR] Outcome squares would overflow." a;
                    return;
                end;
                squared = yc ## 2;
                if any(squared = .) then do;
                    print "ERROR: [CAR] Missing outcome squares; variance not computed." a;
                    return;
                end;
                q[a,] = yc` * mac / (nrow(ma) - 1);
                sum_squares = sum(squared);
                if sum_squares = . | any(q[a,] = .) then do;
                    print "ERROR: [CAR] Missing outcome sum of squares or cross-covariance." a;
                    return;
                end;
                vy[a] = sum_squares / (nrow(ma) - 1);
                resid[idx] = ya - ma[, a];
                if abs(mean(resid[idx])) > 1e-8 + 1e-6 * max(abs(ya)) then do;
                    print "ERROR: [CAR] Predictions are not arm-recentered." a;
                    return;
                end;
            end;
            vsr = diag((vy - 2 * vecdiag(q) + vecdiag(sigma)) / pi)
                + q + q` - sigma;
            if any(vsr = .) | any(resid = .) then do;
                print "ERROR: [CAR] Missing variance components or residuals.";
                return;
            end;
            omegaSR = diag(pi) - pi * pi`;
            correction = j(k, k, 0);
            levels = unique(strata);
            sr = j(ncol(levels) * k, 4, .);

            do s = 1 to ncol(levels);
                ns = sum(strata = levels[s]);
                r = j(k, 1, .);
                do a = 1 to k;
                    idx = loc((strata = levels[s]) & (dat[, 1] = arms[a, 2]));
                    count = ncol(idx);
                    if count > 0 then r[a] = mean(resid[idx]);
                    sr[(s - 1) * k + a,] = s || a || count || r[a];
                end;
                %if "&scheme" = "permuted-block" %then %do;
                    if any(r = .) then do;
                        print "ERROR: [CAR] Empty arm-by-stratum cell in PB variance." s;
                        return;
                    end;
                    rs = diag(r / pi);
                    correction = correction + (ns / n) * rs * omegaSR * rs;
                %end;
            end;
            cov = (vsr - correction) / n;
            cov = (cov + cov`) / 2;
            if any(correction = .) | any(cov = .) then do;
                print "ERROR: [CAR] Missing CAR correction or covariance.";
                return;
            end;

            call eigen(eigenvalues, eigenvectors, cov);
            if any(eigenvalues = .) then do;
                print "ERROR: [CAR] Missing covariance eigenvalues.";
                return;
            end;
            tol = 1e-10 * max(1, max(abs(cov)));
            check = min(eigenvalues) || tol || min(vecdiag(cov));
            create work._car_varcheck from check
                [colname = {minimum_eigenvalue covariance_tolerance minimum_diagonal}];
            append from check;
            close work._car_varcheck;
            if min(eigenvalues) < -tol | min(vecdiag(cov)) < 0 then do;
                print "ERROR: [CAR] Invalid covariance; no truncation applied." cov eigenvalues;
                return;
            end;
            results = j(k * k, 3, .);
            components = j(k * k, 4, .);
            do a = 1 to k;
                do b = 1 to k;
                    pos = (a - 1) * k + b;
                    results[pos,] = a || b || cov[a, b];
                    components[pos,] = a || b || vsr[a, b] || correction[a, b];
                end;
            end;
            estimates = arms[, 1:3] || meanMu` || sqrt(vecdiag(cov));
            create work._car_varnum from results
                [colname = {arm_i arm_j covariance}];
            append from results;
            close work._car_varnum;

            create work._car_components from components
                [colname = {arm_i arm_j v_sr v_omega}];
            append from components;
            close work._car_components;

            create work._car_inference from estimates
                [colname = {arm_index trt n_arm estimate se}];
            append from estimates;
            close work._car_inference;

            create work._car_srnum from sr
                [colname = {stratum_index arm_index n_cell residual_mean}];
            append from sr;
            close work._car_srnum;

            stratum_index = T(1:ncol(levels));
            stratum_label = T(levels);
            create work._car_strata var {stratum_index stratum_label};
            append;
            close work._car_strata;

            call symputx("_car_iml_ok", 1, "L");
        finish;
        run _car_compute;
    quit;
    %car_step(context=Variance step);
    %if &_car_error_rc %then %goto variance_fail;
    %if &_car_iml_ok ne 1 %then %do;
        %car_error(message=Variance IML computation did not complete.);
        %goto variance_fail;
    %end;

    %if &_car_error_rc %then %do;
        %car_error(message=Variance computation failed. Outputs have been invalidated.);
        %goto variance_fail;
    %end;

    data &out_vcov;
        set work._car_varnum;
    run;
    %car_step(context=Variance step);
    %if &_car_error_rc %then %goto variance_fail;

    data &out_components;
        if _n_ = 1 then set work._car_varcheck;
        set work._car_components;
        length car_scheme $14;
        car_scheme = "&scheme";
    run;
    %car_step(context=Variance step);
    %if &_car_error_rc %then %goto variance_fail;

    data &out_inference;
        set work._car_inference;
        length status $16;
        alpha = &alpha;
        lcl = estimate - quantile('NORMAL', 1 - alpha / 2) * se;
        ucl = estimate + quantile('NORMAL', 1 - alpha / 2) * se;
        if se > 0 then do;
            z = estimate / se;
            p_value = 2 * cdf('NORMAL', -abs(z));
            status = 'OK';
        end;
        else status = 'ZERO_SE';
    run;
    %car_step(context=Variance step);
    %if &_car_error_rc %then %goto variance_fail;

    proc sql;
        create table &out_residuals as
        select s.stratum_label as strata, r.arm_index, r.n_cell, r.residual_mean
        from work._car_srnum r
        left join work._car_strata s
        on r.stratum_index = s.stratum_index
        order by r.stratum_index, r.arm_index;
    quit;
    %car_step(
        context = Variance step,
        sql     = YES
    );
    %if &_car_error_rc %then %goto variance_fail;

    %car_result_values(
        data   = &out_vcov,
        values = arm_i arm_j covariance
    );
    %if &_car_error_rc %then %goto variance_fail;
    %car_result_values(
        data   = &out_components,
        values = arm_i arm_j v_sr v_omega minimum_eigenvalue covariance_tolerance minimum_diagonal
    );
    %if &_car_error_rc %then %goto variance_fail;
    %car_result_values(
        data      = &out_inference,
        values    = arm_index trt n_arm estimate se lcl ucl,
        inference = YES
    );
    %if &_car_error_rc %then %goto variance_fail;
    %put NOTE: [CAR] Type-1 covariance computed for &scheme.;
    %let car_rc = 0;
    %return;

%variance_fail:
    %car_clear(outputs=&_car_outputs);
    /* The error flag stays set; cleanup must finish instead of retrying. */
    %let car_rc = 1;
    %put ERROR: [CAR] Variance failed. Specified public outputs invalidated.;
%mend;
