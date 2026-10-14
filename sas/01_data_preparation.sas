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
        %put ERROR: Call CAR_CONFIG first to configure INPUT_CSV.;
        %abort cancel;
    %end;
    %if %length(%superq(input_csv))=0 %then %do;
        %put ERROR: INPUT_CSV is empty. Configure it through CAR_CONFIG.;
        %abort cancel;
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
proc import datafile="&input_csv" out=work.robincar_raw
    dbms=csv replace;
    guessingrows=max;
run;

/*==========================================================================
 Macro   : check_columns
 Purpose : Verify all required source CSV columns after import.

 INPUT  : WORK.ROBINCAR_RAW and the REQUIRED_COLS macro variable.
 OUTPUT : No data output; cancels submission if the source/schema is
          unavailable.

 IMPORTANT:
 - Read dataset metadata directly; avoid blank-delimiter FINDW in SYSFUNC.
==========================================================================*/
%macro check_columns;
    %local j col dsid close_rc missing_cols;
    %let dsid=%sysfunc(open(work.robincar_raw,i));
    %if &dsid=0 %then %do;
        %put ERROR: Cannot open WORK.ROBINCAR_RAW. Check the import log.;
        %abort cancel;
    %end;
    %let missing_cols=0;
    %do j=1 %to %sysfunc(countw(&required_cols));
        %let col=%scan(&required_cols,&j,%str( ));
        %if %sysfunc(varnum(&dsid,&col))=0 %then %do;
            %put ERROR: Required source column &col is missing.;
            %let missing_cols=1;
        %end;
    %end;
    %let close_rc=%sysfunc(close(&dsid));
    %if &missing_cols %then %do;
        %abort cancel;
    %end;
%mend;
%check_columns;

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

/* USUBJID is row-generated; uniqueness is by construction. */
proc sql noprint;
    select count(*) into :n_errors trimmed
    from work.qc_issues where severity='ERROR';
quit;

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
        %put ERROR: Found &n_errors data issues. Review WORK.QC_ISSUES.;
        %abort cancel;
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

/* Ensure the requested treatment arms are represented. */
proc sql noprint;
    select count(*) into :n_analysis trimmed from work.analysis_data;
quit;
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

%put NOTE: Program 01 completed. CAR design metadata: &car_scheme.;
