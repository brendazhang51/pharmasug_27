/*
 * Run after loading car_common.sas and 04-07 in the SAME SAS session.
 * Self-contained analytic fixture, unrelated to the trial's actual design.
 * No files or RobinCar needed. Requires SAS/IML. Unexecuted in this workspace.
 * At completion CAR_TEST_FAILURES=0 is required. Review the SAS log as well.
 * Expected ERROR messages are emitted by the deliberate invalid-input tests.
 */
%global car_test_failures;
%let car_test_failures = 0;

%macro car_assert(condition, message);
    %if not %sysevalf(&condition, boolean) %then %do;
        %let car_test_failures = %eval(&car_test_failures + 1);
        %put ERROR: [CAR TEST] &message;
    %end;
    %else %put NOTE: [CAR TEST] PASS: &message;
%mend;

%macro car_smoke;
    %local checked mismatch;

    data work.smoke_data;
        length usubjid $12 strata $40;
        do trt = 0 to 1;
            do s = 0 to 1;
                strata = ifc(s = 0, 'S0', 'S1');
                do r = 1 to 8;
                    e = 2 * mod(r - 1, 4) - 3;
                    aval = 10 + 3 * trt + 2 * s + e;
                    usubjid = cats('T', trt, 'S', s, 'R', r);
                    output;
                end;
            end;
        end;
        keep usubjid trt strata aval;
    run;

    data work.smoke_arms;
        do arm_index = 1 to 2;
            trt = arm_index - 1;
            n_arm = 16;
            pi_hat = .5;
            output;
        end;
    run;

    data work.smoke_predictions;
        set work.smoke_data(keep = usubjid);
        do arm_index = 1 to 2;
            mu_tilde = 11 + 3 * (arm_index - 1);
            output;
        end;
    run;

    data work.smoke_estimates;
        set work.smoke_arms;
        estimate = 11 + 3 * trt;
    run;

    data work.smoke_coefficients;
        length contrast_id $12 label $80;
        contrast_id = 'DIFF1';
        label = '1 minus 0';
        null_value = 0;
        arm_index = 1;
        coefficient = - 1;
        output;
        arm_index = 2;
        coefficient = 1;
        output;
    run;

    %car_variance(
        data        = work.smoke_data,
        predictions = work.smoke_predictions,
        estimates   = work.smoke_estimates,
        arm_map     = work.smoke_arms,
        car_scheme  = simple
    );
    %car_assert(&car_rc = 0, Simple variance completed);
    %if &car_rc %then
        %return;

    /* ANOVA means have covariance 0, and Var(Y|A)/n_a = 6.4/16 = .4. */

    proc sql noprint;
        select count(*) into :mismatch trimmed
        from work.car_mean_vcov
        where abs(covariance - (case when arm_i = arm_j then .4 else 0 end)) > 1e-10;
    quit;

    %car_assert(&mismatch = 0, Simple covariance matches analytic result);
    %car_contrast(
        estimates    = work.smoke_estimates,
        coefficients = work.smoke_coefficients
    );
    %car_assert(&car_rc = 0, Contrast completed);
    %if &car_rc %then
        %return;

    proc sql noprint;
        select count(*) into :mismatch trimmed
        from work.car_contrast_results
        where abs(estimate - 3) > 1e-10 or abs(se - sqrt(.8)) > 1e-10;
    quit;

    %car_assert(&mismatch = 0, Difference and SE match analytic result);
    %car_variance(
        data        = work.smoke_data,
        predictions = work.smoke_predictions,
        estimates   = work.smoke_estimates,
        arm_map     = work.smoke_arms,
        car_scheme  = permuted-block,
        out_vcov    = work.smoke_pb_vcov
    );
    %car_assert(&car_rc = 0, PB variance completed);
    %if &car_rc %then
        %return;

    proc sql noprint;
        select count(*) into :mismatch trimmed
        from work.smoke_pb_vcov
        where abs(covariance - (case when arm_i = arm_j then .36875 else .03125 end)) > 1e-10;
    quit;

    %car_assert(&mismatch = 0, PB covariance matches analytic correction);
    %car_calibrate(
        data        = work.smoke_data,
        predictions = work.smoke_predictions,
        arm_map     = work.smoke_arms,
        joint       = YES
    );
    %car_assert(&car_rc = 0, Joint calibration handles aliased constant predictions);
    %if &car_rc %then
        %return;

    proc sql noprint;
        select count(*) into :mismatch trimmed
        from work.car_cal_estimates
        where abs(estimate - (11 + 3 * trt)) > 1e-10;
    quit;

    %car_assert(&mismatch = 0, Calibrated means match analytic result);
    %car_variance(
        data           = work.smoke_data,
        predictions    = work.car_cal_predictions,
        estimates      = work.car_cal_estimates,
        arm_map        = work.smoke_arms,
        car_scheme     = permuted-block,
        out_components = work.smoke_cal_components
    );
    %car_assert(&car_rc = 0, Calibrated PB variance completed);
    %if &car_rc %then
        %return;

    proc sql noprint;
        select count(*) into :mismatch trimmed
        from work.smoke_cal_components
        where abs(v_omega) > 1e-10;
    quit;

    %car_assert(&mismatch = 0, Joint calibration removes stratum residual correction);

    data work.smoke_ref;
        set work.smoke_pb_vcov;
    run;

    %car_validate(
        sas_data       = work.smoke_pb_vcov,
        reference_data = work.smoke_ref,
        keys           = arm_i arm_j,
        value          = covariance
    );
    %car_assert(&car_rc = 0, Identical keyed tables pass validation);

    data work.smoke_ref;
        set work.smoke_pb_vcov;
        if _n_ = 1 then covariance = covariance + .1;
    run;

    %car_validate(
        sas_data       = work.smoke_pb_vcov,
        reference_data = work.smoke_ref,
        keys           = arm_i arm_j,
        value          = covariance
    );
    %car_assert(&car_rc = 1, Numeric mismatch fails validation);

    data work.smoke_ref;
        set work.smoke_pb_vcov;
        if _n_ = 1 then delete;
    run;

    %car_validate(
        sas_data       = work.smoke_pb_vcov,
        reference_data = work.smoke_ref,
        keys           = arm_i arm_j,
        value          = covariance
    );
    %car_assert(&car_rc = 1, Missing reference key fails validation);

    data work.smoke_ref;
        set work.smoke_pb_vcov;
        output;
        if _n_ = 1 then output;
    run;

    %car_validate(
        sas_data       = work.smoke_pb_vcov,
        reference_data = work.smoke_ref,
        keys           = arm_i arm_j,
        value          = covariance
    );
    %car_assert(&car_rc = 1, Duplicate reference key fails validation);
    %car_variance(
        data        = work.smoke_data,
        predictions = work.smoke_predictions,
        estimates   = work.smoke_estimates,
        arm_map     = work.smoke_arms,
        car_scheme  = NOT_VERIFIED
    );
    %car_assert(&car_rc = 1, Unknown design is rejected);

    data work.smoke_incomplete;
        set work.smoke_predictions;
        if _n_ = 1 then delete;
    run;

    %car_calibrate(
        data        = work.smoke_data,
        predictions = work.smoke_incomplete,
        arm_map     = work.smoke_arms
    );
    %car_assert(&car_rc = 1, Incomplete prediction grid is rejected);
    %put NOTE: [CAR TEST] Finished with &car_test_failures failures.;
