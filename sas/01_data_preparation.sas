/*==========================================================================
 Program : 01_data_preparation.sas
 Project : Robust Covariate Adjustment under CAR (SAS / RobinCar)
 Purpose : Import, validate, standardize, and summarize RobinCar example data.
 Status  : See doc/validation_status.md for verified configurations.

 INPUT  : CSV columns z1 z2 y0 y1 y2 A y strata_cross x1 x3
 OUTPUT : WORK.ANALYSIS_DATA, WORK.ALLOCATION_SUMMARY,
          WORK.BASELINE_SUMMARY, WORK.QC_ISSUES

 IMPORTANT:
 - y is the observed response. y0/y1/y2 are retained as source columns,
   NOT interpreted as arm-specific potential outcomes without documentation.
 - Source IDs are absent; USUBJID is generated from source CSV row order.
 - CAR design is NOT inferred from observed treatment/stratum counts.
 - All three source treatment arms are retained by default; set ANALYSIS_ARMS
   to a subset only if a matching R reference analysis uses the same subset.
 - This program does NOT address missing outcomes or estimate treatment effects.
==========================================================================*/

/*----------------------- 0. User configuration --------------------------*/

/* Invalidate reserved outputs before checking the new input, even when an old
   run succeeded in this same SAS session. Preserve unrelated WORK datasets. */
%macro _car_data_reset;
    %global car_data_rc car_fit_rc car_aipw_rc car_rc car_suite_rc
        _car_error_rc car_export_count car_export_plot_count;
    %let car_data_rc=1;
    %let car_fit_rc=1;
    %let car_aipw_rc=1;
    %let car_rc=1;
    %let car_suite_rc=1;
    %let _car_error_rc=1;
    %let car_export_count=0;
    %let car_export_plot_count=0;
    proc datasets library=work nolist nowarn;
        delete robincar_raw standardized_all analysis_data qc_issues
            allocation_summary baseline_summary
            model_parameters model_fitted model_diagnostics
            aipw_predictions aipw_means
            car_run_settings car_mean_vcov car_mean_inference
            car_variance_components car_stratum_residuals
            car_contrast_coefficients car_contrast_results car_contrast_vcov
            car_cal_predictions car_cal_means car_cal_diagnostics
            car_cal_vcov car_cal_inference car_cal_components
            car_cal_stratum_residuals car_cal_contrasts car_cal_contrast_vcov
            car_validation_suite car_validation_details
            car_validation_results car_validation_summary
            car_check_detail car_check_summary
            p02_r_summary p02_r_diagnostics_compare p02_r_fitted_compare
            p03_r_mean_compare;
        delete car_model_anova car_model_ancova car_model_anhecova / memtype=itemstor;
    quit;
%mend;

/* Preserve current QC findings before cancelling. Never invoke final inference
   export here: those results are unavailable for a failed preparation. */
%macro _car_data_abort(message=, save_qc=NO);
    %global car_data_rc car_rc _car_error_rc;
    %let car_data_rc=1;
    %let car_rc=1;
    %let _car_error_rc=1;
    %put ERROR: [CAR DATA] &message;
    %if &save_qc=YES and %sysfunc(exist(work.qc_issues)) %then %do;
        proc print data=work.qc_issues noobs; run;
        %if %symexist(car_export_dir) %then %do;
            %if %length(%superq(car_export_dir))>0 %then %do;
                proc export data=work.qc_issues
                    outfile="&car_export_dir./qc_issues.csv" dbms=csv replace;
                run;
                %if &syserr>4 %then %do;
                    %put WARNING: QC CSV could not be saved. WORK.QC_ISSUES remains available.;
                %end;
            %end;
        %end;
    %end;
    %if %sysmacexist(car_report_finish) %then %car_report_finish;
    %abort cancel;
%mend;
/* Check immediately after preparation steps; a later PROC can reset SYSERR. */
%macro _car_data_step(context=, sql=NO);
    %if &syserr>4 %then %do;
        %_car_data_abort(message=&context failed with SYSERR=&syserr..);
    %end;
    %if &sql=YES %then %do;
        %if &sqlrc ne 0 %then %do;
            %_car_data_abort(message=&context failed with SQLRC=&sqlrc..);
        %end;
    %end;
%mend;
%_car_data_reset;
%_car_data_step(context=Previous run output cleanup);

/*==========================================================================
 Macro   : require_config
 Purpose : Check that the server CSV path has been configured.

 INPUT  : Global macro variable INPUT_CSV.
 OUTPUT : No data output; cancels submission when configuration is absent.

 IMPORTANT:
 - Define and call CAR_CONFIG before running Program 01.
==========================================================================*/
%macro require_config;
    %if not %symexist(input_csv) %then %do;
        %_car_data_abort(message=Call CAR_CONFIG first to configure INPUT_CSV.);
    %end;
    %if %length(%superq(input_csv))=0 %then %do;
        %_car_data_abort(message=INPUT_CSV is empty. Configure it through CAR_CONFIG.);
    %end;
