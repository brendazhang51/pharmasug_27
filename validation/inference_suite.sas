/*
 * Load 00_car_common.sas and 07, then run the continuous example successfully.
 * Load this file to define the suite; it does not run on submission.
 * Example: %car_test_inference(reference_dir=/your/server/reference);
 * References are from robincar_reference.R, with identical settings/population.
 * See doc/validation_status.md for verified configurations and pending runs.
 */

/* Explicit schemas avoid PROC IMPORT inference and reject key truncation. */
%macro _car_reference_import(
    file =,
    kind =,
    out  =
);
    %local bad value header;
    %if not %sysfunc(fileexist(%superq(file))) %then %do;
        %car_error(message=Required reference file is absent: &file.);
        %return;
    %end;
    %if &kind = analysis %then
        %let header=usubjid,trt,aval,strata,x1_analysis,x3_analysis;
    %else %if &kind = settings %then
        %let header=model,car_scheme,variance_type,joint,add_x,alpha,arms,n,package_version,package_remote_sha,input_md5;
    %else %if &kind = arm_map %then %let header=arm_index,trt,n_arm,pi_hat;
    %else %if &kind = predictions %then %let header=usubjid,arm_index,mu_tilde;
    %else %if &kind = raw %then %let header=usubjid,arm_index,mu_raw;
    %else %if &kind = cal_raw %then %let header=usubjid,arm_index,mu_cal_raw;
    %else %if &kind = estimates %then %let header=arm_index,estimate;
    %else %if &kind = inference %then %let header=arm_index,estimate,se,lcl,ucl;
    %else %if &kind = vcov %then %let header=arm_i,arm_j,covariance;
    %else %if &kind = contrasts %then %let header=contrast_id,estimate,se,lcl,ucl,p_value;
    %else %if &kind = contrast_vcov %then %let header=contrast_i,contrast_j,covariance;
    %else %do;
        %car_error(message=Unknown reference schema.);
        %return;
    %end;
    %let bad=1;
    data _null_;
        infile "&file" obs=1 lrecl=32767;
        input;
        valid = lowcase(compress(strip(_infile_), '"')) = symget('header');
        call symputx('bad', not valid, 'L');
    run;
    %car_step(context=Reference header check);
    %if &_car_error_rc %then %return;
    %if &bad %then %do;
        %car_error(message=Reference CSV header does not match its explicit schema.);
        %return;
    %end;
    data &out;
        infile "&file" dsd dlm=',' firstobs=2 lrecl=32767 truncover;
        length _bad 8 _raw_id _raw_label $32767;
        _bad = 0;
        %if &kind = analysis %then %do;
            length usubjid $12 strata $40 trt aval x1_analysis x3_analysis 8;
            input _raw_id :$32767. trt :best32. aval :best32.
                _raw_label :$32767. x1_analysis :best32. x3_analysis :best32.;
            if lengthn(_raw_id) > 12 or lengthn(_raw_label) > 40 then _bad = 1;
            usubjid = _raw_id;
            strata = _raw_label;
            if cmiss(usubjid, strata) then _bad = 1;
        %end;
        %else %if &kind = settings %then %do;
            length model $8 car_scheme $14 joint $3 add_x $256 arms $256
                package_version $16 package_remote_sha $64 input_md5 $32;
            length variance_type alpha n 8;
            length _raw_model _raw_scheme _raw_joint _raw_x _raw_arms
                _raw_version _raw_sha _raw_md5 $32767;
            /* R settings.csv order is fixed by the exporter. */
            input _raw_model :$32767. _raw_scheme :$32767. variance_type :best32.
                _raw_joint :$32767. _raw_x :$32767. alpha :best32. _raw_arms :$32767.
                n :best32. _raw_version :$32767. _raw_sha :$32767. _raw_md5 :$32767.;
            if lengthn(_raw_model) > 8 or lengthn(_raw_scheme) > 14
                or lengthn(_raw_joint) > 3 or lengthn(_raw_x) > 256
                or lengthn(_raw_arms) > 256 or lengthn(_raw_version) > 16
                or lengthn(_raw_sha) > 64 or lengthn(_raw_md5) > 32 then _bad = 1;
            model = _raw_model;
            car_scheme = _raw_scheme;
            joint = _raw_joint;
            add_x = _raw_x;
            arms = _raw_arms;
            package_version = _raw_version;
            package_remote_sha = _raw_sha;
            input_md5 = _raw_md5;
            if cmiss(model, car_scheme, joint, arms, package_version, input_md5) then _bad = 1;
            drop _raw_model _raw_scheme _raw_joint _raw_x _raw_arms
                _raw_version _raw_sha _raw_md5;
        %end;
        %else %if &kind = arm_map %then %do;
            length arm_index trt n_arm pi_hat 8;
            input arm_index :best32. trt :best32. n_arm :best32. pi_hat :best32.;
        %end;
        %else %if &kind = predictions or &kind = raw or &kind = cal_raw %then %do;
            length usubjid $12 arm_index 8;
            %if &kind = predictions %then %let value = mu_tilde;
            %else %if &kind = raw %then %let value = mu_raw;
            %else %let value = mu_cal_raw;
            length &value 8;
            input _raw_id :$32767. arm_index :best32. &value :best32.;
            if lengthn(_raw_id) > 12 then _bad = 1;
            usubjid = _raw_id;
            if missing(usubjid) then _bad = 1;
        %end;
        %else %if &kind = estimates %then %do;
            length arm_index estimate 8;
            input arm_index :best32. estimate :best32.;
        %end;
        %else %if &kind = inference %then %do;
            length arm_index estimate se lcl ucl 8;
            input arm_index :best32. estimate :best32. se :best32. lcl :best32. ucl :best32.;
        %end;
        %else %if &kind = vcov %then %do;
            length arm_i arm_j covariance 8;
            input arm_i :best32. arm_j :best32. covariance :best32.;
        %end;
        %else %if &kind = contrasts %then %do;
            length contrast_id $12 estimate se lcl ucl p_value 8;
            input _raw_id :$32767. estimate :best32. se :best32.
                lcl :best32. ucl :best32. p_value :best32.;
            if lengthn(_raw_id) > 12 then _bad = 1;
            contrast_id = _raw_id;
            if missing(contrast_id) then _bad = 1;
        %end;
        %else %if &kind = contrast_vcov %then %do;
            length contrast_i contrast_j $12 covariance 8;
            input _raw_id :$32767. _raw_label :$32767. covariance :best32.;
            if lengthn(_raw_id) > 12 or lengthn(_raw_label) > 12 then _bad = 1;
            contrast_i = _raw_id;
            contrast_j = _raw_label;
            if cmiss(contrast_i, contrast_j) then _bad = 1;
        %end;
        if nmiss(of _numeric_) > 0 or _error_ then _bad = 1;
        drop _raw_id _raw_label;
    run;
    %car_step(context=Reference import);
    %if &_car_error_rc %then %return;
    proc sql noprint;
        select coalesce(sum(_bad), 0) + (count(*) = 0) into :bad trimmed from &out;
    quit;
    %car_step(
        context = Reference import checks,
        sql     = YES
    );
    %if &bad > 0 %then %car_error(message=Reference CSV contains missing values or invalid keys.);