%mend;

%car_smoke;

/* Build independent unadjusted inputs for arbitrary fixture populations. */
%macro car_fixture_inputs(
    data   =,
    prefix =
);
    %local n;
    proc sql noprint;
        select count(*) into :n trimmed from &data;
        create table work._car_fixture_counts as
        select trt, count(*) as n_arm, mean(aval) as estimate
        from &data group by trt order by trt;
    quit;
    data work.&prefix._arms;
        set work._car_fixture_counts;
        arm_index = _n_;
        pi_hat = n_arm / &n;
    run;
    data work.&prefix._estimates;
        set work.&prefix._arms;
    run;
    proc sql;
        create table work.&prefix._predictions as
        select d.usubjid, a.arm_index, a.estimate as mu_tilde
        from &data d cross join work.&prefix._arms a;
    quit;
%mend;

%macro car_seed_variance;
    %car_variance(
        data        = work.smoke_data,
        predictions = work.smoke_predictions,
        estimates   = work.smoke_estimates,
        arm_map     = work.smoke_arms,
        car_scheme  = simple
    );
    %car_assert(&car_rc = 0, Variance seed succeeds);
%mend;

%macro car_assert_variance_cleared;
    %car_assert(&car_rc = 1, Expected variance failure);
    %car_assert(%sysfunc(exist(work.car_mean_vcov)) = 0, Old covariance removed);
    %car_assert(%sysfunc(exist(work.car_mean_inference)) = 0, Old inference removed);
    %car_assert(%sysfunc(exist(work.car_variance_components)) = 0, Old components removed);
    %car_assert(%sysfunc(exist(work.car_stratum_residuals)) = 0, Old residual summary removed);
