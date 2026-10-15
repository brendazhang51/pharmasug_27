/*
 * Inference smoke tests: analytic fixtures and invalid-input protection.
 * Run after loading 00_car_common.sas and 04-07 in the SAME SAS session.
 * Self-contained analytic fixture, unrelated to the trial's actual design.
 * No files or RobinCar needed. Requires SAS/IML. See doc/validation_status.md.
 * At completion CAR_TEST_FAILURES=0 is required. Review the SAS log as well.
 * Expected ERROR messages are emitted by the deliberate invalid-input tests.
 */
%global car_test_failures;
%let car_test_failures = 0;

%macro car_assert(condition=, message=);
    %if not %sysevalf(&condition, boolean) %then %do;
        %let car_test_failures = %eval(&car_test_failures + 1);
        %put ERROR: [CAR TEST] &message;
    %end;
    %else %put NOTE: [CAR TEST] PASS: &message;
%mend;

/* Abort before creating fixtures when a required macro has not been loaded. */
%macro car_smoke_require;
    %local j name;
    %do j=1 %to 6;
        %let name=%scan(car_error car_calibrate car_variance car_contrast
            car_validate car_test_inference,&j);
        %if not %sysmacexist(&name) %then %do;
            %let car_test_failures=1;
            %put ERROR: [CAR TEST] Required macro &name is not loaded.;
            %abort cancel;
        %end;
    %end;
%mend;
%car_smoke_require;

