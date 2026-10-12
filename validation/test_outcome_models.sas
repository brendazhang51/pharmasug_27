/* Run Program 01 and Program 02 in the same session before this file.
   Tests expect the original 500-row, three-arm example in ANALYSIS_DATA.
   Optional: set reference_dir to a server directory containing R reference
   CSVs from reference_outcome_models.R for the SAME selected population. */
%macro p02_assert(condition,message);
    %if not (&condition) %then %do;
        %put ERROR: PROGRAM 02 TEST FAILED: &message;
        %abort cancel;
    %end;
%mend;

%car_fit();
%p02_assert(&car_fit_rc=0,Three-arm fit succeeds);
proc sql noprint;
    select count(*),count(distinct model),max(abs(aval-predicted-residual))
      into :p02_n,:p02_models,:p02_identity from work.model_fitted;
    select count(*) into :p02_bad from work.model_diagnostics
      where n ne 500 or model_rank ne expected_rank or error_df ne n-model_rank;
    select max(abs(a.predicted-b.arm_mean)) into :p02_anova
      from work.model_fitted as a inner join
        (select trt,mean(aval) as arm_mean from work.analysis_data group by trt) as b
      on a.trt=b.trt where a.model='ANOVA';
quit;
%p02_assert(&p02_n=1500 and &p02_models=3 and &p02_bad=0,Population and ranks);
%p02_assert(%sysevalf(&p02_identity<1e-8),Observed outcome identity);
%p02_assert(%sysevalf(&p02_anova<1e-8),ANOVA reproduces arm means);

/* Verify the exact item stores that Program 03 will use for scoring. */
%macro p02_score_test;
    %local j method;
    %do j=1 %to 3;
        %let method=%scan(ANOVA ANCOVA ANHECOVA,&j);
        proc plm restore=work.car_model_&method;
            score data=work.analysis_data out=work._p02_scored predicted=plm_predicted;
        run;
        proc sql noprint;
            select count(*),coalesce(sum(missing(s.plm_predicted) or
              abs(s.plm_predicted-f.predicted)>1e-8+1e-8*abs(f.predicted)),0)
              into :p02_matched,:p02_bad
              from work._p02_scored as s inner join work.model_fitted as f
              on s.usubjid=f.usubjid where f.model="&method";
        quit;
        %p02_assert(&p02_matched=500 and &p02_bad=0,PLM reproduces GLM predictions);
    %end;
%mend;
%p02_score_test;

/* Optional independent R comparison: full joins detect missing/extra keys. */
%macro p02_compare_r;
    %if not %symexist(reference_dir) %then %return;
    %if %length(%superq(reference_dir))=0 %then %return;
    proc import datafile="&reference_dir./reference_fitted.csv"
      out=work._p02_r_fitted dbms=csv replace; guessingrows=max; run;
    proc import datafile="&reference_dir./reference_diagnostics.csv"
      out=work._p02_r_diag dbms=csv replace; guessingrows=max; run;
    proc sql noprint;
        select count(*) into :p02_bad
          from work.model_fitted as s full join work._p02_r_fitted as r
          on s.model=r.model and s.usubjid=r.usubjid
          where missing(s.model) or missing(r.model) or s.trt ne r.trt
            or nmiss(s.predicted,r.predicted,s.residual,r.residual)>0
            or abs(s.predicted-r.predicted)>1e-8+1e-8*abs(r.predicted)
            or abs(s.residual-r.residual)>1e-8+1e-8*abs(r.residual);
    quit;
    %p02_assert(&p02_bad=0,R fitted values and residuals agree);
    proc sql noprint;
        select count(*) into :p02_bad
          from work.model_diagnostics as s full join work._p02_r_diag as r
          on s.model=r.model
          where missing(s.model) or missing(r.model) or s.n ne r.n
            or s.model_rank ne r.model_rank or s.error_df ne r.error_df
            or nmiss(s.sse,r.sse,s.mse,r.mse)>0
            or abs(s.sse-r.sse)>1e-8+1e-8*abs(r.sse)
            or abs(s.mse-r.mse)>1e-8+1e-8*abs(r.mse);
    quit;
    %p02_assert(&p02_bad=0,R SSE MSE and degrees of freedom agree);
%mend;
%p02_compare_r;

data work._p02_two; set work.analysis_data; where trt in (0,1); run;
%car_fit(data=work._p02_two);
%p02_assert(&car_fit_rc=0,Two-arm fit succeeds);
proc sql noprint;
    select count(*) into :p02_n from work.model_fitted;
quit;
%p02_assert(&p02_n=906,Two-arm population preserved);

%car_fit(method=ANCOVA);
%p02_assert(&car_fit_rc=0,Single-method API succeeds);
%p02_assert(%sysfunc(exist(work.car_model_anova,ITEMSTOR))=0,Previous item stores removed);

%macro p02_negative_tests;
    %local case;
    %do case=1 %to 11;
        data work._p02_bad;
            set work.analysis_data;
            %if &case=1 %then %do; if _n_=1 then aval=.; %end;
            %if &case=2 %then %do; usubjid='DUPLICATE'; %end;
            %if &case=3 %then %do; if trt ne 0 then delete; %end;
            %if &case=4 %then %do; x3_analysis=x1_analysis; %end;
            %if &case=5 %then %do; delete; %end;
            %if &case=6 %then %do; drop x3_analysis; %end;
            %if &case=7 %then %do; if trt=0 and usubjid ne 'SRC00000001' then delete; %end;
            %if &case=8 %then %do; if _n_=1 then x1_analysis=.; %end;
            %if &case=9 %then %do; if _n_=1 then usubjid=' '; %end;
            %if &case=10 %then %do;
                length character_outcome $20;
                character_outcome=put(aval,best16.);
                drop aval;
                rename character_outcome=aval;
            %end;
            /* Four rows cannot support a full-rank, positive-DF ANHECOVA. */
            %if &case=11 %then %do;
                if _n_>4 then delete;
                trt=floor((_n_-1)/2);
            %end;
        run;
        %car_fit(data=work._p02_bad);
        %p02_assert(&car_fit_rc=1,Invalid input is rejected);
        %p02_assert(%sysfunc(exist(work.model_fitted))=0,No stale or partial fitted output);
        %p02_assert(%sysfunc(exist(work.car_model_anova,ITEMSTOR))=0,No stale or partial store);
    %end;
%mend;
%p02_negative_tests;
%car_fit(data=work._p02_missing);
%p02_assert(&car_fit_rc=1,Absent dataset rejected);
%car_fit(method=INVALID);
%p02_assert(&car_fit_rc=1,Invalid method rejected);

/* Restore the default outputs for subsequent work. */
%car_fit();
%p02_assert(&car_fit_rc=0,Default results restored);
%put NOTE: Program 02 tests passed. R comparison runs only when REFERENCE_DIR is set.;
