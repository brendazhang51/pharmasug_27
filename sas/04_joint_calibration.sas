/*==========================================================================
 Program : 04_joint_calibration.sas
 Project : Robust Covariate Adjustment under CAR (SAS / RobinCar)
 Purpose : Fit linear or joint calibration and re-center treatment
           predictions.
 Status  : See doc/validation_status.md for verified configurations.

 INPUT  : Program 03 predictions and means, analysis data and MODEL;
          optional numeric calibration covariates.
 OUTPUT : Calibrated predictions, treatment means, rank/estimability
          diagnostics; CAR_RC.

 IMPORTANT:
 - Requires SAS/IML; load 00_car_common.sas first. Loading does not run a fit.
 - Each arm-specific OLS uses every prediction arm; joint=YES adds strata.
 - SVD supports aliased columns; non-estimable predictions cause failure.
 - Process one population, model and estimator per call.
 - Reference: RobinCar/R/robincar-calibrate.R and utils-adjust.R.
==========================================================================*/

/*==========================================================================
 Macro   : car_calibrate
 Purpose : Fit calibration models and publish re-centered predictions.

 INPUT  : DATA, PREDICTIONS, MEANS, MODEL; JOINT, ADD_X and RANK_TOL.
 OUTPUT : OUT_PREDICTIONS, OUT_MEANS, OUT_DIAGNOSTICS; CAR_RC.

 IMPORTANT:
 - JOINT=YES includes stratum indicators; JOINT=NO omits them.
 - After safe name checks, failure clears the specified public outputs.
==========================================================================*/
%macro car_calibrate(
    data            = work.analysis_data,
    predictions     = work.aipw_predictions,
    means           = work.aipw_means,
    model           = ANCOVA,
    joint           = YES,
    add_x           = ,
    rank_tol        = 1e-10,
    out_predictions = work.car_cal_predictions,
    out_means       = work.car_cal_means,
    out_diagnostics = work.car_cal_diagnostics
);
    %global car_rc _car_error_rc;
    %let car_rc = 1;
    %let _car_error_rc = 0;
    %if not %sysmacexist(car_inputs) %then %do;
        %let car_rc = 1;
        %put ERROR: [CAR] Run 00_car_common.sas first.;
        %return;
    %end;

    %local _car_outputs _car_iml_ok;
    %let _car_outputs = &out_predictions &out_means &out_diagnostics;
    %car_output_guard(
        inputs   = &data &predictions &means,
        outputs  = &_car_outputs,
        expected = 3
    );
    %if &_car_error_rc %then %return;
    %car_clear(outputs=&_car_outputs);
    %if &_car_error_rc %then %goto calibrate_fail;

    %if "%qupcase(%superq(joint))" ne "YES"
        and "%qupcase(%superq(joint))" ne "NO" %then %do;
        %car_error(message=JOINT must be YES or NO.);
        %goto calibrate_fail;
    %end;

    %car_number(
        name       = RANK_TOL,
        value      = %superq(rank_tol),
        lower      = 0,
        upper      = 1,
        lower_open = YES,
        upper_open = YES
    );
    %if &_car_error_rc %then %goto calibrate_fail;

    %car_inputs(
        data        = &data,
        predictions = &predictions,
        means       = &means,
        model       = %superq(model),
        add_x       = &add_x
    );
    %if &_car_error_rc %then
        %goto calibrate_fail;

    %let _car_iml_ok = 0;

    proc iml;
        /* Keep the complete calculation in one module: RETURN skips all
           remaining matrix work and leaves _CAR_IML_OK=0 on failure. */
        start _car_compute;
            use work._car_data;
            read all var {trt aval} into dat;
            read all var {usubjid} into ids;
            read all var {strata} into strata;
            %if %length(%superq(add_x)) %then %do;
                read all var {&add_x} into extra;
            %end;
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
            x = j(n, 1, 1) || mu;
            %if %length(%superq(add_x)) %then %do;
                x = x || extra;
            %end;

            %if %upcase(&joint) = YES %then %do;
                levels = unique(strata);

                /* Intercept + S-1 dummies span the full joint-stratum space. */
                do s = 2 to ncol(levels);
                    x = x || (strata = levels[s]);
                end;
            %end;

            /* Scale columns before SVD, including constant/aliased predictions. */
            scale = sqrt(x[##,]);
            do j = 1 to ncol(x);
                if scale[j] = 0 then scale[j] = 1;
                x[, j] = x[, j] / scale[j];
            end;
            raw = j(n, k, .);
            centered = raw;
            diagout = j(k, 7, .);

            do a = 1 to k;
                idx = loc(dat[, 1] = arms[a, 2]);
                xa = x[idx,];
                ya = dat[idx, 2];

                /* SVD also supports wide matrices; keep only nonzero directions. */
                if any(xa = .) | any(ya = .) then do;
                    print "ERROR: [CAR] Missing calibration design or outcome.";
                    return;
                end;
                call svd(u, q, v, xa);
                if any(q = .) | any(u = .) | any(v = .) then do;
                    print "ERROR: [CAR] SVD produced missing values.";
                    return;
                end;
                keep = loc(q > &rank_tol * max(q));
                r = ncol(keep);
                if r = 0 then do;
                    print "ERROR: [CAR] Calibration has zero effective rank." a;
                    return;
                end;
                if nrow(xa) <= r then do;
                    print "ERROR: [CAR] Calibration has no residual degrees of freedom." a r;
                    return;
                end;
                vr = v[, keep];
                ur = u[, keep];
                beta = vr * diag(1 / q[keep]) * ur` * ya;
                if any(beta = .) then do;
                    print "ERROR: [CAR] Missing calibration coefficients." a;
                    return;
                end;

                /* Reject predictions outside the fitted row space. */
                error = max(abs(x - x * vr * vr`));
                if error = . | error > 100 * &rank_tol then do;
                    print
                        "ERROR: [CAR] Counterfactual calibration predictions are not estimable." a error;
                    return;
                end;
                raw[, a] = x * beta;
                delta = mean(ya - raw[idx, a]);
                centered[, a] = raw[, a] + delta;
                if any(raw[, a] = .) | any(centered[, a] = .) then do;
                    print "ERROR: [CAR] Missing calibrated predictions." a;
                    return;
                end;
                diagout[a,] = a || nrow(xa) || ncol(x) || r
                    || (ncol(x) - r) || error || delta;
            end;

            /* Subject-major, then arm-major order: same as WORK._CAR_GRID. */
            results = j(n * k, 3, .);
            do i = 1 to n;
                do a = 1 to k;
                    results[(i - 1) * k + a,] = a || raw[i, a] || centered[i, a];
                end;
            end;
            create work._car_calnum from results
                [colname = {arm_index mu_cal_raw mu_tilde}];
            append from results;
            close work._car_calnum;

            est = arms[, 1:3] || centered[:,]`;
            create work._car_calest from est
                [colname = {arm_index trt n_arm estimate}];
            append from est;
            close work._car_calest;

            create work._car_caldiag from diagout
                [colname = {
                    arm_index n_arm n_columns effective_rank n_aliased estimability_error
                    recenter_delta
                }];
            append from diagout;
            close work._car_caldiag;

            call symputx("_car_iml_ok", 1, "L");
        finish;
        run _car_compute;
    quit;
    %car_step(context=Calibrate step);
    %if &_car_error_rc %then %goto calibrate_fail;
    %if &_car_iml_ok ne 1 %then %do;
        %car_error(message=Calibrate IML computation did not complete.);
        %goto calibrate_fail;
    %end;

    %if &_car_error_rc %then %do;
        %car_error(message=Calibration failed. Outputs have been invalidated.);
        %goto calibrate_fail;
    %end;

    /* Publish the same public prediction/mean schema as Program 03. */
    data work._car_calvalues;
        merge work._car_grid(keep=usubjid) work._car_calnum;
    run;
    %car_step(context=Calibrated subject alignment);
    %if &_car_error_rc %then %goto calibrate_fail;
    proc sql;
        create table &out_predictions as
        select "%upcase(&model)" as model length=8, p.usubjid,
            d.trt as observed_trt, a.trt as target_trt, d.aval,
            p.mu_cal_raw as predicted,
            case when d.trt=a.trt then d.aval-p.mu_cal_raw else . end
                as observed_residual
        from work._car_calvalues p inner join work._car_data d on p.usubjid=d.usubjid
        inner join work._car_arms a on p.arm_index=a.arm_index
        order by p.usubjid,a.trt;
        create table &out_means as
        select model,target_trt,count(*) as n_total,
            sum(observed_trt=target_trt) as n_arm,
            mean(case when observed_trt=target_trt then aval else . end) as observed_mean,
            mean(predicted) as mean_pred_all,
            mean(case when observed_trt=target_trt then predicted else . end) as mean_pred_arm,
            mean(observed_residual) as mean_residual_arm,
            calculated mean_pred_all+calculated mean_residual_arm as aipw_mean
        from &out_predictions group by model,target_trt;
        create table &out_diagnostics as
        select "%upcase(&model)" as model length=8,a.trt as target_trt,
            d.n_arm,d.n_columns,d.effective_rank,d.n_aliased,
            d.estimability_error,d.recenter_delta,"%upcase(&joint)" as calibration length=5
        from work._car_caldiag d inner join work._car_arms a on d.arm_index=a.arm_index
        order by a.trt;
    quit;
    %car_step(context=Calibrated Program 03 schema publication, sql=YES);
    %if &_car_error_rc %then %goto calibrate_fail;
    %car_result_values(
        data   = &out_predictions,
        values = observed_trt target_trt aval predicted
    );
    %if &_car_error_rc %then %goto calibrate_fail;
    %car_result_values(
        data   = &out_means,
        values = target_trt n_total n_arm observed_mean mean_pred_all
            mean_pred_arm mean_residual_arm aipw_mean
    );
    %if &_car_error_rc %then %goto calibrate_fail;
    %car_result_values(
        data   = &out_diagnostics,
        values = target_trt n_arm n_columns effective_rank n_aliased estimability_error recenter_delta
    );
    %if &_car_error_rc %then %goto calibrate_fail;
    %put NOTE: [CAR] Calibration complete. Inspect &out_diagnostics for aliased columns.;
    %let car_rc = 0;
    %return;

%calibrate_fail:
    %car_clear(outputs=&_car_outputs);
    /* The error flag stays set; cleanup must finish instead of retrying. */
    %let car_rc = 1;
    %put ERROR: [CAR] Calibrate failed. Specified public outputs invalidated.;
%mend;
