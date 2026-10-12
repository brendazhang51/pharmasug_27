/*==========================================================================
 Program 02: continuous-outcome working models (SAS/STAT required).
 Run utilities.SAS and Program 01 in this session first. All observed TRT
 levels are categorical; only X1_ANALYSIS and X3_ANALYSIS are covariates.
 No CAR inference is performed. GLM's ordinary model-based SEs/p-values in
 MODEL_PARAMETERS are diagnostics, not final treatment-effect inference.

 API: %car_fit(data=work.analysis_data, method=ALL)
 METHOD: ALL, ANOVA, ANCOVA, ANHECOVA. CAR_FIT_RC: 0 success, 1 failure.
 A failed macro call returns without fitting further models and removes its
 public outputs. The default driver below cancels submission on failure.
 WORK.MODEL_* outputs, WORK.CAR_MODEL_* item stores and WORK._CF_* scratch
 names are reserved. Do not use these names as input.
==========================================================================*/

%macro _car_fit_clear;
    proc datasets library=work nolist nowarn;
        delete model_parameters model_fitted model_diagnostics;
        delete car_model_anova car_model_ancova car_model_anhecova / memtype=itemstor;
    quit;
%mend;

%macro _car_fit_impl(data=, method=);
    %local dsid close_rc j name vnum schema_bad n nbad nunique k min_arm
           methods m current effects expected_rank fitted_n fitted_bad
           model_rank error_df sse mse diag_rows fit_rc;
    %if &method ne ALL and &method ne ANOVA and &method ne ANCOVA
        and &method ne ANHECOVA %then %do;
        %put ERROR: METHOD must be ALL, ANOVA, ANCOVA, or ANHECOVA.;
        %return;
    %end;
    %let dsid=%sysfunc(open(&data,i));
    %if &dsid=0 %then %do;
        %put ERROR: Cannot open &data.. Run Program 01 successfully first.;
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

    /* One fixed complete population is used even when only ANOVA is requested. */
    data work._cf_input;
        set &data(keep=usubjid trt aval x1_analysis x3_analysis);
    run;
    %if &syserr>4 %then %return;
    proc sql noprint;
        select count(*), count(distinct usubjid), count(distinct trt),
               coalesce(sum(missing(usubjid) or
                   nmiss(trt,aval,x1_analysis,x3_analysis)>0),0)
          into :n trimmed,:nunique trimmed,:k trimmed,:nbad trimmed
          from work._cf_input;
        create table work._cf_counts as
          select trt,count(*) as n from work._cf_input group by trt;
        select min(n) into :min_arm trimmed from work._cf_counts;
    quit;
    %if &sqlrc ne 0 %then %return;
    %if &n=0 %then %do;
        %put ERROR: Analysis input is empty.;
        %return;
    %end;
    %if &nbad>0 or &nunique ne &n or &k<2 or &min_arm<2 %then %do;
        %put ERROR: Invalid population: rows=&n unique_IDs=&nunique missing_rows=&nbad arms=&k minimum_arm_n=&min_arm..;
        %return;
    %end;

    %let methods=&method;
    %if &method=ALL %then %let methods=ANOVA ANCOVA ANHECOVA;
    %do m=1 %to %sysfunc(countw(&methods));
        %let current=%scan(&methods,&m);
        %let effects=trt;
        %let expected_rank=&k;
        %if &current=ANCOVA %then %do;
            %let effects=trt x1_analysis x3_analysis;
            %let expected_rank=%eval(&k+2);
        %end;
        %if &current=ANHECOVA %then %do;
            %let effects=trt x1_analysis x3_analysis
                trt*x1_analysis trt*x3_analysis;
            %let expected_rank=%eval(3*&k);
        %end;

        proc datasets library=work nolist nowarn;
            delete _cf_parameters _cf_anova _cf_fitted _cf_diagnostics;
        quit;
        ods output ParameterEstimates=work._cf_parameters
                   OverallANOVA=work._cf_anova;
        proc glm data=work._cf_input order=internal;
            class trt;
            model aval=&effects / solution;
            output out=work._cf_fitted predicted=predicted residual=residual;
            store out=work.car_model_&current;
        run;
        quit;
        %let fit_rc=&syserr;
        ods output close;
        %if &fit_rc>4 %then %return;
        %if not %sysfunc(exist(work._cf_parameters)) or
            not %sysfunc(exist(work._cf_anova)) or
            not %sysfunc(exist(work._cf_fitted)) or
            not %sysfunc(exist(work.car_model_&current,ITEMSTOR)) %then %do;
            %put ERROR: &current did not produce all required model outputs.;
            %return;
        %end;

        /* Model DF + intercept is the rank, allowing for GLM CLASS coding.
           Redundant GLM indicator parameters are expected; a rank below the
           identifiable model's expected rank is an actual fitting failure. */
        proc sql noprint;
            select count(*),coalesce(sum(nmiss(predicted,residual)>0),0)
              into :fitted_n trimmed,:fitted_bad trimmed from work._cf_fitted;
            create table work._cf_diagnostics as
              select "&current" as model length=8, &n as n,
                     &expected_rank as expected_rank,
                     max(case when upcase(strip(Source))='MODEL' then DF+1 else . end) as model_rank,
                     max(case when upcase(strip(Source))='ERROR' then DF else . end) as error_df,
                     max(case when upcase(strip(Source))='ERROR' then SS else . end) as sse,
                     max(case when upcase(strip(Source))='ERROR' then MS else . end) as mse
              from work._cf_anova;
        quit;
        %if &sqlrc ne 0 %then %return;
        data _null_;
            set work._cf_diagnostics;
            call symputx('diag_rows',nmiss(model_rank,error_df,sse,mse),'L');
            call symputx('model_rank',model_rank,'L');
            call symputx('error_df',error_df,'L');
        run;
        %if &fitted_n ne &n or &fitted_bad>0 or &diag_rows>0 or
            &model_rank ne &expected_rank or &error_df<=0 %then %do;
            %put ERROR: &current failed population/rank/DF checks. Expected rank=&expected_rank actual=&model_rank error_DF=&error_df..;
            %return;
        %end;
        data work._cf_parameters;
            length model $8 Parameter $256;
            set work._cf_parameters;
            model="&current";
            keep model Parameter Estimate StdErr tValue Probt;
        run;
        data work._cf_fitted;
            length model $8;
            set work._cf_fitted;
            model="&current";
            keep model usubjid trt aval predicted residual;
        run;
        /* PROC APPEND creates the base on the first iteration; no FORCE. */
        proc append base=work.model_parameters data=work._cf_parameters; run;
        %if &syserr>4 %then %return;
        proc append base=work.model_fitted data=work._cf_fitted; run;
        %if &syserr>4 %then %return;
        proc append base=work.model_diagnostics data=work._cf_diagnostics; run;
        %if &syserr>4 %then %return;
    %end;
    %let car_fit_rc=0;
%mend;

%macro car_fit(data=work.analysis_data, method=ALL);
    %global car_fit_rc;
    %let car_fit_rc=1;
    %_car_fit_clear;
    %_car_fit_impl(data=&data,method=%upcase(&method));
    %if &car_fit_rc ne 0 %then %do;
        %_car_fit_clear;
        %put ERROR: Program 02 failed. Model outputs have been invalidated.;
    %end;
%mend car_fit;

/* Default driver. Later calls can request just one method. */
%macro _car_fit_driver;
    %car_fit();
    %if &car_fit_rc ne 0 %then %do;
        %abort cancel;
    %end;
    proc print data=work.model_diagnostics noobs; run;
    %put NOTE: Program 02 completed. Working models only. CAR inference is pending.;
%mend;
%_car_fit_driver;