%mend;
%require_config;
/* A run entry point may select the population before submitting Program 01. */
%if not %symexist(analysis_arms) %then %do;
    %let analysis_arms = 0 1 2;
%end;
%let expected_arms = 0 1 2;
%let required_cols = z1 z2 y0 y1 y2 A y strata_cross x1 x3;
/* For documentation only; fill based on source trial/generation protocol. */
%let car_scheme    = NOT_VERIFIED;

/*----------------------- 1. Import source CSV ---------------------------*/
/* Return status rather than cancelling inside the import helper, so failure
   scenarios can be exercised by the standalone validation script. */
%macro _car_import_source;
    %global car_data_rc;
    %local import_rc dsid close_rc n_raw;
    %let car_data_rc=1;
    proc datasets library=work nolist nowarn;
        delete robincar_raw;
    quit;
    %if not %sysfunc(fileexist(%superq(input_csv))) %then %do;
        %put ERROR: [CAR DATA] Input CSV does not exist or is inaccessible: %superq(input_csv).;
        %return;
    %end;
    proc import datafile="&input_csv" out=work.robincar_raw
        dbms=csv replace;
        guessingrows=max;
    run;
    /* Capture SYSERR before any other DATA/PROC step can overwrite it. */
    %let import_rc=&syserr;
    %if &import_rc>4 or not %sysfunc(exist(work.robincar_raw)) %then %do;
        %put ERROR: [CAR DATA] CSV import failed with SYSERR=&import_rc: %superq(input_csv).;
        proc datasets library=work nolist nowarn;
            delete robincar_raw;
        quit;
        %return;
    %end;
    %let dsid=%sysfunc(open(work.robincar_raw,i));
    %if &dsid=0 %then %return;
    %let n_raw=%sysfunc(attrn(&dsid,nlobs));
    %let close_rc=%sysfunc(close(&dsid));
    %if &n_raw=0 %then %do;
        %put ERROR: [CAR DATA] Input CSV contains no observations.;
        proc datasets library=work nolist nowarn;
            delete robincar_raw;
        quit;
        %return;
    %end;
    %let car_data_rc=0;
%mend;
%_car_import_source;
%if &car_data_rc ne 0 %then %do;
    %_car_data_abort(message=Input import failed. No models or inference will run.);
%end;

/*==========================================================================
 Macro   : check_columns
 Purpose : Verify all required source CSV columns after import.

 INPUT  : WORK.ROBINCAR_RAW and the REQUIRED_COLS macro variable.
 OUTPUT : CAR_DATA_RC=0 when schema checks pass; 1 otherwise.
          The automatic caller cancels on failure.

 IMPORTANT:
 - Read dataset metadata directly; avoid blank-delimiter FINDW in SYSFUNC.
==========================================================================*/
%macro check_columns;
    %global car_data_rc;
    %local j col dsid close_rc missing_cols vnum expected_type;
    %let car_data_rc=1;
    %let dsid=%sysfunc(open(work.robincar_raw,i));
    %if &dsid=0 %then %do;
        %put ERROR: Cannot open WORK.ROBINCAR_RAW. Check the import log.;
        %return;
    %end;
    %let missing_cols=0;
    %do j=1 %to %sysfunc(countw(&required_cols));
        %let col=%scan(&required_cols,&j,%str( ));
        %let vnum=%sysfunc(varnum(&dsid,&col));
        %if &vnum=0 %then %do;
            %put ERROR: Required source column &col is missing.;
            %let missing_cols=1;
        %end;
        /* y0/y1/y2 are traceability-only columns; do not constrain their type. */
        %else %if &col ne y0 and &col ne y1 and &col ne y2 %then %do;
            %let expected_type=N;
            %if &col=strata_cross %then %let expected_type=C;
            %if %sysfunc(vartype(&dsid,&vnum)) ne &expected_type %then %do;
                %put ERROR: Source column &col must have type &expected_type..;
                %let missing_cols=1;
            %end;
        %end;
    %end;
    %let close_rc=%sysfunc(close(&dsid));
    %if &missing_cols %then %return;
    %let car_data_rc=0;
%mend;
%check_columns;
%if &car_data_rc ne 0 %then %do;
    %_car_data_abort(message=Input schema validation failed.);
%end;

/*----------------------- 2. Standardize fields --------------------------*/
data work.standardized_all;
    set work.robincar_raw;
    length usubjid $12 strata $40 issue $200;
    usubjid = cats('SRC',put(_n_,z8.));
    trt = A;
    aval = y;
    strata = strip(strata_cross);
    x1_analysis = x1;
    x3_analysis = x3;
    /* Keep all source columns, including y0/y1/y2, for traceability. */
    drop issue;
run;

%_car_data_step(context=Input standardization);