%mend;

%macro car_extended_smoke;
    %local j value mismatch alpha_values fixture_dir close_rc;
    /* Three arms with unequal allocation: 16, 24, 32 subjects. */
    data work.smoke_three;
        length usubjid $12 strata $40;
        do trt = 0 to 2;
            do s = 0 to 1;
                strata = ifc(s = 0, 'S0', 'S1');
                do r = 1 to 8 + 4 * trt;
                    aval = 10 + 3 * trt + 2 * s + 2 * mod(r - 1, 4) - 3;
                    usubjid = cats('T', trt, 'S', s, 'R', put(r, z2.));
                    output;
                end;
            end;
        end;
        keep usubjid trt aval strata;
    run;
    %car_fixture_inputs(
        data   = work.smoke_three,
        prefix = three
    );
    %car_variance(
        data        = work.smoke_three,
        predictions = work.three_predictions,
        estimates   = work.three_estimates,
        arm_map     = work.three_arms,
        car_scheme  = simple,
        out_vcov    = work.smoke_three_cov
    );
    %car_assert(&car_rc = 0, Three unequal arms succeed);
    %if &car_rc %then %return;
    proc sql noprint;
        select count(*) into :mismatch trimmed
        from work.smoke_three_cov v inner join work.three_arms a on v.arm_i=a.arm_index
        where abs(v.covariance - (case when v.arm_i=v.arm_j
            then (6 * a.n_arm / (a.n_arm - 1)) / a.n_arm else 0 end)) > 1e-10;
    quit;
    %car_assert(&mismatch = 0, Unequal-arm covariance agrees with analytic values);

    /* Reverse all arm indices and deliberately scramble every input's rows. */
    data work.smoke_reverse_arms;
        set work.three_arms;
        arm_index = 4 - arm_index;
    run;
    data work.smoke_reverse_pred;
        set work.three_predictions;
        arm_index = 4 - arm_index;
    run;
    data work.smoke_reverse_est;
        set work.three_estimates;
        arm_index = 4 - arm_index;
    run;
    proc sort data=work.smoke_three; by descending usubjid; run;
    proc sort data=work.smoke_reverse_pred; by descending arm_index descending usubjid; run;
    %car_variance(
        data        = work.smoke_three,
        predictions = work.smoke_reverse_pred,
        estimates   = work.smoke_reverse_est,
        arm_map     = work.smoke_reverse_arms,
        car_scheme  = simple,
        out_vcov    = work.smoke_reverse_cov
    );
    %car_assert(&car_rc = 0, Reversed arm map and scrambled rows succeed);
    proc sql noprint;
        select count(*) into :mismatch trimmed
        from work.smoke_reverse_cov a full join work.smoke_three_cov b
        on a.arm_i=4-b.arm_i and a.arm_j=4-b.arm_j
        where missing(a.arm_i) or missing(b.arm_i) or abs(a.covariance-b.covariance)>1e-10;
    quit;
    %car_assert(&mismatch = 0, Covariance permutes with treatment labels);
    data work.smoke_reverse_coef;
        length contrast_id $12 label $80;
        contrast_id='DIFF1'; label='Arm 0 minus arm 2'; null_value=0;
        do arm_index=1 to 3;
            coefficient=(arm_index=3)-(arm_index=1); output;
        end;
    run;
    %car_contrast(
        estimates    = work.smoke_reverse_est,
        vcov         = work.smoke_reverse_cov,
        coefficients = work.smoke_reverse_coef
    );
    %car_assert(&car_rc = 0, Reversed reference-arm contrast succeeds);
    proc sql noprint;
        select count(*) into :mismatch trimmed from work.car_contrast_results
        where abs(estimate+6)>1e-10;
    quit;
    %car_assert(&mismatch = 0, Reversed reference-arm difference has correct sign);

    %car_calibrate(
        data        = work.smoke_data,
        predictions = work.smoke_predictions,
        arm_map     = work.smoke_arms,
        joint       = NO
    );
    %car_assert(&car_rc = 0, Linear calibration accepts constant aliased predictions);
    proc sql noprint;
        select count(*) into :mismatch trimmed from work.car_cal_estimates
        where abs(estimate-(11+3*trt))>1e-10;
    quit;
    %car_assert(&mismatch = 0, Linear calibrated means match analytic values);
    %put NOTE: [CAR TEST] Next calibration error is expected.;
    %car_calibrate(
        data        = work.smoke_data,
        predictions = work.smoke_incomplete,
        arm_map     = work.smoke_arms
    );
    %car_assert(&car_rc = 1, Calibration failure after success);
    %car_assert(%sysfunc(exist(work.car_cal_predictions))=0, Stale calibrated predictions removed);
    %car_assert(%sysfunc(exist(work.car_cal_estimates))=0, Stale calibrated means removed);
    %car_assert(%sysfunc(exist(work.car_cal_diagnostics))=0, Stale calibration diagnostics removed);

    /* Each invalid scalar is tested AFTER a successful call. */
    %let alpha_values = . bad -1 0 1 1e-300;
    %do j=1 %to 7;
        %car_seed_variance;
        %if &j=7 %then %let value=;
        %else %let value=%scan(&alpha_values, &j, %str( ));
        %put NOTE: [CAR TEST] Next invalid-alpha error is expected.;
        %car_variance(
            data        = work.smoke_data,
            predictions = work.smoke_predictions,
            estimates   = work.smoke_estimates,
            arm_map     = work.smoke_arms,
            car_scheme  = simple,
            alpha       = &value
        );
        %car_assert_variance_cleared;
    %end;
    %do j=1 %to 3;
        %car_seed_variance;
        %if &j=1 %then %do;
            data work.smoke_bad_pred;
                set work.smoke_predictions;
                mu_tilde=mu_tilde+1;
            run;
            data work.smoke_bad_est;
                set work.smoke_estimates;
                estimate=estimate+1;
            run;
            %car_variance(
                data        = work.smoke_data,
                predictions = work.smoke_bad_pred,
                estimates   = work.smoke_bad_est,
                arm_map     = work.smoke_arms,
                car_scheme  = simple
            );
        %end;
        %else %if &j=2 %then %do;
            data work.smoke_bad_est;
                set work.smoke_estimates;
                estimate=estimate+1;
            run;
            %car_variance(
                data        = work.smoke_data,
                predictions = work.smoke_predictions,
                estimates   = work.smoke_bad_est,
                arm_map     = work.smoke_arms,
                car_scheme  = simple
            );
        %end;
        %else %do;
            data work.smoke_bad_arms;
                set work.smoke_arms;
                pi_hat=.4;
            run;
            %car_variance(
                data        = work.smoke_data,
                predictions = work.smoke_predictions,
                estimates   = work.smoke_estimates,
                arm_map     = work.smoke_bad_arms,
                car_scheme  = simple
            );
        %end;
        %car_assert_variance_cleared;
    %end;

    %car_seed_variance;
    data work.smoke_overflow;
        set work.smoke_data;
        if mod(_n_, 2)=0 then aval=1e300;
        else aval=-1e300;
    run;
    %car_fixture_inputs(
        data   = work.smoke_overflow,
        prefix = overflow
    );
    %put NOTE: [CAR TEST] Next matrix-overflow failure is expected.;
    %car_variance(
        data        = work.smoke_overflow,
        predictions = work.overflow_predictions,
        estimates   = work.overflow_estimates,
        arm_map     = work.overflow_arms,
        car_scheme  = simple
    );
    %car_assert_variance_cleared;

    /* Empty treatment-by-stratum support: PB fails; joint extrapolation fails. */
    data work.smoke_empty_cell;
        set work.smoke_data;
        if trt=1 and strata='S0' then delete;
    run;
    %car_fixture_inputs(
        data   = work.smoke_empty_cell,
        prefix = emptycell
    );
    %car_variance(
        data        = work.smoke_empty_cell,
        predictions = work.emptycell_predictions,
        estimates   = work.emptycell_estimates,
        arm_map     = work.emptycell_arms,
        car_scheme  = permuted-block
    );
    %car_assert_variance_cleared;
    %car_calibrate(
        data        = work.smoke_empty_cell,
        predictions = work.emptycell_predictions,
        arm_map     = work.emptycell_arms,
        joint       = YES
    );
    %car_assert(&car_rc=1, Joint calibration rejects unsupported counterfactual strata);

    /* Name rejection must never delete an input or an unrelated old output. */
    data work.smoke_keep; marker=17; run;
    %car_calibrate(
        data            = work.smoke_data,
        predictions     = work.smoke_predictions,
        arm_map         = work.smoke_arms,
        out_predictions = work.smoke_keep,
        out_estimates   = work.smoke_keep
    );
    %car_assert(&car_rc=1, Duplicate outputs rejected);
    %car_assert(%sysfunc(exist(work.smoke_keep))=1, Unsafe name check preserves old outputs);
    %car_calibrate(
        data            = work.smoke_data,
        predictions     = work.smoke_predictions,
        arm_map         = work.smoke_arms,
        out_predictions = work.smoke_data
    );
    %car_assert(&car_rc=1, Input overwrite rejected);
    %car_assert(%sysfunc(exist(work.smoke_data))=1, Input population preserved);
    %car_calibrate(
        data            = work.smoke_data,
        predictions     = work.smoke_predictions,
        arm_map         = work.smoke_arms,
        out_predictions = work._car_forbidden
    );
    %car_assert(&car_rc=1, Reserved output rejected);

    libname smkalias "%sysfunc(pathname(work))";
    %car_calibrate(
        data            = work.smoke_data,
        predictions     = work.smoke_predictions,
        arm_map         = work.smoke_arms,
        out_predictions = smkalias.smoke_data
    );
    %car_assert(&car_rc=1, Input alias overwrite rejected);
    %car_assert(%sysfunc(exist(work.smoke_data))=1, Aliased input remains present);
    %car_calibrate(
        data            = work.smoke_data,
        predictions     = work.smoke_predictions,
        arm_map         = work.smoke_arms,
        out_predictions = work.smoke_keep,
        out_estimates   = smkalias.smoke_keep
    );
    %car_assert(&car_rc=1, Output aliases rejected before deletion);
    %car_assert(%sysfunc(exist(work.smoke_keep))=1, Aliased outputs preserved on name failure);
    libname smkalias clear;

    %do j=1 %to 6;
        %car_seed_variance;
        %car_contrast(
            estimates    = work.smoke_estimates,
            coefficients = work.smoke_coefficients
        );
        %car_assert(&car_rc=0, Contrast seed succeeds);
        data work.smoke_bad_cov;
            set work.car_mean_vcov;
            %if &j=1 %then %do;
                if arm_i=1 and arm_j=2 then covariance=.1;
            %end;
            %if &j=2 %then %do;
                if _n_=1 then delete;
            %end;
            %if &j=4 %then %do;
                if arm_i=arm_j then covariance=-.1;
            %end;
            %if &j=5 %then %do;
                if arm_i ne arm_j then covariance=.6;
            %end;
            %if &j=6 %then %do;
                if _n_=1 then covariance=.;
            %end;
        run;
        data work.smoke_bad_coef;
            set work.smoke_coefficients;
            %if &j=3 %then %do;
                if _n_=1 then coefficient=.;
            %end;
        run;
        %car_contrast(
            estimates    = work.smoke_estimates,
            vcov         = work.smoke_bad_cov,
            coefficients = work.smoke_bad_coef
        );
        %car_assert(&car_rc=1, Invalid covariance or coefficients rejected);
        %car_assert(%sysfunc(exist(work.car_contrast_results))=0, Stale contrasts removed);
        %car_assert(%sysfunc(exist(work.car_contrast_vcov))=0, Stale contrast covariance removed);
    %end;
    data work.smoke_zero_cov;
        do arm_i=1 to 2;
            do arm_j=1 to 2; covariance=0; output; end;
        end;
    run;
    %car_contrast(
        estimates    = work.smoke_estimates,
        vcov         = work.smoke_zero_cov,
        coefficients = work.smoke_coefficients
    );
    %car_assert(&car_rc=0, Zero-SE contrast is reported without dividing by zero);
    proc sql noprint;
        select count(*) into :mismatch trimmed from work.car_contrast_results
        where status ne 'ZERO_SE' or not missing(z) or not missing(p_value);
    quit;
    %car_assert(&mismatch=0, Zero-SE status and missing tests are explicit);

    data work.smoke_constant;
        set work.smoke_data;
        aval=10+3*trt;
    run;
    %car_fixture_inputs(
        data   = work.smoke_constant,
        prefix = constant
    );
    %car_variance(
        data        = work.smoke_constant,
        predictions = work.constant_predictions,
        estimates   = work.constant_estimates,
        arm_map     = work.constant_arms,
        car_scheme  = simple
    );
    %car_assert(&car_rc=0, Zero-SE mean inference succeeds);
    proc sql noprint;
        select count(*) into :mismatch trimmed from work.car_mean_inference
        where status ne 'ZERO_SE' or se ne 0 or not missing(z) or not missing(p_value);
    quit;
    %car_assert(&mismatch=0, Zero-SE means have explicit status);
    %car_calibrate(
        data        = work.smoke_data,
        predictions = work.smoke_predictions,
        arm_map     = work.smoke_arms
    );
    %car_assert(&car_rc=0, Calibration parameter-test seed succeeds);
    %car_calibrate(
        data        = work.smoke_data,
        predictions = work.smoke_predictions,
        arm_map     = work.smoke_arms,
        rank_tol    = bad
    );
    %car_assert(&car_rc=1, Invalid rank tolerance rejected without macro arithmetic);
    %car_assert(%sysfunc(exist(work.car_cal_predictions))=0, Invalid rank tolerance clears old predictions);

    /* Validation always replaces its previous success/failure report. */
    %do j=1 %to 4;
        %car_validate(
            sas_data       = work.smoke_pb_vcov,
            reference_data = work.smoke_pb_vcov,
            keys           = arm_i arm_j,
            value          = covariance
        );
        %car_assert(&car_rc=0, Validation report seed succeeds);
        data work.smoke_validation_ref;
            set work.smoke_pb_vcov;
            %if &j=1 %then %do; covariance=.; %end;
            %if &j=2 %then %do; delete; %end;
        run;
        %if &j=3 %then %do;
            %car_validate(
                sas_data       = work.smoke_pb_vcov,
                reference_data = work.smoke_validation_ref,
                keys           = arm_i arm_j,
                value          = covariance,
                atol           = bad
            );
        %end;
        %else %if &j=4 %then %do;
            %car_validate(
                sas_data       = work.smoke_pb_vcov,
                reference_data = work.smoke_validation_ref,
                keys           = arm_i arm_j,
                value          = covariance,
                rtol           =
            );
        %end;
        %else %do;
            %car_validate(
                sas_data       = work.smoke_pb_vcov,
                reference_data = work.smoke_validation_ref,
                keys           = arm_i arm_j,
                value          = covariance
            );
        %end;
        %car_assert(&car_rc=1, Missing/empty reference or invalid tolerance fails);
        %car_assert(%sysfunc(exist(work.car_validation_summary))=1, Fresh failure report exists);
    %end;
    %car_validate(
        sas_data       = work.smoke_pb_vcov,
        reference_data = work._car_no_reference,
        keys           = arm_i arm_j,
        value          = covariance
    );
    %car_assert(&car_rc=2, Absent reference is NOT_RUN);

    /* The suite's metadata rejection needs no RobinCar installation. */
    %if %sysmacexist(car_test_inference) %then %do;
        %let fixture_dir=%sysfunc(pathname(work))/car_smoke_reference;
        %if not %sysfunc(fileexist(&fixture_dir)) %then
            %let fixture_dir=%sysfunc(dcreate(car_smoke_reference, %sysfunc(pathname(work))));
        filename _carfx "&fixture_dir./settings.csv";
        data _null_;
            file _carfx;
            put 'model,car_scheme,variance_type,joint,add_x,alpha,arms,n,package_version,package_remote_sha,input_md5';
            put 'ANCOVA,simple,1,YES,,0.05,"0,1",32,1.2.0,not-recorded,00000000000000000000000000000000';
        run;
        filename _carfx clear;
        data work.smoke_settings;
            length model $8 car_scheme $14 joint $3 add_x $256;
            model='ANCOVA'; car_scheme='simple'; joint='YES'; add_x='';
            variance_type=1; alpha=.1; n=32;
        run;
        data work.smoke_metadata;
            set work.smoke_data;
            x1_analysis=0;
            x3_analysis=0;
        run;
        %car_test_inference(
            reference_dir = &fixture_dir,
            data          = work.smoke_metadata,
            settings      = work.smoke_settings,
            arm_map       = work.smoke_arms
        );
        %car_assert(&car_suite_rc=1, Mismatched alpha settings reject the reference suite);
    %end;
    %else %car_assert(0, Load test_inference.sas before the smoke test);
    %put NOTE: [CAR TEST] Extended suite finished with &car_test_failures failures.;
%mend;

%car_extended_smoke;