/* Independent unadjusted fixtures, published directly in Program 03 format. */
%macro car_fixture_inputs(data=, prefix=);
    %local n;
    proc sql noprint;
        select count(*) into :n trimmed from &data;
        create table work.&prefix._arms as
        select trt,count(*) as n_arm,mean(aval) as observed_mean
        from &data group by trt order by trt;
    quit;
    data work.&prefix._means;
        length model $8;
        set work.&prefix._arms;
        model='ANCOVA';
        target_trt=trt;
        n_total=&n;
        mean_pred_all=observed_mean;
        mean_pred_arm=observed_mean;
        mean_residual_arm=0;
        aipw_mean=observed_mean;
        drop trt;
    run;
    proc sql;
        create table work.&prefix._predictions as
        select m.model,d.usubjid,d.trt as observed_trt,m.target_trt,d.aval,
            m.mean_pred_all as predicted,
            case when d.trt=m.target_trt then d.aval-m.mean_pred_all else . end
                as observed_residual
        from &data d cross join work.&prefix._means m;
    quit;
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

    %car_fixture_inputs(data=work.smoke_data, prefix=smoke);

    data work.smoke_coefficients;
        length contrast_id $12 label $80;
        contrast_id = 'DIFF1';
        label = '1 minus 0';
        null_value = 0;
        target_trt = 0;
        coefficient = - 1;
        output;
        target_trt = 1;
        coefficient = 1;
        output;
    run;

    %car_variance(
        data        = work.smoke_data,
        predictions = work.smoke_predictions,
        means       = work.smoke_means,
        car_scheme  = simple
    );
    %car_assert(condition=&car_rc = 0, message=Simple variance completed);
    %if &car_rc %then
        %return;

    /* ANOVA means have covariance 0, and Var(Y|A)/n_a = 6.4/16 = .4. */

    proc sql noprint;
        select count(*) into :mismatch trimmed
        from work.car_mean_vcov
        where abs(covariance - (case when target_trt_i = target_trt_j then .4 else 0 end)) > 1e-10;
    quit;

    %car_assert(condition=&mismatch = 0, message=Simple covariance matches analytic result);
    %car_contrast(
        means        = work.smoke_means,
        coefficients = work.smoke_coefficients
    );
    %car_assert(condition=&car_rc = 0, message=Contrast completed);
    %if &car_rc %then
        %return;

    proc sql noprint;
        select count(*) into :mismatch trimmed
        from work.car_contrast_results
        where abs(estimate - 3) > 1e-10 or abs(se - sqrt(.8)) > 1e-10;
    quit;

    %car_assert(condition=&mismatch = 0, message=Difference and SE match analytic result);
    %car_variance(
        data        = work.smoke_data,
        predictions = work.smoke_predictions,
        means       = work.smoke_means,
        car_scheme  = permuted-block,
        out_vcov    = work.smoke_pb_vcov
    );
    %car_assert(condition=&car_rc = 0, message=PB variance completed);
    %if &car_rc %then
        %return;

    proc sql noprint;
        select count(*) into :mismatch trimmed
        from work.smoke_pb_vcov
        where abs(covariance - (case when target_trt_i = target_trt_j then .36875 else .03125 end)) > 1e-10;
    quit;

    %car_assert(condition=&mismatch = 0, message=PB covariance matches analytic correction);
    %car_calibrate(
        data        = work.smoke_data,
        predictions = work.smoke_predictions,
        means       = work.smoke_means,
        joint       = YES
    );
    %car_assert(condition=&car_rc = 0, message=Joint calibration handles aliased constant predictions);
    %if &car_rc %then
        %return;

    proc sql noprint;
        select count(*) into :mismatch trimmed
        from work.car_cal_means
        where abs(aipw_mean - (11 + 3 * target_trt)) > 1e-10;
    quit;

    %car_assert(condition=&mismatch = 0, message=Calibrated means match analytic result);
    %car_variance(
        data           = work.smoke_data,
        predictions    = work.car_cal_predictions,
        means          = work.car_cal_means,
        car_scheme     = permuted-block,
        out_components = work.smoke_cal_components
    );
    %car_assert(condition=&car_rc = 0, message=Calibrated PB variance completed);
    %if &car_rc %then
        %return;

    proc sql noprint;
        select count(*) into :mismatch trimmed
        from work.smoke_cal_components
        where abs(v_omega) > 1e-10;
    quit;

    %car_assert(condition=&mismatch = 0, message=Joint calibration removes stratum residual correction);

    data work.smoke_ref;
        set work.smoke_pb_vcov;
    run;

    %car_validate(
        sas_data       = work.smoke_pb_vcov,
        reference_data = work.smoke_ref,
        keys           = target_trt_i target_trt_j,
        value          = covariance
    );
    %car_assert(condition=&car_rc = 0, message=Identical keyed tables pass validation);

    data work.smoke_ref;
        set work.smoke_pb_vcov;
        if _n_ = 1 then covariance = covariance + .1;
    run;

    %car_validate(
        sas_data       = work.smoke_pb_vcov,
        reference_data = work.smoke_ref,
        keys           = target_trt_i target_trt_j,
        value          = covariance
    );
    %car_assert(condition=&car_rc = 1, message=Numeric mismatch fails validation);

    data work.smoke_ref;
        set work.smoke_pb_vcov;
        if _n_ = 1 then delete;
    run;

    %car_validate(
        sas_data       = work.smoke_pb_vcov,
        reference_data = work.smoke_ref,
        keys           = target_trt_i target_trt_j,
        value          = covariance
    );
    %car_assert(condition=&car_rc = 1, message=Missing reference key fails validation);

    data work.smoke_ref;
        set work.smoke_pb_vcov;
        output;
        if _n_ = 1 then output;
    run;

    %car_validate(
        sas_data       = work.smoke_pb_vcov,
        reference_data = work.smoke_ref,
        keys           = target_trt_i target_trt_j,
        value          = covariance
    );
    %car_assert(condition=&car_rc = 1, message=Duplicate reference key fails validation);
    %car_variance(
        data        = work.smoke_data,
        predictions = work.smoke_predictions,
        means       = work.smoke_means,
        car_scheme  = NOT_VERIFIED
    );
    %car_assert(condition=&car_rc = 1, message=Unknown design is rejected);

    data work.smoke_incomplete;
        set work.smoke_predictions;
        if _n_ = 1 then delete;
    run;

    %car_calibrate(
        data        = work.smoke_data,
        predictions = work.smoke_incomplete,
        means       = work.smoke_means
    );
    %car_assert(condition=&car_rc = 1, message=Incomplete prediction grid is rejected);
    %put NOTE: [CAR TEST] Finished with &car_test_failures failures.;