%mend;

%macro _car_suite_record(
    id      =,
    status  =,
    details =
);
    data work._car_suite_row;
        length check_id $64 status $20 details $256;
        check_id = "&id";
        status = "&status";
        details = "&details";
    run;
    %car_step(context=Suite record);
    proc append base=&out_summary data=work._car_suite_row;
    run;
    %car_step(context=Suite append);
%mend;

%macro _car_suite_compare(
    sas_data       =,
    reference_data =,
    keys           =,
    values         =,
    id             =
);
    %local j field result key_index detail_dsid close_rc;
    %do j = 1 %to %sysfunc(countw(&values));
        %let field = %scan(&values, &j);
        %car_validate(
            sas_data       = &sas_data,
            reference_data = &reference_data,
            keys           = &keys,
            value          = &field,
            atol           = &atol,
            rtol           = &rtol,
            out            = work.car_check_detail,
            out_summary    = work.car_check_summary
        );
        %let result = &car_rc;
        /* The comparison's result is saved. Track report-write errors separately. */
        %let _car_error_rc = 0;
        %let detail_dsid = %sysfunc(open(work.car_check_detail, i));
        data work._car_suite_detail;
            length check_id $64 keys $512 status $20
                sas_value reference_value abs_error tolerance 8;
            set work.car_check_detail;
            check_id = "&id..&field";
            keys = '';
            %if &result = 0 or &result = 1 %then %do;
                /* Input-error reports may not contain the requested keys. */
                %do key_index = 1 %to %sysfunc(countw(&keys));
                    %if &detail_dsid > 0 %then %do;
                    %if %sysfunc(varnum(&detail_dsid, %scan(&keys, &key_index))) > 0 %then %do;
                        keys = catx('|', keys, vvalue(%scan(&keys, &key_index)));
                    %end;
                    %end;
                %end;
            %end;
            keep check_id keys status sas_value reference_value abs_error tolerance;
        run;
        %if &detail_dsid > 0 %then %let close_rc = %sysfunc(close(&detail_dsid));
        %car_step(context=Suite detail);
        %if &_car_error_rc %then %do;
            %let suite_failed = 1;
            %return;
        %end;
        proc append base=&out_details data=work._car_suite_detail;
        run;
        %car_step(context=Suite detail append);
        %if &_car_error_rc %then %do;
            %let suite_failed = 1;
            %return;
        %end;
        %if &result = 0 %then
            %_car_suite_record(
                id     = &id..&field,
                status = PASS
            );
        %else %do;
            %let suite_failed = 1;
            %_car_suite_record(
                id      = &id..&field,
                status  = FAIL,
                details = See WORK.CAR_CHECK_DETAIL
            );
        %end;
        /* Accumulate comparisons without letting a later PASS erase failure. */
        %if &_car_error_rc %then %let suite_failed = 1;
        %let _car_error_rc = 0;
    %end;
