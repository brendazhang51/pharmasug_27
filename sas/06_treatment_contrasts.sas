/*
 * Linear contrasts of treatment means. Load car_common.sas first.
 * Coefficients: character contrast_id/label, numeric arm_index/coefficient/
 * null_value. Include ALL arm indices, including zero coefficients.
 * Sources: RobinCar/R/robincar-contrast.R. Initial implementation; unvalidated.
 */

%macro car_contrast(
    estimates    = work.car_arm_estimates,
    vcov         = work.car_mean_vcov,
    coefficients = work.car_contrast_coefficients,
    alpha        = 0.05,
    out          = work.car_contrast_results,
    out_vcov     = work.car_contrast_vcov
);
    %global car_rc _car_error_rc;
    %let car_rc = 1;
    %let _car_error_rc = 0;
    %local k m bad rows;
    %if not %sysmacexist(car_require) %then %do;
        %let car_rc = 1;
        %put ERROR: [CAR] Run car_common.sas first.;
        %return;
    %end;

    %local _car_outputs _car_iml_ok;
    %let _car_outputs = &out &out_vcov;
    %car_output_guard(
        inputs   = &estimates &vcov &coefficients,
        outputs  = &_car_outputs,
        expected = 2
    );
    %if &_car_error_rc %then %return;
    %car_clear(outputs=&_car_outputs);
    %if &_car_error_rc %then %goto contrast_fail;

    %car_alpha(value=%superq(alpha));
    %if &_car_error_rc %then %goto contrast_fail;

    %car_require(
        data    = &estimates,
        vars    = arm_index estimate,
        numeric = arm_index estimate
    );
    %car_require(
        data    = &vcov,
        vars    = arm_i arm_j covariance,
        numeric = arm_i arm_j covariance
    );
    %car_require(
        data      = &coefficients,
        vars      = contrast_id label arm_index coefficient null_value,
        numeric   = arm_index coefficient null_value,
        character = contrast_id label
    );
    %if &_car_error_rc %then
        %goto contrast_fail;
    %car_unique(
        data = &estimates,
        keys = arm_index
    );
    %car_unique(
        data = &vcov,
        keys = arm_i arm_j
    );
    %car_unique(
        data = &coefficients,
        keys = contrast_id arm_index
    );
    %if &_car_error_rc %then
        %goto contrast_fail;

    proc sort data = &estimates out = work._car_est;
        by arm_index;
    run;
    %car_step(context=Contrast step);
    %if &_car_error_rc %then %goto contrast_fail;

    proc sort data = &coefficients out = work._car_coef;
        by contrast_id arm_index;
    run;
    %car_step(context=Contrast step);
    %if &_car_error_rc %then %goto contrast_fail;

    proc sort data = &vcov out = work._car_cov;
        by arm_i arm_j;
    run;
    %car_step(context=Contrast step);
    %if &_car_error_rc %then %goto contrast_fail;

    proc sql noprint;
        select count(*) into :k trimmed
        from work._car_est;
        select count(distinct contrast_id) into :m trimmed
        from work._car_coef;
        select count(*) into :rows trimmed
        from work._car_cov;
    quit;
    %car_step(
        context = Contrast step,
        sql     = YES
    );
    %if &_car_error_rc %then %goto contrast_fail;

    %if &k < 2 or &m = 0 or &rows ne %eval(&k * &k) %then %do;
        %car_error(Empty contrasts or incomplete mean covariance.);
        %goto contrast_fail;
    %end;

    data work._car_bad;
        set work._car_est;
        if arm_index ne _n_ or missing(estimate);
    run;
    %car_step(context=Contrast step);
    %if &_car_error_rc %then %goto contrast_fail;

    proc sql noprint;
        select count(*) into :bad trimmed
        from work._car_bad;
    quit;
    %car_step(
        context = Contrast step,
        sql     = YES
    );
    %if &_car_error_rc %then %goto contrast_fail;

    %if &bad > 0 %then
        %car_error(Estimate indices must be 1 through K with finite means.);

    proc sql noprint;
        select count(*) into :bad trimmed
        from work._car_cov
        where arm_i < 1
            or arm_i > &k
            or arm_i ne int(arm_i)
            or arm_j < 1
            or arm_j > &k
            or arm_j ne int(arm_j)
            or missing(covariance);
    quit;
    %car_step(
        context = Contrast step,
        sql     = YES
    );
    %if &_car_error_rc %then %goto contrast_fail;

    %if &bad > 0 %then
        %car_error(Covariance keys or values are invalid.);

    proc sql;
        create table work._car_contrast_check as
        select
            contrast_id,
            count(*) as n_rows,
            count(distinct label) as n_labels,
            count(distinct null_value) as n_nulls,
            sum(
                missing(label)
                or missing(coefficient)
                or missing(null_value)
                or arm_index < 1
                or arm_index > &k
                or arm_index ne int(arm_index)
            ) as n_bad
        from work._car_coef
        group by contrast_id;
    quit;
    %car_step(
        context = Contrast step,
        sql     = YES
    );
    %if &_car_error_rc %then %goto contrast_fail;

    proc sql noprint;
        select count(*) into :bad trimmed
        from work._car_contrast_check
        where n_rows ne &k
            or n_labels ne 1
            or n_nulls ne 1
            or n_bad > 0;
    quit;
    %car_step(
        context = Contrast step,
        sql     = YES
    );
    %if &_car_error_rc %then %goto contrast_fail;

    %if &bad > 0 %then
        %car_error(Each contrast needs K coefficients with one complete label and null value.);
    %if &_car_error_rc %then
        %goto contrast_fail;

    data work._car_labels;
        set work._car_coef;
        by contrast_id;
        if first.contrast_id;
        keep contrast_id label null_value;
    run;
    %car_step(context=Contrast step);
    %if &_car_error_rc %then %goto contrast_fail;

    %let _car_iml_ok = 0;

    proc iml;
        use work._car_est;
        read all var {estimate} into theta;
        close work._car_est;

        use work._car_cov;
        read all var {covariance} into cv;
        close work._car_cov;

        use work._car_coef;
        read all var {coefficient} into cf;
        close work._car_coef;

        v = shape(cv, &k, &k);
        c = shape(cf, &m, &k);
        if any(v = .) | any(c = .) | any(theta = .) then do;
            print "ERROR: [CAR] Missing contrast inputs.";
            stop;
        end;
        tol = 1e-10 * max(1, max(abs(v)));
        if max(abs(v - v`)) > tol then do;
            print "ERROR: [CAR] Mean covariance is not symmetric.";
            stop;
        end;
        v = (v + v`) / 2;
        call eigen(e, ev, v);
        if any(e = .) | min(e) < -tol | min(vecdiag(v)) < 0 then do;
            print "ERROR: [CAR] Mean covariance is not positive semidefinite.";
            stop;
        end;
        delta = c * theta;
        vc = c * v * c`;
        vc = (vc + vc`) / 2;
        if any(delta = .) | any(vc = .) then do;
            print "ERROR: [CAR] Missing contrast estimate or covariance.";
            stop;
        end;
        if min(vecdiag(vc)) < 0 then do;
            print "ERROR: [CAR] Negative contrast variance.";
            stop;
        end;
        result = delta || sqrt(vecdiag(vc));
        create work._car_cnum from result
            [colname = {estimate se}];
        append from result;
        close work._car_cnum;

        use work._car_labels;
        read all var {contrast_id} into labels;
        close work._car_labels;
        contrast_i = repeat(labels, 1, &m);
        contrast_j = repeat(labels`, &m, 1);
        contrast_i = shape(contrast_i, &m * &m, 1);
        contrast_j = shape(contrast_j, &m * &m, 1);
        covariance = shape(vc, &m * &m, 1);
        create work._car_cvcov var {contrast_i contrast_j covariance};
        append;
        close work._car_cvcov;

        call symputx("_car_iml_ok", 1, "L");
    quit;
    %car_step(context=Contrast step);
    %if &_car_error_rc %then %goto contrast_fail;
    %if &_car_iml_ok ne 1 %then %do;
        %car_error(Contrast IML computation did not complete.);
        %goto contrast_fail;
    %end;

    %if &_car_error_rc %then %do;
        %car_error(Contrast computation failed. Outputs have been invalidated.);
        %goto contrast_fail;
    %end;

    data &out;
        merge work._car_labels work._car_cnum;
        length status $16;
        alpha = &alpha;
        lcl = estimate - quantile('NORMAL', 1 - alpha / 2) * se;
        ucl = estimate + quantile('NORMAL', 1 - alpha / 2) * se;
        if se > 0 then do;
            z = (estimate - null_value) / se;
            p_value = 2 * cdf('NORMAL', -abs(z));
            status = 'OK';
        end;
        else status = 'ZERO_SE';
    run;
    %car_step(context=Contrast step);
    %if &_car_error_rc %then %goto contrast_fail;

    data &out_vcov;
        set work._car_cvcov;
    run;
    %car_step(context=Contrast step);
    %if &_car_error_rc %then %goto contrast_fail;

    %car_result_values(
        data      = &out,
        values    = estimate se lcl ucl,
        inference = YES
    );
    %if &_car_error_rc %then %goto contrast_fail;
    %car_result_values(
        data   = &out_vcov,
        values = covariance
    );
    %if &_car_error_rc %then %goto contrast_fail;
    %put NOTE: [CAR] Linear contrasts complete. CIs are marginal and unadjusted.;
    %let car_rc = 0;
    %return;

%contrast_fail:
    %car_clear(outputs=&_car_outputs);
    %if &_car_error_rc %then %goto contrast_fail;
    %let car_rc = 1;
    %put ERROR: [CAR] Contrast failed. Specified public outputs invalidated.;
%mend;