%mend;

%car_smoke;

%macro car_seed_variance;
    %car_variance(
        data        = work.smoke_data,
        predictions = work.smoke_predictions,
        means       = work.smoke_means,
        car_scheme  = simple
    );
    %car_assert(condition=&car_rc = 0, message=Variance seed succeeds);
%mend;

%macro car_assert_variance_cleared;
    %car_assert(condition=&car_rc = 1, message=Expected variance failure);
    %car_assert(condition=%sysfunc(exist(work.car_mean_vcov)) = 0, message=Old covariance removed);
    %car_assert(condition=%sysfunc(exist(work.car_mean_inference)) = 0, message=Old inference removed);
    %car_assert(condition=%sysfunc(exist(work.car_variance_components)) = 0, message=Old components removed);
    %car_assert(condition=%sysfunc(exist(work.car_stratum_residuals)) = 0, message=Old residual summary removed);
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
        means       = work.three_means,
        car_scheme  = simple,
        out_vcov    = work.smoke_three_cov
    );
    %car_assert(condition=&car_rc = 0, message=Three unequal arms succeed);
    %if &car_rc %then %return;
    proc sql noprint;
        select count(*) into :mismatch trimmed
        from work.smoke_three_cov v inner join work.three_arms a on v.target_trt_i=a.trt
        where abs(v.covariance - (case when v.target_trt_i=v.target_trt_j
            then (6 * a.n_arm / (a.n_arm - 1)) / a.n_arm else 0 end)) > 1e-10;
    quit;
    %car_assert(condition=&mismatch = 0, message=Unequal-arm covariance agrees with analytic values);

    /* Shuffle inputs; select the highest treatment as the reference. */
    proc sort data=work.smoke_three; by descending usubjid; run;
    proc sort data=work.three_predictions out=work.smoke_reverse_pred;
        by descending target_trt descending usubjid;
    run;
    proc sort data=work.three_means out=work.smoke_reverse_means;
        by descending target_trt;
    run;
    %car_variance(
        data        = work.smoke_three,
        predictions = work.smoke_reverse_pred,
        means       = work.smoke_reverse_means,
        car_scheme  = simple,
        out_vcov    = work.smoke_reverse_cov
    );
    %car_assert(condition=&car_rc=0, message=Shuffled native treatment labels succeed);
    proc sql noprint;
        select count(*) into :mismatch trimmed
        from work.smoke_reverse_cov a full join work.smoke_three_cov b
        on a.target_trt_i=b.target_trt_i and a.target_trt_j=b.target_trt_j
        where missing(a.target_trt_i) or missing(b.target_trt_i)
            or abs(a.covariance-b.covariance)>1e-10;
    quit;
    %car_assert(condition=&mismatch=0, message=Covariance is stable under source row permutations);
    data work.smoke_reverse_coef;
        length contrast_id $12 label $80;
        contrast_id='DIFF1'; label='Arm 0 minus arm 2'; null_value=0;
        do target_trt=0 to 2;
            coefficient=(target_trt=0)-(target_trt=2); output;
        end;
    run;
    %car_contrast(
        means        = work.smoke_reverse_means,
        vcov         = work.smoke_reverse_cov,
        coefficients = work.smoke_reverse_coef
    );
    %car_assert(condition=&car_rc=0, message=Different reference-arm contrast succeeds);
    proc sql noprint;
        select count(*) into :mismatch trimmed from work.car_contrast_results
        where abs(estimate+6)>1e-10;
    quit;
    %car_assert(condition=&mismatch=0, message=Highest-reference treatment difference has correct sign);

    /* Actual labels need not be consecutive or start at zero. */
    data work.smoke_labels;
        set work.smoke_three;
        trt=10+10*trt*(trt+1);
    run;
    %car_fixture_inputs(data=work.smoke_labels, prefix=labels);
    %car_variance(
        data        = work.smoke_labels,
        predictions = work.labels_predictions,
        means       = work.labels_means,
        car_scheme  = simple,
        out_vcov    = work.smoke_label_cov
    );
    %car_assert(condition=&car_rc=0, message=Nonconsecutive treatment labels succeed);
    proc sql noprint;
        select count(*) into :mismatch trimmed
        from work.smoke_label_cov a full join work.smoke_three_cov b
        on a.target_trt_i=10+10*b.target_trt_i*(b.target_trt_i+1)
            and a.target_trt_j=10+10*b.target_trt_j*(b.target_trt_j+1)
        where missing(a.target_trt_i) or missing(b.target_trt_i)
            or abs(a.covariance-b.covariance)>1e-10;
    quit;
    %car_assert(condition=&mismatch=0, message=Covariance maps using actual treatment labels);
    data work.smoke_label_coef;
        length contrast_id $12 label $80;
        contrast_id='DIFF1'; label='70 minus 10'; null_value=0;
        do target_trt=10,30,70;
            coefficient=(target_trt=70)-(target_trt=10); output;
        end;
    run;
    %car_contrast(
        means        = work.labels_means,
        vcov         = work.smoke_label_cov,
        coefficients = work.smoke_label_coef
    );
    %car_assert(condition=&car_rc=0, message=Contrast accepts nonconsecutive treatment labels);
    proc sql noprint;
        select count(*) into :mismatch trimmed from work.car_contrast_results
        where abs(estimate-6)>1e-10;
    quit;
    %car_assert(condition=&mismatch=0, message=Native-label contrast agrees with analytic difference);

    %car_calibrate(
        data        = work.smoke_data,
        predictions = work.smoke_predictions,
        means       = work.smoke_means,
        joint       = NO
    );
    %car_assert(condition=&car_rc = 0, message=Linear calibration accepts constant aliased predictions);
    proc sql noprint;
        select count(*) into :mismatch trimmed from work.car_cal_means
        where abs(aipw_mean-(11+3*target_trt))>1e-10;
    quit;
    %car_assert(condition=&mismatch = 0, message=Linear calibrated means match analytic values);
    %put NOTE: [CAR TEST] Next calibration error is expected.;
    %car_calibrate(
        data        = work.smoke_data,
        predictions = work.smoke_incomplete,
        means       = work.smoke_means
    );
    %car_assert(condition=&car_rc = 1, message=Calibration failure after success);
    %car_assert(condition=%sysfunc(exist(work.car_cal_predictions))=0, message=Stale calibrated predictions removed);
    %car_assert(condition=%sysfunc(exist(work.car_cal_means))=0, message=Stale calibrated means removed);
    %car_assert(condition=%sysfunc(exist(work.car_cal_diagnostics))=0, message=Stale calibration diagnostics removed);

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
            means       = work.smoke_means,
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
                predicted=predicted+1;
            run;
            data work.smoke_bad_est;
                set work.smoke_means;
                aipw_mean=aipw_mean+1;
            run;
            %car_variance(
                data        = work.smoke_data,
                predictions = work.smoke_bad_pred,
                means       = work.smoke_bad_est,
                car_scheme  = simple
            );
        %end;
        %else %if &j=2 %then %do;
            data work.smoke_bad_est;
                set work.smoke_means;
                aipw_mean=aipw_mean+1;
            run;
            %car_variance(
                data        = work.smoke_data,
                predictions = work.smoke_predictions,
                means       = work.smoke_bad_est,
                car_scheme  = simple
            );
        %end;
        %else %do;
            data work.smoke_bad_means;
                set work.smoke_means;
                n_arm=n_arm+1;
            run;
            %car_variance(
                data        = work.smoke_data,
                predictions = work.smoke_predictions,
                means       = work.smoke_bad_means,
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
        means       = work.overflow_means,
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
        means       = work.emptycell_means,
        car_scheme  = permuted-block
    );
    %car_assert_variance_cleared;
    %car_calibrate(
        data        = work.smoke_empty_cell,
        predictions = work.emptycell_predictions,
        means       = work.emptycell_means,
        joint       = YES
    );
    %car_assert(condition=&car_rc=1, message=Joint calibration rejects unsupported counterfactual strata);

    /* Name rejection must never delete an input or an unrelated old output. */
    data work.smoke_keep; marker=17; run;
    %car_calibrate(
        data            = work.smoke_data,
        predictions     = work.smoke_predictions,
        means           = work.smoke_means,
        out_predictions = work.smoke_keep,
        out_means       = work.smoke_keep
    );
    %car_assert(condition=&car_rc=1, message=Duplicate outputs rejected);
    %car_assert(condition=%sysfunc(exist(work.smoke_keep))=1, message=Unsafe name check preserves old outputs);
    %car_calibrate(
        data            = work.smoke_data,
        predictions     = work.smoke_predictions,
        means           = work.smoke_means,
        out_predictions = work.smoke_data
    );
    %car_assert(condition=&car_rc=1, message=Input overwrite rejected);
    %car_assert(condition=%sysfunc(exist(work.smoke_data))=1, message=Input population preserved);
    %car_calibrate(
        data            = work.smoke_data,
        predictions     = work.smoke_predictions,
        means           = work.smoke_means,
        out_predictions = work._car_forbidden
    );
    %car_assert(condition=&car_rc=1, message=Reserved output rejected);

    libname smkalias "%sysfunc(pathname(work))";
    %car_calibrate(
        data            = work.smoke_data,
        predictions     = work.smoke_predictions,
        means           = work.smoke_means,
        out_predictions = smkalias.smoke_data
    );
    %car_assert(condition=&car_rc=1, message=Input alias overwrite rejected);
    %car_assert(condition=%sysfunc(exist(work.smoke_data))=1, message=Aliased input remains present);
    %car_calibrate(
        data            = work.smoke_data,
        predictions     = work.smoke_predictions,
        means           = work.smoke_means,
        out_predictions = work.smoke_keep,
        out_means       = smkalias.smoke_keep
    );
    %car_assert(condition=&car_rc=1, message=Output aliases rejected before deletion);
    %car_assert(condition=%sysfunc(exist(work.smoke_keep))=1, message=Aliased outputs preserved on name failure);
    libname smkalias clear;

    %do j=1 %to 8;
        %car_seed_variance;
        %car_contrast(
            means        = work.smoke_means,
            coefficients = work.smoke_coefficients
        );
        %car_assert(condition=&car_rc=0, message=Contrast seed succeeds);
        data work.smoke_bad_cov;
            set work.car_mean_vcov;
            %if &j=1 %then %do;
                if target_trt_i=0 and target_trt_j=1 then covariance=.1;
            %end;
            %if &j=2 %then %do;
                if _n_=1 then delete;
            %end;
            %if &j=4 %then %do;
                if target_trt_i=target_trt_j then covariance=-.1;
            %end;
            %if &j=5 %then %do;
                if target_trt_i ne target_trt_j then covariance=.6;
            %end;
            %if &j=6 %then %do;
                if _n_=1 then covariance=.;
            %end;
            %if &j=8 %then %do;
                model='ANOVA';
            %end;
        run;
        data work.smoke_bad_coef;
            set work.smoke_coefficients;
            %if &j=3 %then %do;
                if _n_=1 then coefficient=.;
            %end;
            %if &j=7 %then %do;
                if _n_=1 then target_trt=99;
            %end;
        run;
        %car_contrast(
            means        = work.smoke_means,
            vcov         = work.smoke_bad_cov,
            coefficients = work.smoke_bad_coef
        );
        %car_assert(condition=&car_rc=1, message=Invalid covariance or coefficients rejected);
        %car_assert(condition=%sysfunc(exist(work.car_contrast_results))=0, message=Stale contrasts removed);
        %car_assert(condition=%sysfunc(exist(work.car_contrast_vcov))=0, message=Stale contrast covariance removed);
    %end;
    data work.smoke_zero_cov;
        length model $8; model='ANCOVA';
        do target_trt_i=0 to 1;
            do target_trt_j=0 to 1; covariance=0; output; end;
        end;
    run;
    %car_contrast(
        means        = work.smoke_means,
        vcov         = work.smoke_zero_cov,
        coefficients = work.smoke_coefficients
    );
    %car_assert(condition=&car_rc=0, message=Zero-SE contrast is reported without dividing by zero);
    proc sql noprint;
        select count(*) into :mismatch trimmed from work.car_contrast_results
        where status ne 'ZERO_SE' or not missing(z) or not missing(p_value);
    quit;
    %car_assert(condition=&mismatch=0, message=Zero-SE status and missing tests are explicit);

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
        means       = work.constant_means,
        car_scheme  = simple
    );
    %car_assert(condition=&car_rc=0, message=Zero-SE mean inference succeeds);
    proc sql noprint;
        select count(*) into :mismatch trimmed from work.car_mean_inference
        where status ne 'ZERO_SE' or se ne 0 or not missing(z) or not missing(p_value);
    quit;
    %car_assert(condition=&mismatch=0, message=Zero-SE means have explicit status);
    %car_calibrate(
        data        = work.smoke_data,
        predictions = work.smoke_predictions,
        means       = work.smoke_means
    );
    %car_assert(condition=&car_rc=0, message=Calibration parameter-test seed succeeds);
    %car_calibrate(
        data        = work.smoke_data,
        predictions = work.smoke_predictions,
        means       = work.smoke_means,
        rank_tol    = bad
    );
    %car_assert(condition=&car_rc=1, message=Invalid rank tolerance rejected without macro arithmetic);
    %car_assert(condition=%sysfunc(exist(work.car_cal_predictions))=0, message=Invalid rank tolerance clears old predictions);

    /* Validation always replaces its previous success/failure report. */
    %do j=1 %to 4;
        %car_validate(
            sas_data       = work.smoke_pb_vcov,
            reference_data = work.smoke_pb_vcov,
            keys           = target_trt_i target_trt_j,
            value          = covariance
        );
        %car_assert(condition=&car_rc=0, message=Validation report seed succeeds);
        data work.smoke_validation_ref;
            set work.smoke_pb_vcov;
            %if &j=1 %then %do; covariance=.; %end;
            %if &j=2 %then %do; delete; %end;
        run;
        %if &j=3 %then %do;
            %car_validate(
                sas_data       = work.smoke_pb_vcov,
                reference_data = work.smoke_validation_ref,
                keys           = target_trt_i target_trt_j,
                value          = covariance,
                atol           = bad
            );
        %end;
        %else %if &j=4 %then %do;
            %car_validate(
                sas_data       = work.smoke_pb_vcov,
                reference_data = work.smoke_validation_ref,
                keys           = target_trt_i target_trt_j,
                value          = covariance,
                rtol           =
            );
        %end;
        %else %do;
            %car_validate(
                sas_data       = work.smoke_pb_vcov,
                reference_data = work.smoke_validation_ref,
                keys           = target_trt_i target_trt_j,
                value          = covariance
            );
        %end;
        %car_assert(condition=&car_rc=1, message=Missing/empty reference or invalid tolerance fails);
        %car_assert(condition=%sysfunc(exist(work.car_validation_summary))=1, message=Fresh failure report exists);
    %end;
    %car_validate(
        sas_data       = work.smoke_pb_vcov,
        reference_data = work._car_no_reference,
        keys           = target_trt_i target_trt_j,
        value          = covariance
    );
    %car_assert(condition=&car_rc=2, message=Absent reference is NOT_RUN);

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
            settings      = work.smoke_settings
        );
        %car_assert(condition=&car_suite_rc=1, message=Mismatched alpha settings reject the reference suite);
    %end;
    %else %car_assert(condition=0, message=Load test_inference_reference.sas before the smoke test);
    %put NOTE: [CAR TEST] Extended suite finished with &car_test_failures failures.;
