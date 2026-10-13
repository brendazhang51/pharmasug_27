/*
 * Joint / linear calibration. Load car_common.sas first.
 * One analysis per call. Input predictions: usubjid arm_index mu_tilde.
 * All prediction arms enter each arm-specific OLS. Joint strata are saturated.
 * Sources: RobinCar/R/robincar-calibrate.R and utils-adjust.R.
 * Initial implementation; SAS runtime and RobinCar equivalence pending.
 */

%macro car_calibrate(
    data            = work.analysis_data,
    predictions     = work.car_aipw_predictions,
    arm_map         = work.car_arm_map,
    joint           = YES,
    add_x           =,
    rank_tol        = 1e-10,
    out_predictions = work.car_cal_predictions,
    out_estimates   = work.car_cal_estimates,
    out_diagnostics = work.car_cal_diagnostics
);
    %global car_rc _car_error_rc;
    %let car_rc = 1;
    %let _car_error_rc = 0;
    %if not %sysmacexist(car_inputs) %then %do;
        %let car_rc = 1;
        %put ERROR: [CAR] Run car_common.sas first.;
        %return;
    %end;

    %local _car_outputs _car_iml_ok;
    %let _car_outputs = &out_predictions &out_estimates &out_diagnostics;
    %car_output_guard(
        inputs   = &data &predictions &arm_map,
        outputs  = &_car_outputs,
        expected = 3
    );
    %if &_car_error_rc %then %return;
    %car_clear(outputs=&_car_outputs);
    %if &_car_error_rc %then %goto calibrate_fail;

    %if %upcase(&joint) ne YES and %upcase(&joint) ne NO %then %do;
        %car_error(JOINT must be YES or NO.);
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
        arm_map     = &arm_map,
        add_x       = &add_x
    );
    %if &_car_error_rc %then
        %goto calibrate_fail;

    %let _car_iml_ok = 0;

    proc iml;
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
                stop;
            end;
            call svd(u, q, v, xa);
            if any(q = .) | any(u = .) | any(v = .) then do;
                print "ERROR: [CAR] SVD produced missing values.";
                stop;
            end;
            keep = loc(q > &rank_tol * max(q));
            r = ncol(keep);
            if r = 0 then do;
                print "ERROR: [CAR] Calibration has zero effective rank." a;
                stop;
            end;
            if nrow(xa) <= r then do;
                print "ERROR: [CAR] Calibration has no residual degrees of freedom." a r;
                stop;
            end;
            vr = v[, keep];
            ur = u[, keep];
            beta = vr * diag(1 / q[keep]) * ur` * ya;
            if any(beta = .) then do;
                print "ERROR: [CAR] Missing calibration coefficients." a;
                stop;
            end;

            /* Reject predictions outside the fitted row space. */
            error = max(abs(x - x * vr * vr`));
            if error = . | error > 100 * &rank_tol then do;
                print
                    "ERROR: [CAR] Counterfactual calibration predictions are not estimable." a error;
                stop;
            end;
            raw[, a] = x * beta;
            delta = mean(ya - raw[idx, a]);
            centered[, a] = raw[, a] + delta;
            if any(raw[, a] = .) | any(centered[, a] = .) then do;
                print "ERROR: [CAR] Missing calibrated predictions." a;
                stop;
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
    quit;
    %car_step(context=Calibrate step);
    %if &_car_error_rc %then %goto calibrate_fail;
    %if &_car_iml_ok ne 1 %then %do;
        %car_error(Calibrate IML computation did not complete.);
        %goto calibrate_fail;
    %end;

    %if &_car_error_rc %then %do;
        %car_error(Calibration failed. Outputs have been invalidated.);
        %goto calibrate_fail;
    %end;

    data &out_predictions;
        merge work._car_grid(keep = usubjid) work._car_calnum;
    run;
    %car_step(context=Calibrate step);
    %if &_car_error_rc %then %goto calibrate_fail;

    data &out_estimates;
        set work._car_calest;
    run;
    %car_step(context=Calibrate step);
    %if &_car_error_rc %then %goto calibrate_fail;

    data &out_diagnostics;
        set work._car_caldiag;
        length calibration $5;
        calibration = "%upcase(&joint)";
    run;
    %car_step(context=Calibrate step);
    %if &_car_error_rc %then %goto calibrate_fail;

    %car_result_values(
        data   = &out_predictions,
        values = arm_index mu_cal_raw mu_tilde
    );
    %if &_car_error_rc %then %goto calibrate_fail;
    %car_result_values(
        data   = &out_estimates,
        values = arm_index trt n_arm estimate
    );
    %if &_car_error_rc %then %goto calibrate_fail;
    %car_result_values(
        data   = &out_diagnostics,
        values = arm_index n_arm n_columns effective_rank n_aliased estimability_error
            recenter_delta
    );
    %if &_car_error_rc %then %goto calibrate_fail;
    %put NOTE: [CAR] Calibration complete. Inspect &out_diagnostics for aliased columns.;
    %let car_rc = 0;
    %return;

%calibrate_fail:
    %car_clear(outputs=&_car_outputs);
    %if &_car_error_rc %then %goto calibrate_fail;
    %let car_rc = 1;
    %put ERROR: [CAR] Calibrate failed. Specified public outputs invalidated.;
%mend;
