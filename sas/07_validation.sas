/*==========================================================================
 Program : 07_validation.sas
 Project : Robust Covariate Adjustment under CAR (SAS / RobinCar)
 Purpose : Compare one numeric result column using complete keys and mixed
           tolerance.
 Status  : See doc/validation_status.md for verified configurations.

 INPUT  : SAS and reference datasets, unique key columns, numeric value
          column and absolute/relative tolerances.
 OUTPUT : Keyed comparison details, comparison summary and CAR_RC.

 IMPORTANT:
 - Load 00_car_common.sas first; this macro does not require SAS/IML.
 - The caller must align population, settings and treatment-arm ordering.
 - Use abs(SAS-reference) <= atol + rtol*abs(reference).
 - CAR_RC: 0=pass, 1=failure, 2=reference unavailable (NOT_RUN).
 - Loading defines the comparator without importing CSVs or running tests.
==========================================================================*/

/*==========================================================================
 Macro   : car_validate
 Purpose : Compare one numeric field with keyed mixed-tolerance checks.

 INPUT  : SAS_DATA, REFERENCE_DATA, KEYS, VALUE; ATOL, RTOL and COMPARE.
 OUTPUT : OUT comparison details, OUT_SUMMARY and CAR_RC.

 IMPORTANT:
 - Keys must be complete and unique; missing numeric values fail.
 - Missing reference tables return NOT_RUN=2, not a successful comparison.
==========================================================================*/
%macro car_validate(
    sas_data       =,
    reference_data =,
    keys           =,
    value          =,
    atol           = 1e-8,
    rtol           = 1e-6,
    compare        = NO,
    out            = work.car_validation_results,
    out_summary    = work.car_validation_summary
);
    %global car_rc _car_error_rc;
    %let car_rc = 1;
    %let _car_error_rc = 0;
    %local i ds_s ds_r vs vr rc bad n_failed n_rows;
    %if not %sysmacexist(car_require) %then %do;
        %let car_rc = 1;
        %put ERROR: [CAR] Run 00_car_common.sas first.;
        %return;
    %end;

    %local _car_outputs;
    %let _car_outputs = &out &out_summary;
    %car_output_guard(
        inputs   = &sas_data &reference_data,
        outputs  = &_car_outputs,
        expected = 2
    );
    %if &_car_error_rc %then %return;
    %car_clear(outputs=&_car_outputs);
    %if &_car_error_rc %then %goto validation_fail;

    %if %length(%superq(reference_data)) = 0 %then %do;
        %car_error(message=Specify a REFERENCE_DATA dataset name.);
        %goto validation_fail;
    %end;

    %if %length(%superq(keys)) = 0 or %car_nwords(%superq(value)) ne 1 %then %do;
        %car_error(message=Specify KEYS and one numeric VALUE column.);
        %goto validation_fail;
    %end;

    %if %sysfunc(findw(%upcase(&keys), %upcase(&value))) > 0 %then %do;
        %car_error(message=VALUE cannot also be a key.);
        %goto validation_fail;
    %end;

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
    %if &_car_error_rc %then %goto validation_fail;

    %if %upcase(&compare) ne YES and %upcase(&compare) ne NO %then %do;
        %car_error(message=COMPARE must be YES or NO.);
        %goto validation_fail;
    %end;

    %car_require(
        data    = &sas_data,
        vars    = &keys &value,
        numeric = &value
    );
    %if &_car_error_rc %then
        %goto validation_fail;
    %if not %sysfunc(exist(&reference_data)) %then %do;

        data &out;
            length status $20 details $200;
            status = 'NOT_RUN';
            details = 'Reference dataset unavailable';
        run;
        %car_step(context=Validation report);
        %if &_car_error_rc %then %goto validation_fail;

        data &out_summary;
            length status $20;
            status = 'NOT_RUN';
            n_rows = 0;
            n_failed = .;
        run;
        %car_step(context=Validation report);
        %if &_car_error_rc %then %goto validation_fail;

        %put WARNING: [CAR] Reference &reference_data is unavailable. Validation NOT_RUN.;
        %let car_rc = 2;
        %return;
    %end;

    %car_require(
        data    = &reference_data,
        vars    = &keys &value,
        numeric = &value
    );
    %if &_car_error_rc %then
        %goto validation_fail;

    /* Prevent implicit numeric/character conversion or key truncation. */
    %let ds_s = %sysfunc(open(&sas_data, i));
    %let ds_r = %sysfunc(open(&reference_data, i));
    %do i = 1 %to %car_nwords(%superq(keys));
        %let vs = %sysfunc(varnum(&ds_s, %scan(&keys, &i)));
        %let vr = %sysfunc(varnum(&ds_r, %scan(&keys, &i)));
        %if %sysfunc(vartype(&ds_s, &vs)) ne %sysfunc(vartype(&ds_r, &vr)) %then
            %car_error(message=Key types disagree for %scan(&keys,&i).);
        %else %if %sysfunc(vartype(&ds_s, &vs)) = C %then %do;
            %if %sysfunc(varlen(&ds_s, &vs)) ne %sysfunc(varlen(&ds_r, &vr)) %then
                %car_error(message=Character key lengths must match for %scan(&keys,&i).);
        %end;
    %end;

    %let rc = %sysfunc(close(&ds_s));
    %let rc = %sysfunc(close(&ds_r));
    %if &_car_error_rc %then
        %goto validation_fail;
    %car_unique(
        data = &sas_data,
        keys = &keys
    );
    %car_unique(
        data = &reference_data,
        keys = &keys
    );
    %if &_car_error_rc %then
        %goto validation_fail;

    proc sort data = &sas_data(keep = &keys &value rename = (&value = _car_sas_value))
        out = work._car_val_s;
        by &keys;
    run;
    %car_step(context=Validation report);
    %if &_car_error_rc %then %goto validation_fail;

    proc sort data = &reference_data(keep = &keys &value rename = (&value = _car_ref_value))
        out = work._car_val_r;
        by &keys;
    run;
    %car_step(context=Validation report);
    %if &_car_error_rc %then %goto validation_fail;

    data &out;
        merge work._car_val_s(in = s) work._car_val_r(in = r);
        by &keys;
        length status $20 value_name $32;
        value_name = "&value";
        sas_value = _car_sas_value;
        reference_value = _car_ref_value;
        if not s then status = 'MISSING_SAS_KEY';
        else if not r then status = 'MISSING_REF_KEY';
        else if missing(sas_value) or missing(reference_value) then status = 'MISSING_VALUE';
        else do;
            abs_error = abs(sas_value - reference_value);
            tolerance = &atol + &rtol * abs(reference_value);
            if missing(abs_error) or missing(tolerance) then status = 'NUMERIC_ERROR';
            else if abs_error <= tolerance then status = 'PASS';
            else status = 'FAIL';
        end;
        drop _car_sas_value _car_ref_value;
    run;
    %car_step(context=Validation report);
    %if &_car_error_rc %then %goto validation_fail;

    proc sql noprint;
        select
            count(*),
            coalesce(sum(status ne 'PASS'), 0) into :n_rows trimmed,
            :n_failed trimmed
        from &out;
        create table &out_summary as
        select
            count(*) as n_rows,
            coalesce(sum(status ne 'PASS'), 0) as n_failed,
            max(abs_error) as max_abs_error
        from &out;
    quit;
    %car_step(
        context = Validation report,
        sql     = YES
    );
    %if &_car_error_rc %then %goto validation_fail;

    data &out_summary;
        set &out_summary;
        length status $20;
        if n_rows = 0 or n_failed > 0 then status = 'FAIL';
        else status = 'PASS';
        atol = &atol;
        rtol = &rtol;
    run;
    %car_step(context=Validation report);
    %if &_car_error_rc %then %goto validation_fail;

    %if %upcase(&compare) = YES %then %do;

        /* Supplemental report; mixed-tolerance DATA step is authoritative. */

        proc compare
            base = work._car_val_r
            compare = work._car_val_s
            method = absolute
            criterion = &atol;
            id &keys;
            var _car_ref_value;
            with _car_sas_value;
        run;
        %car_step(context=Validation report);
        %if &_car_error_rc %then %goto validation_fail;

    %end;
    %if &n_rows = 0 or &n_failed > 0 %then %do;
        %car_error(message=Validation failed: &n_failed differences across &n_rows keys.);
    %end;
    %else %do;
        %let car_rc = 0;
        %put NOTE: [CAR] Validation PASS for &value across &n_rows keys.;
    %end;
    %return;

%validation_fail:
    %car_clear(outputs=&_car_outputs);
    %let car_rc = 1;

    data &out;
        length status $20 details $200;
        status = 'INPUT_ERROR';
        details = 'See SAS log for invalid schema or duplicate/missing keys';
    run;
    %car_step(context=Failure report);

    data &out_summary;
        length status $20;
        status = 'FAIL';
        n_rows = 0;
        n_failed = .;
    run;
    %car_step(context=Failure report);

%mend;