%mend;

%macro car_test_inference(
    reference_dir            =,
    data                     = work.analysis_data,
    settings                 = work.car_run_settings,
    arm_map                  = work.car_arm_map,
    raw_predictions          = work.car_predictions,
    original_predictions     = work.car_aipw_predictions,
    original_estimates       = work.car_arm_estimates,
    original_vcov            = work.car_mean_vcov,
    original_inference       = work.car_mean_inference,
    original_contrasts       = work.car_contrast_results,
    original_contrast_vcov   = work.car_contrast_vcov,
    calibrated_predictions   = work.car_cal_predictions,
    calibrated_estimates     = work.car_cal_estimates,
    calibrated_vcov          = work.car_cal_vcov,
    calibrated_inference     = work.car_cal_inference,
    calibrated_contrasts     = work.car_cal_contrasts,
    calibrated_contrast_vcov = work.car_cal_contrast_vcov,
    atol                     = 1e-8,
    rtol                     = 1e-6,
    out_summary              = work.car_validation_suite,
    out_details              = work.car_validation_details
);
    %global car_rc car_suite_rc _car_error_rc;
    %local suite_failed bad rows value stage table kind actual_n arm_text;
    %let car_rc = 1;
    %let _car_error_rc = 0;
    %let car_suite_rc = 1;
    %let suite_failed = 0;
    %car_output_guard(
        inputs   = &data &settings &arm_map &raw_predictions &original_predictions
            &original_estimates &original_vcov &original_inference &original_contrasts
            &original_contrast_vcov &calibrated_predictions &calibrated_estimates &calibrated_vcov
            &calibrated_inference &calibrated_contrasts &calibrated_contrast_vcov,
        outputs  = &out_summary &out_details work.car_check_detail work.car_check_summary,
        expected = 4
    );
    %if &_car_error_rc %then %return;
    %car_clear(outputs=&out_summary &out_details work.car_check_detail work.car_check_summary);
    %car_number(
        name  = ATOL,
        value = %superq(atol),
        lower = 0
    );
    %car_number(
        name  = RTOL,
        value = %superq(rtol),
        lower = 0
    );
    %if &_car_error_rc %then %goto suite_fail;
    %if %length(%superq(reference_dir)) = 0 %then %do;
        %_car_suite_record(
            id      = reference,
            status  = NOT_RUN,
            details = No reference directory supplied
        );
        %if &_car_error_rc %then %goto suite_fail;
        %let car_rc = 2;
        %let car_suite_rc = 2;
        %return;
    %end;
    %if not %sysfunc(fileexist(&reference_dir./settings.csv)) %then %do;
        %_car_suite_record(
            id      = reference,
            status  = NOT_RUN,
            details = Reference settings.csv unavailable
        );
        %if &_car_error_rc %then %goto suite_fail;
        %let car_rc = 2;
        %let car_suite_rc = 2;
        %return;
    %end;
    %car_require(
        data      = &settings,
        vars      = model car_scheme variance_type alpha joint add_x n,
        numeric   = variance_type alpha n,
        character = model car_scheme joint add_x
    );
    %car_require(
        data      = &data,
        vars      = usubjid trt aval strata x1_analysis x3_analysis,
        numeric   = trt aval x1_analysis x3_analysis,
        character = usubjid strata
    );
    %if &_car_error_rc %then %goto suite_fail;
    %_car_reference_import(
        file = &reference_dir./settings.csv,
        kind = settings,
        out  = work._car_ref_settings
    );
    %if &_car_error_rc %then %goto suite_fail;
    proc sql noprint;
        select count(*) into :rows trimmed from &settings;
        select count(*) into :bad trimmed from work._car_ref_settings;
        select count(*) into :actual_n trimmed from &data;
    quit;
    %car_step(
        context = Settings row count,
        sql     = YES
    );
    %if &_car_error_rc %then %goto suite_fail;
    %if &rows ne 1 or &bad ne 1 %then %do;
        %car_error(message=Exactly one SAS and R settings row is required.);
        %goto suite_fail;
    %end;
    proc sql noprint;
        select count(*) into :bad trimmed
        from &settings s cross join work._car_ref_settings r
        where s.model ne r.model or s.car_scheme ne r.car_scheme
            or s.variance_type ne r.variance_type or s.alpha ne r.alpha
            or s.joint ne r.joint or s.add_x ne r.add_x or s.n ne r.n
            or s.n ne &actual_n or r.variance_type ne 1
            or r.alpha <= 0 or r.alpha >= 1
            or r.model not in ('ANOVA', 'ANCOVA', 'ANHECOVA')
            or r.car_scheme not in ('simple', 'permuted-block')
            or r.joint ne 'YES' or not missing(r.add_x)
            or r.package_version ne '1.2.0';
    quit;
    %car_step(
        context = Settings comparison,
        sql     = YES
    );
    %if &_car_error_rc %then %goto suite_fail;
    %if &bad > 0 %then %do;
        %car_error(message=SAS and reference settings disagree.);
        %goto suite_fail;
    %end;
    %_car_suite_record(
        id     = settings,
        status = PASS
    );
    %_car_reference_import(
        file = &reference_dir./analysis.csv,
        kind = analysis,
        out  = work._car_ref_analysis
    );
    %if &_car_error_rc %then %goto suite_fail;
    %_car_reference_import(
        file = &reference_dir./arm_map.csv,
        kind = arm_map,
        out  = work._car_ref_arm_map
    );
    %if &_car_error_rc %then %goto suite_fail;
    %car_require(
        data    = &arm_map,
        vars    = arm_index trt n_arm pi_hat,
        numeric = arm_index trt n_arm pi_hat
    );
    %if &_car_error_rc %then %goto suite_fail;
    proc sql noprint;
        select strip(put(trt, best32.)) into :arm_text separated by ','
        from &arm_map order by arm_index;
        select count(*) into :bad trimmed from work._car_ref_settings
        where arms ne "&arm_text";
    quit;
    %car_step(
        context = Declared arm ordering,
        sql     = YES
    );
    %if &_car_error_rc %then %goto suite_fail;
    %if &bad > 0 %then %do;
        %car_error(message=Reference settings disagree with the SAS treatment order.);
        %goto suite_fail;
    %end;
    %_car_suite_compare(
        sas_data       = &data,
        reference_data = work._car_ref_analysis,
        keys           = usubjid,
        values         = trt aval x1_analysis x3_analysis,
        id             = population
    );
    %_car_suite_compare(
        sas_data       = &arm_map,
        reference_data = work._car_ref_arm_map,
        keys           = arm_index,
        values         = trt n_arm pi_hat,
        id             = arm_map
    );
    proc sql noprint;
        select count(*) into :bad trimmed
        from &data s full join work._car_ref_analysis r on s.usubjid=r.usubjid
        where missing(s.usubjid) or missing(r.usubjid) or s.strata ne r.strata;
    quit;
    %car_step(
        context = Joint strata comparison,
        sql     = YES
    );
    %if &_car_error_rc %then %goto suite_fail;
    %if &bad > 0 or &suite_failed %then %do;
        %car_error(message=Population or arm mapping differs from the reference.);
        %goto suite_fail;
    %end;
    %_car_suite_record(
        id     = population.strata,
        status = PASS
    );

    %_car_reference_import(
        file = &reference_dir./original_raw_predictions.csv,
        kind = raw,
        out  = work._car_ref_raw
    );
    %if &_car_error_rc %then %goto suite_fail;
    %_car_suite_compare(
        sas_data       = &raw_predictions,
        reference_data = work._car_ref_raw,
        keys           = usubjid arm_index,
        values         = mu_raw,
        id             = original.raw
    );
    %_car_reference_import(
        file = &reference_dir./calibrated_raw_predictions.csv,
        kind = cal_raw,
        out  = work._car_ref_cal_raw
    );
    %if &_car_error_rc %then %goto suite_fail;
    %_car_suite_compare(
        sas_data       = &calibrated_predictions,
        reference_data = work._car_ref_cal_raw,
        keys           = usubjid arm_index,
        values         = mu_cal_raw,
        id             = calibrated.raw
    );

    %do stage = 1 %to 2;
        %if &stage = 1 %then %let table = original;
        %else %let table = calibrated;
        %do kind = 1 %to 6;
            %local suffix keys values sas_table;
            %let suffix = %scan(predictions estimates vcov inference contrasts contrast_vcov, &kind);
            %let sas_table = &&&table._&suffix;
            %_car_reference_import(
                file = &reference_dir./&table._&suffix..csv,
                kind = &suffix,
                out  = work._car_ref_&suffix
            );
            %if &_car_error_rc %then %goto suite_fail;
            %if &kind = 1 %then %do;
                %let keys = usubjid arm_index;
                %let values = mu_tilde;
            %end;
            %else %if &kind = 2 %then %do;
                %let keys = arm_index;
                %let values = estimate;
            %end;
            %else %if &kind = 3 %then %do;
                %let keys = arm_i arm_j;
                %let values = covariance;
            %end;
            %else %if &kind = 4 %then %do;
                %let keys = arm_index;
                %let values = estimate se lcl ucl;
            %end;
            %else %if &kind = 5 %then %do;
                %let keys = contrast_id;
                %let values = estimate se lcl ucl p_value;
            %end;
            %else %do;
                %let keys = contrast_i contrast_j;
                %let values = covariance;
            %end;
            %_car_suite_compare(
                sas_data       = &sas_table,
                reference_data = work._car_ref_&suffix,
                keys           = &keys,
                values         = &values,
                id             = &table..&suffix
            );
        %end;
    %end;
    %if &suite_failed %then %goto suite_fail;
    %_car_suite_record(
        id      = suite,
        status  = PASS,
        details = All population/settings/numeric checks passed
    );
    %if &_car_error_rc %then %goto suite_fail;
    %let car_suite_rc = 0;
    %let car_rc = 0;
    %return;

%suite_fail:
    %_car_suite_record(
        id      = suite,
        status  = FAIL,
        details = See SAS log and comparison reports
    );
    %let car_suite_rc = 1;
    %let car_rc = 1;
%mend;