%mend;

%car_extended_smoke;

%put NOTE: CAR_TEST_FAILURES=&CAR_TEST_FAILURES;
/* Native Program 03 contract: multiple models and nonzero residual shifts. */
%macro _car_native_seed(model=ANCOVA);
    %car_variance(
        data           = work.smoke_three,
        predictions    = work.native_source_pred,
        means          = work.native_source_means,
        model          = &model,
        car_scheme     = simple,
        out_vcov       = work.native_cov,
        out_inference  = work.native_inference,
        out_components = work.native_components,
        out_residuals  = work.native_residuals
    );
    %car_assert(condition=&car_rc=0, message=Native AIPW seed succeeds);
%mend;

%macro _car_native_tests;
    %local j mismatch native_model;
    %if not %sysmacexist(car_assert) or not %sysmacexist(car_inputs)
        or not %sysfunc(exist(work.smoke_three)) %then %do;
        %put ERROR: Build and submit the full run/run.sas entry point.;
        %abort cancel;
    %end;
    /* All source subjects have arm mean 11+3*TRT. The ANCOVA fixture uses
       raw prediction 9+3*TARGET_TRT, so its residual shift is exactly 2.
       ANOVA raw predictions equal the arm means and have shift zero. */
    data work.native_source_pred;
        length model $8;
        set work.smoke_three;
        observed_trt=trt;
        do model='ANOVA','ANCOVA';
            do target_trt=0 to 2;
                predicted=11+3*target_trt-2*(model='ANCOVA');
                observed_residual=.;
                if observed_trt=target_trt then observed_residual=aval-predicted;
                output;
            end;
        end;
        keep model usubjid observed_trt target_trt aval predicted observed_residual;
    run;
    proc sort data=work.native_source_pred;
        by descending usubjid descending target_trt model;
    run;
    data work.native_source_means;
        length model $8;
        do model='ANOVA','ANCOVA';
            do target_trt=2 to 0 by -1;
                n_total=72;
                n_arm=16+8*target_trt;
                observed_mean=11+3*target_trt;
                mean_pred_all=observed_mean-2*(model='ANCOVA');
                mean_pred_arm=mean_pred_all;
                mean_residual_arm=2*(model='ANCOVA');
                aipw_mean=observed_mean;
                output;
            end;
        end;
    run;
    data work.native_pred_before;
        set work.native_source_pred;
    run;
    data work.native_means_before;
        set work.native_source_means;
    run;
    %_car_native_seed;
    %if &car_rc %then %return;
    proc sql noprint;
        select count(*) into :mismatch trimmed from work.native_inference
        where target_trt not in (0,1,2) or n_arm ne 16+8*target_trt
            or abs(aipw_mean-(11+3*target_trt))>1e-12;
    quit;
    %car_assert(condition=&mismatch=0, message=Native inference selects ANCOVA and re-centers nonzero residuals);
    %car_calibrate(
        data        = work.smoke_three,
        predictions = work.native_source_pred,
        means       = work.native_source_means
    );
    %car_assert(condition=&car_rc=0, message=Calibration directly accepts native multi-model sources);
    %car_variance(
        data        = work.smoke_three,
        predictions = work.car_cal_predictions,
        means       = work.car_cal_means,
        car_scheme  = simple
    );
    %car_assert(condition=&car_rc=0, message=Calibrated outputs directly reuse the Program 03 schema);
    proc compare base=work.native_pred_before compare=work.native_source_pred noprint;
    run;
    %let mismatch=&sysinfo;
    %car_assert(condition=&mismatch=0, message=Native input leaves Program 03 prediction sources unchanged);
    proc compare base=work.native_means_before compare=work.native_source_means noprint;
    run;
    %let mismatch=&sysinfo;
    %car_assert(condition=&mismatch=0, message=Native input leaves Program 03 mean sources unchanged);

    %do j=1 %to 12;
        %_car_native_seed;
        %if &car_rc %then %return;
        %let native_model=ANCOVA;
        %if &j=8 %then %let native_model=INVALID;
        data work.native_bad_pred;
            set work.native_source_pred;
            %if &j=1 %then %do;
                if model='ANCOVA' and target_trt=0 then predicted=.;
            %end;
            %if &j=2 %then %do;
                if model='ANCOVA' then do;
                    observed_trt=99;
                    observed_residual=.;
                end;
            %end;
            %if &j=3 %then %do;
                if model='ANCOVA' and target_trt=0 then do;
                    target_trt=99;
                    observed_residual=.;
                end;
            %end;
            %if &j=4 %then %do;
                output;
                if model='ANCOVA' and target_trt=0 then output;
            %end;
            %if &j=5 %then %do;
                if model='ANCOVA' and observed_trt=target_trt then observed_residual=.;
            %end;
            %if &j=7 %then %do;
                if model='ANCOVA' then delete;
            %end;
            %if &j=11 %then %do;
                if model='ANCOVA' and observed_trt ne target_trt then observed_residual=0;
            %end;
            %if &j=12 %then %do;
                if model='ANCOVA' then aval=aval+1;
            %end;
        run;
        data work.native_bad_means;
            set work.native_source_means;
            %if &j=6 %then %do;
                if model='ANCOVA' then aipw_mean=aipw_mean+1;
            %end;
            %if &j=7 %then %do;
                if model='ANCOVA' then delete;
            %end;
            %if &j=9 %then %do;
                output;
                if model='ANCOVA' and target_trt=0 then output;
            %end;
            %if &j=10 %then %do;
                if model='ANCOVA' then mean_pred_arm=.;
            %end;
        run;
        %put NOTE: [CAR TEST] Next Native AIPW error is expected for case &j..;
        %car_variance(
            data           = work.smoke_three,
            predictions    = work.native_bad_pred,
            means          = work.native_bad_means,
            model          = &native_model,
            car_scheme     = simple,
            out_vcov       = work.native_cov,
            out_inference  = work.native_inference,
            out_components = work.native_components,
            out_residuals  = work.native_residuals
        );
        %car_assert(condition=&car_rc=1, message=Invalid native AIPW input is rejected);
        %car_assert(condition=%sysfunc(exist(work.native_cov))=0, message=Stale native covariance removed);
        %car_assert(condition=%sysfunc(exist(work.native_inference))=0, message=Stale native inference removed);
        %car_assert(condition=%sysfunc(exist(work.native_components))=0, message=Stale native components removed);
        %car_assert(condition=%sysfunc(exist(work.native_residuals))=0, message=Stale native residuals removed);
    %end;
    %_car_native_seed(model=ANOVA);
    %if &car_rc %then %return;
    proc sql noprint;
        select count(*) into :mismatch trimmed from work.native_inference
        where abs(aipw_mean-(11+3*target_trt))>1e-12;
    quit;
    %car_assert(condition=&mismatch=0, message=Native input can select a different source model);
    %put NOTE: [CAR TEST] Native input suite finished with &car_test_failures total failures.;
%mend;
%_car_native_tests;
