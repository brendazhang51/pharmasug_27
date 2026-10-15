/*==========================================================================
 Program : 06_treatment_contrasts.sas
 Project : Robust Covariate Adjustment under CAR (SAS / RobinCar)
 Purpose : Estimate linear treatment contrasts from the complete mean
           covariance.
 Status  : See doc/validation_status.md for verified configurations.

 INPUT  : Treatment means, complete mean covariance and long-form contrast
          coefficients including every arm.
 OUTPUT : Contrast estimates, SEs, CIs, z tests, p-values and covariance;
          CAR_RC.

 IMPORTANT:
 - Requires SAS/IML; load 00_car_common.sas first. Loading defines macros only.
 - Use C theta and C V C-prime, retaining all off-diagonal covariance.
 - Each contrast must specify all arms, including zero coefficients.
 - Confidence intervals and p-values are marginal normal approximations.
 - Reference: RobinCar/R/robincar-contrast.R.
==========================================================================*/

/*==========================================================================
 Macro   : car_contrast
 Purpose : Calculate linear contrasts and their full covariance matrix.

 INPUT  : Program 03 MEANS, MODEL, VCOV, COEFFICIENTS and ALPHA.
 OUTPUT : OUT and OUT_VCOV; CAR_RC.

 IMPORTANT:
 - Coefficient keys are CONTRAST_ID and TARGET_TRT; retain all arm rows.
 - Zero SE is reported as ZERO_SE with missing z and p-value.
==========================================================================*/
%macro car_contrast(
    means        = work.aipw_means,
    model        = ANCOVA,
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
        %put ERROR: [CAR] Run 00_car_common.sas first.;
        %return;
    %end;

    %local _car_outputs _car_iml_ok;
    %let _car_outputs = &out &out_vcov;
    %car_output_guard(
        inputs   = &means &vcov &coefficients,
        outputs  = &_car_outputs,
        expected = 2
    );
    %if &_car_error_rc %then %return;
    %car_clear(outputs=&_car_outputs);
    %if &_car_error_rc %then %goto contrast_fail;

    %car_alpha(value=%superq(alpha));
    %if &_car_error_rc %then %goto contrast_fail;

    %car_select_means(means=&means, model=%superq(model));
    %if &_car_error_rc %then %goto contrast_fail;
    %car_require(
        data      = &vcov,
        vars      = model target_trt_i target_trt_j covariance,
        numeric   = target_trt_i target_trt_j covariance,
        character = model
    );
    %car_require(
        data      = &coefficients,
        vars      = contrast_id label target_trt coefficient null_value,
        numeric   = target_trt coefficient null_value,
        character = contrast_id label
    );
    %if &_car_error_rc %then %goto contrast_fail;
    data work._car_est;
        set work._car_means;
        arm_index=_n_;
        estimate=aipw_mean;
    run;
    %car_step(context=Private contrast treatment ordering);
    %if &_car_error_rc %then %goto contrast_fail;
    data work._car_selected_cov;
        set &vcov;
        where upcase(model)="%upcase(&model)";
    run;
    %car_step(context=Contrast covariance model selection);
    %if &_car_error_rc %then %goto contrast_fail;
    %car_unique(data=work._car_selected_cov, keys=target_trt_i target_trt_j);
    %car_unique(data=&coefficients, keys=contrast_id target_trt);
    %if &_car_error_rc %then %goto contrast_fail;
    proc sql;
        create table work._car_cov as
        select a.arm_index as arm_i,b.arm_index as arm_j,v.covariance
        from work._car_selected_cov v
        left join work._car_est a on v.target_trt_i=a.target_trt
        left join work._car_est b on v.target_trt_j=b.target_trt
        order by arm_i,arm_j;
        create table work._car_coef as
        select c.*,a.arm_index from &coefficients c
        left join work._car_est a on c.target_trt=a.target_trt
        order by c.contrast_id,a.arm_index;
    quit;
    %car_step(context=Contrast target treatment alignment, sql=YES);
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
        %car_error(message=Empty contrasts or incomplete mean covariance.);
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
        %car_error(message=Estimate indices must be 1 through K with finite means.);

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
        %car_error(message=Covariance keys or values are invalid.);

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
        %car_error(message=Each contrast needs K coefficients with one complete label and null value.);
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
        /* Keep the complete calculation in one module: RETURN skips all
           remaining matrix work and leaves _CAR_IML_OK=0 on failure. */
        start _car_compute;
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
                return;
            end;
            tol = 1e-10 * max(1, max(abs(v)));
            if max(abs(v - v`)) > tol then do;
                print "ERROR: [CAR] Mean covariance is not symmetric.";
                return;
            end;
            v = (v + v`) / 2;
            call eigen(e, ev, v);
            if any(e = .) | min(e) < -tol | min(vecdiag(v)) < 0 then do;
                print "ERROR: [CAR] Mean covariance is not positive semidefinite.";
                return;
            end;
            delta = c * theta;
            vc = c * v * c`;
            vc = (vc + vc`) / 2;
            if any(delta = .) | any(vc = .) then do;
                print "ERROR: [CAR] Missing contrast estimate or covariance.";
                return;
            end;
            if min(vecdiag(vc)) < 0 then do;
                print "ERROR: [CAR] Negative contrast variance.";
                return;
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
        finish;
        run _car_compute;
    quit;
    %car_step(context=Contrast step);
    %if &_car_error_rc %then %goto contrast_fail;
    %if &_car_iml_ok ne 1 %then %do;
        %car_error(message=Contrast IML computation did not complete.);
        %goto contrast_fail;
    %end;

    %if &_car_error_rc %then %do;
        %car_error(message=Contrast computation failed. Outputs have been invalidated.);
        %goto contrast_fail;
    %end;

    data &out;
        merge work._car_labels work._car_cnum;
        length model $8 status $16;
        model="%upcase(&model)";
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
        length model $8;
        model="%upcase(&model)";
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
    /* The error flag stays set; cleanup must finish instead of retrying. */
    %let car_rc = 1;
    %put ERROR: [CAR] Contrast failed. Specified public outputs invalidated.;
%mend;
