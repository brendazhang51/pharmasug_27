/*==========================================================================
 Program 03: arm-specific predictions and AIPW point estimates.
 Run Programs 01 and 02 in the same SAS session first. The saved PROC GLM
 item stores from Program 02 must correspond to DATA. No CAR-aware standard
 errors, confidence intervals, calibration, or treatment contrasts are made.

 API: %car_aipw(data=work.analysis_data, method=ALL)
 METHOD: ALL, ANOVA, ANCOVA, ANHECOVA. CAR_AIPW_RC: 0 success, 1 failure.
 Outputs: WORK.AIPW_PREDICTIONS (one row per subject/target arm/model) and
          WORK.AIPW_MEANS (one row per target arm/model).

 For arm a: AIPW_MEAN = mean_i{m_a(X_i)}
                      + mean_{i:A_i=a}{Y_i-m_a(X_i)}.
 The second term uses the observed arm count n_a as its denominator.
==========================================================================*/

%macro _car_aipw_clear;
    proc datasets library=work nolist nowarn;
        delete aipw_predictions aipw_means;
    quit;
%mend;

%macro _car_aipw_impl(data=,method=);
    %local dsid close_rc j name vnum schema_bad n nbad nunique k min_arm
           methods m current scored_n scored_bad matched observed_bad
           means_n means_bad fit_n;
    %if &method ne ALL and &method ne ANOVA and &method ne ANCOVA
        and &method ne ANHECOVA %then %do;
        %put ERROR: METHOD must be ALL, ANOVA, ANCOVA, or ANHECOVA.;
        %return;
    %end;
    %let dsid=%sysfunc(open(&data,i));
    %if &dsid=0 %then %do;
        %put ERROR: Cannot open &data.. Run Program 01 first.;
        %return;
    %end;
    %let schema_bad=0;
    %do j=1 %to 5;
        %let name=%scan(USUBJID TRT AVAL X1_ANALYSIS X3_ANALYSIS,&j);
        %let vnum=%sysfunc(varnum(&dsid,&name));
        %if &vnum=0 %then %do;
            %let schema_bad=1;
            %put ERROR: Required variable &name is missing.;
        %end;
        %else %if &j>1 %then %do;
            %if %sysfunc(vartype(&dsid,&vnum)) ne N %then %do;
                %let schema_bad=1;
                %put ERROR: &name must be numeric.;
            %end;
        %end;
    %end;
    %let close_rc=%sysfunc(close(&dsid));
    %if &schema_bad %then %return;
    %if not %sysfunc(exist(work.model_fitted)) %then %do;
        %put ERROR: WORK.MODEL_FITTED is missing. Run Program 02 first.;
        %return;
    %end;

    data work._ca_input;
        set &data(keep=usubjid trt aval x1_analysis x3_analysis);
        observed_trt=trt;
        drop trt;
    run;
    %if &syserr>4 %then %return;
    proc sql noprint;
        select count(*),count(distinct usubjid),count(distinct observed_trt),
               coalesce(sum(missing(usubjid) or
                   nmiss(observed_trt,aval,x1_analysis,x3_analysis)>0),0)
          into :n trimmed,:nunique trimmed,:k trimmed,:nbad trimmed
          from work._ca_input;
        create table work._ca_arms as
          select observed_trt as trt,count(*) as n_arm
          from work._ca_input group by observed_trt;
        select min(n_arm) into :min_arm trimmed from work._ca_arms;
    quit;
    %if &sqlrc ne 0 %then %return;
    %if &n=0 %then %do;
        %put ERROR: Analysis input is empty.;
        %return;
    %end;
    %if &nbad>0 or &nunique ne &n or &k<2 or &min_arm<2 %then %do;
        %put ERROR: Invalid AIPW population: rows=&n unique_IDs=&nunique missing_rows=&nbad arms=&k minimum_arm_n=&min_arm..;
        %return;
    %end;

    /* The TRT column is the target arm supplied to PROC PLM. The original
       assignment is retained separately as OBSERVED_TRT. */
    proc sql;
        create table work._ca_grid as
          select a.usubjid,a.observed_trt,a.aval,
                 a.x1_analysis,a.x3_analysis,b.trt
          from work._ca_input as a,work._ca_arms as b
          order by a.usubjid,b.trt;
    quit;
    %if &sqlrc ne 0 %then %return;

    %let methods=&method;
    %if &method=ALL %then %let methods=ANOVA ANCOVA ANHECOVA;
    %do m=1 %to %sysfunc(countw(&methods));
        %let current=%scan(&methods,&m);
        %if not %sysfunc(exist(work.car_model_&current,ITEMSTOR)) %then %do;
            %put ERROR: Missing WORK.CAR_MODEL_&current item store. Run Program 02 with this method.;
            %return;
        %end;
        proc datasets library=work nolist nowarn;
            delete _ca_scored _ca_long _ca_means;
        quit;
        proc plm restore=work.car_model_&current;
            score data=work._ca_grid out=work._ca_scored predicted=predicted;
        run;
        %if &syserr>4 or not %sysfunc(exist(work._ca_scored)) %then %do;
            %put ERROR: PROC PLM failed for &current..;
            %return;
        %end;
        proc sql noprint;
            select count(*),coalesce(sum(missing(predicted)),0)
              into :scored_n trimmed,:scored_bad trimmed
              from work._ca_scored;
            select count(*),coalesce(sum(
                   missing(s.predicted) or missing(f.predicted) or
                   s.observed_trt ne f.trt or s.aval ne f.aval or
                   abs(s.predicted-f.predicted)>1e-8+1e-8*abs(f.predicted)),0)
              into :matched trimmed,:observed_bad trimmed
              from work._ca_scored as s inner join work.model_fitted as f
              on s.usubjid=f.usubjid and s.trt=f.trt
              where s.trt=s.observed_trt and f.model="&current";
            select count(*) into :fit_n trimmed from work.model_fitted
              where model="&current";
        quit;
        %if &sqlrc ne 0 %then %return;
        %if &scored_n ne %eval(&n*&k) or &scored_bad>0 or
            &matched ne &n or &fit_n ne &n or &observed_bad>0 %then %do;
            %put ERROR: &current scoring does not reproduce Program 02 or has missing/extra rows.;
            %return;
        %end;

        data work._ca_long;
            length model $8;
            set work._ca_scored;
            model="&current";
            target_trt=trt;
            if observed_trt=target_trt then observed_residual=aval-predicted;
            else observed_residual=.;
            keep model usubjid observed_trt target_trt aval predicted
                 observed_residual;
        run;
        proc sql;
            create table work._ca_means as
              select "&current" as model length=8,target_trt,
                     count(*) as n_total,
                     sum(observed_trt=target_trt) as n_arm,
                     mean(case when observed_trt=target_trt then aval else . end)
                       as observed_mean,
                     mean(predicted) as mean_pred_all,
                     mean(case when observed_trt=target_trt then predicted else . end)
                       as mean_pred_arm,
                     mean(observed_residual) as mean_residual_arm,
                     calculated mean_pred_all+calculated mean_residual_arm
                       as aipw_mean
              from work._ca_long group by target_trt;
        quit;
        %if &sqlrc ne 0 %then %return;
        proc sql noprint;
            select count(*),coalesce(sum(n_total ne &n or n_arm<2 or
                nmiss(observed_mean,mean_pred_all,mean_pred_arm,
                      mean_residual_arm,aipw_mean)>0 or
                abs(aipw_mean-(observed_mean-mean_pred_arm+mean_pred_all))>1e-8),0)
              into :means_n trimmed,:means_bad trimmed from work._ca_means;
        quit;
        %if &sqlrc ne 0 %then %return;
        %if &means_n ne &k or &means_bad>0 %then %do;
            %put ERROR: &current AIPW means failed completeness or identity checks.;
            %return;
        %end;
        proc append base=work.aipw_predictions data=work._ca_long; run;
        %if &syserr>4 %then %return;
        proc append base=work.aipw_means data=work._ca_means; run;
        %if &syserr>4 %then %return;
    %end;
    %let car_aipw_rc=0;
%mend;

%macro car_aipw(data=work.analysis_data,method=ALL);
    %global car_aipw_rc;
    %let car_aipw_rc=1;
    %_car_aipw_clear;
    %_car_aipw_impl(data=&data,method=%upcase(&method));
    %if &car_aipw_rc ne 0 %then %do;
        %_car_aipw_clear;
        %put ERROR: Program 03 failed. AIPW outputs have been invalidated.;
    %end;
%mend car_aipw;

%macro _car_aipw_driver;
    %car_aipw();
    %if &car_aipw_rc ne 0 %then %abort cancel;
    title 'AIPW treatment-specific means (point estimates only)';
    proc print data=work.aipw_means noobs; run;
    title;
    %put NOTE: Program 03 completed. CAR-aware inference is pending.;
%mend;
%_car_aipw_driver;