/*----------------------- 3. Row-level data checks -----------------------*/
data work.qc_issues;
    set work.standardized_all;
    length severity $8 issue_code $32 details $200;
    keep usubjid severity issue_code details;

    if missing(trt) then do;
        severity='ERROR'; issue_code='MISSING_TRT';
        details='Treatment assignment is missing'; output;
    end;
    else if not (trt in (0,1,2)) then do;
        severity='ERROR'; issue_code='INVALID_TRT';
        details=cats('Unexpected treatment level: ',trt); output;
    end;

    if missing(aval) then do;
        severity='ERROR'; issue_code='MISSING_AVAL';
        details='Observed outcome is missing (complete-case example only)'; output;
    end;
    if missing(z1) or missing(z2) or missing(strata) then do;
        severity='ERROR'; issue_code='MISSING_STRATA';
        details='One or more randomization stratum fields are missing'; output;
    end;
    else if strip(strata) ne cats(strip(vvalue(z1)),'-',strip(vvalue(z2))) then do;
        severity='ERROR'; issue_code='STRATA_MISMATCH';
        details=cats('strata_cross=',strata,' vs z1-z2=',z1,'-',z2); output;
    end;
    if missing(x1_analysis) or missing(x3_analysis) then do;
        severity='ERROR'; issue_code='MISSING_X';
        details='Baseline working-model covariate missing'; output;
    end;
run;

%_car_data_step(context=Row-level QC);

/* USUBJID is row-generated; uniqueness is by construction. */
proc sql noprint;
    select count(*) into :n_errors trimmed
    from work.qc_issues where severity='ERROR';
quit;
%_car_data_step(context=QC error count, sql=YES);

/*==========================================================================
 Macro   : stop_on_errors
 Purpose : Stop data preparation when row-level QC errors are present.

 INPUT  : N_ERRORS calculated from WORK.QC_ISSUES.
 OUTPUT : No data output; cancels submission when N_ERRORS is positive.

 IMPORTANT:
 - Review WORK.QC_ISSUES before continuing with an invalid population.
==========================================================================*/
%macro stop_on_errors;
    %if &n_errors > 0 %then %do;
        %_car_data_abort(message=Found &n_errors data issues. Review WORK.QC_ISSUES., save_qc=YES);
    %end;
%mend;
%stop_on_errors;

/*----------------------- 4. Analysis population -------------------------*/
/* Explicit arm selection; no implicit collapse of the three-arm trial. */
data work.analysis_data;
    set work.standardized_all;
    if findw("&analysis_arms",strip(put(trt,best.)),' ') > 0;
    keep usubjid trt aval x1_analysis x3_analysis z1 z2 strata
         A y x1 x3 strata_cross y0 y1 y2;
run;

%_car_data_step(context=Analysis population creation);

/* Ensure the requested treatment arms are represented. */
proc sql noprint;
    select count(*) into :n_analysis trimmed from work.analysis_data;
quit;
%_car_data_step(context=Analysis population count, sql=YES);
%if &n_analysis=0 %then %do;
    %_car_data_abort(message=No observations remain for the requested analysis arms.);
%end;
%put NOTE: Analysis dataset contains &n_analysis observations.;

/*----------------------- 5. Allocation balance --------------------------*/
proc sql;
    create table work.allocation_summary as
    select a.strata, a.trt, count(*) as n_arm_stratum,
           b.n_stratum,
           calculated n_arm_stratum / b.n_stratum as observed_prop format=8.4
    from work.analysis_data as a
    inner join
      (select strata, count(*) as n_stratum
       from work.analysis_data group by strata) as b
    on a.strata=b.strata
    group by a.strata, a.trt, b.n_stratum
    order by a.strata, a.trt;
quit;

%_car_data_step(context=Allocation summary, sql=YES);

/*----------------------- 6. Baseline summaries --------------------------*/
proc means data=work.analysis_data n mean std min max nway;
    class trt;
    var x1_analysis x3_analysis;
    output out=work.baseline_summary(drop=_type_ _freq_)
        n= n_x1 n_x3
        mean= mean_x1 mean_x3
        std= sd_x1 sd_x3
        min= min_x1 min_x3
        max= max_x1 max_x3;
run;

%_car_data_step(context=Baseline summary);

/*----------------------- 7. Display QC outputs --------------------------*/
title 'RobinCar example: treatment by randomization stratum';
proc freq data=work.analysis_data;
    tables strata*trt / missing;
run;

title 'Observed allocation proportions within strata';
proc print data=work.allocation_summary noobs; run;

title 'Baseline covariate summary by treatment';
proc print data=work.baseline_summary noobs; run;

title 'Data quality findings';
proc print data=work.qc_issues noobs; run;
title;

%let car_data_rc=0;
%let _car_error_rc=0;
%put NOTE: CAR_DATA_RC=&car_data_rc;
%put NOTE: Program 01 completed. CAR design metadata: &car_scheme.;
