/*
 * Use the generated run/run_inference.sas for configuration and dependencies.
 * This bridge example fits ANCOVA and constructs the proposed 02/03 tables.
 * It does not replace general-purpose 02/03 implementations.
 * Supports the numeric arms retained by 01, including all three source arms.
 * Requires SAS/STAT and SAS/IML. See doc/validation_status.md for verification scope.
 * Pass the documented design explicitly. Example:
 * %car_worked_example(car_scheme=simple);
 * That is an algorithm demonstration unless the actual design is verified.
 * R comparison: use model ANCOVA and the identical arm subset/order.
 */

%macro car_worked_example(
    car_scheme =,
    alpha      = 0.05
);
    %local n k _car_example_outputs _car_macro_index _car_required_macro;
    %global car_rc _car_error_rc;
    %let car_rc = 1;
    %let _car_error_rc = 0;
    %if not %sysmacexist(car_output_guard) %then %do;
        %let car_rc=1;
        %put ERROR: [CAR] Load 00_car_common.sas before the example.;
        %return;
    %end;
    /* Check dependencies before fitting or invalidating previous outputs. */
    %do _car_macro_index=1 %to 3;
        %let _car_required_macro=%scan(car_calibrate car_variance car_contrast,
            &_car_macro_index);
        %if not %sysmacexist(&_car_required_macro) %then %do;
            %let _car_error_rc=1;
            %put ERROR: [CAR] Required macro &_car_required_macro is not loaded. Load Programs 04-06 in this SAS session.;
            %return;
        %end;
    %end;
    %let _car_example_outputs = work.car_run_settings work.car_arm_map work.car_predictions
        work.car_aipw_predictions work.car_arm_estimates work.car_mean_vcov
        work.car_mean_inference work.car_variance_components work.car_stratum_residuals
        work.car_contrast_coefficients work.car_contrast_results work.car_contrast_vcov
        work.car_cal_predictions work.car_cal_estimates work.car_cal_diagnostics
        work.car_cal_vcov work.car_cal_inference work.car_cal_components
        work.car_cal_stratum_residuals work.car_cal_contrasts work.car_cal_contrast_vcov;
    %car_output_guard(
        inputs   = work.analysis_data,
        outputs  = &_car_example_outputs,
        expected = 21
    );
    %if &_car_error_rc %then %return;
    %car_clear(outputs=&_car_example_outputs);
    %if &_car_error_rc %then %goto example_fail;
    %car_alpha(value=%superq(alpha));
    %if &_car_error_rc %then %goto example_fail;
    %if %length(%superq(car_scheme)) = 0 %then %do;
        %car_error(message=Supply the documented CAR_SCHEME before running this example.);
        %goto example_fail;
    %end;

    %car_require(
        data      = work.analysis_data,
        vars      = usubjid trt aval strata x1_analysis x3_analysis,
        numeric   = trt aval x1_analysis x3_analysis,
        character = usubjid strata
    );
    %if &_car_error_rc %then
        %goto example_fail;

    proc sql noprint;
        select count(*) into :n trimmed
        from work.analysis_data;
        create table work._car_demo_arms as
        select trt, count(*) as n_arm
        from work.analysis_data
        group by trt
        order by trt;
    quit;
    %car_step(
        context = Example step,
        sql     = YES
    );
    %if &_car_error_rc %then %goto example_fail;

    %if &n = 0 %then %do;
        %car_error(message=Analysis population is empty.);
        %goto example_fail;
    %end;

    data work.car_arm_map;
        set work._car_demo_arms;
        arm_index = _n_;
        pi_hat = n_arm / &n;
    run;

    proc glm data = work.analysis_data;
        class trt;
        model aval = trt x1_analysis x3_analysis;
        store work._car_demo_model;
    quit;

    %if &syserr > 4 %then %do;
        %car_error(message=ANCOVA fitting failed.);
        %goto example_fail;
    %end;

    proc sql;
        create table work._car_demo_score as
        select
            d.usubjid,
            d.aval,
            d.strata,
            d.x1_analysis,
            d.x3_analysis,
            d.trt as observed_trt,
            a.trt,
            a.arm_index
        from work.analysis_data d
        cross join work.car_arm_map a
        order by d.usubjid, a.arm_index;
    quit;
    %car_step(
        context = Example step,
        sql     = YES
    );
    %if &_car_error_rc %then %goto example_fail;

    proc plm restore = work._car_demo_model;
        score data = work._car_demo_score out = work.car_predictions predicted = mu_raw;
    run;

    %if &syserr > 4 %then %do;
        %car_error(message=ANCOVA scoring failed.);
        %goto example_fail;
    %end;

    proc sql;
        create table work._car_demo_delta as
        select arm_index, mean(aval - mu_raw) as delta
        from work.car_predictions
        where trt = observed_trt
        group by arm_index;
        create table work.car_aipw_predictions as
        select p.usubjid, p.arm_index, p.mu_raw, p.mu_raw + d.delta as mu_tilde
        from work.car_predictions p
        left join work._car_demo_delta d
        on p.arm_index = d.arm_index
        order by p.usubjid, p.arm_index;
        create table work.car_arm_estimates as
        select a.arm_index, a.trt, a.n_arm, mean(p.mu_tilde) as estimate
        from work.car_arm_map a
        left join work.car_aipw_predictions p
        on a.arm_index = p.arm_index
        group by a.arm_index, a.trt, a.n_arm;
    quit;
    %car_step(
        context = Example step,
        sql     = YES
    );
    %if &_car_error_rc %then %goto example_fail;

    %car_variance(
        car_scheme = &car_scheme,
        alpha      = &alpha
    );
    %if &_car_error_rc %then
        %goto example_fail;

    /* Active-minus-first-arm coefficients, explicitly including zeros. */

    proc sql noprint;
        select count(*) into :k trimmed
        from work.car_arm_map;
    quit;
    %car_step(
        context = Example step,
        sql     = YES
    );
    %if &_car_error_rc %then %goto example_fail;

    data work.car_contrast_coefficients;
        length contrast_id $12 label $80;
        do target = 2 to &k;
            contrast_id = cats('DIFF', target - 1);
            label = cats('Arm index ', target, ' minus arm index 1');
            null_value = 0;
            do arm_index = 1 to &k;
                coefficient = (arm_index = target) - (arm_index = 1);
                output;
            end;
        end;
        drop target;
    run;

    %car_contrast(alpha=&alpha);
    %if &_car_error_rc %then
        %goto example_fail;
    %car_calibrate;
    %if &_car_error_rc %then
        %goto example_fail;
    %car_variance(
        predictions    = work.car_cal_predictions,
        estimates      = work.car_cal_estimates,
        car_scheme     = &car_scheme,
        alpha          = &alpha,
        out_vcov       = work.car_cal_vcov,
        out_inference  = work.car_cal_inference,
        out_components = work.car_cal_components,
        out_residuals  = work.car_cal_stratum_residuals
    );
    %if &_car_error_rc %then
        %goto example_fail;
    %car_contrast(
        estimates = work.car_cal_estimates,
        vcov      = work.car_cal_vcov,
        alpha     = &alpha,
        out       = work.car_cal_contrasts,
        out_vcov  = work.car_cal_contrast_vcov
    );
    %if &_car_error_rc %then
        %goto example_fail;

    proc print data = work.car_mean_inference;
    run;
    %car_step(context=Example step);
    %if &_car_error_rc %then %goto example_fail;

    proc print data = work.car_contrast_results;
    run;
    %car_step(context=Example step);
    %if &_car_error_rc %then %goto example_fail;

    proc print data = work.car_cal_inference;
    run;
    %car_step(context=Example step);
    %if &_car_error_rc %then %goto example_fail;

    proc print data = work.car_cal_contrasts;
    run;
    %car_step(context=Example step);
    %if &_car_error_rc %then %goto example_fail;

    /* Saved settings identify this exact bridge run for independent validation. */
    data work.car_run_settings;
        length model $8 car_scheme $14 joint $3 add_x $256;
        model = 'ANCOVA';
        car_scheme = lowcase("&car_scheme");
        variance_type = 1;
        alpha = &alpha;
        joint = 'YES';
        add_x = '';
        n = &n;
    run;
    %car_step(context=Run settings publication);
    %if &_car_error_rc %then %goto example_fail;
    %let car_rc = 0;
    %put NOTE: [CAR] Computation complete. Invoke CAR_TEST_INFERENCE to compare reference results.;
    %return;

%example_fail:
    %car_clear(outputs=&_car_example_outputs);
    %let car_rc=1;
%mend;
