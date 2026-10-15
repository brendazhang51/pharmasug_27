/* Run Program 01 and Program 02 in the same session before this file.
   Tests expect the original 500-row, three-arm example in ANALYSIS_DATA.
   Optional: set reference_dir to a server directory containing R reference
   CSVs from reference_outcome_models.R for the SAME selected population. */
/* Keyword parameters keep comparison operators from becoming parameter names. */

%macro p02_assert(condition=, message=);
    %if not (&condition) %then %do;
        %put ERROR: PROGRAM 02 TEST FAILED: &message;
        %abort cancel;
    %end;
%mend;

%car_fit();
%p02_assert(
    condition=&car_fit_rc=0,
    message=Three-arm fit succeeds
);
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
%p02_assert(
    condition=&p02_n=1500 and &p02_models=3 and &p02_bad=0,
    message=Population and ranks
);
%p02_assert(
    condition=%sysevalf(&p02_identity<1e-8),
    message=Observed outcome identity
);
%p02_assert(
    condition=%sysevalf(&p02_anova<1e-8),
    message=ANOVA reproduces arm means
);

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
        %p02_assert(
            condition=&p02_matched=500 and &p02_bad=0,
            message=PLM reproduces GLM predictions
        );
    %end;
%mend;
%p02_score_test;

/* Optional independent R comparison: full joins detect missing/extra keys. */
%macro p02_compare_r;
    %local p02_bad import_bad p02_fitted_rows p02_diag_rows p02_diag_bad;
    %let import_bad=0;
    proc datasets library=work nolist nowarn;
        delete p02_r_fitted_compare p02_r_diagnostics_compare p02_r_summary
               _p02_r_fitted _p02_r_diag _p02_compare_preview;
    quit;
    %if not %symexist(reference_dir) %then %return;
    %if %length(%superq(reference_dir))=0 %then %return;
    %p02_assert(
        condition=%sysfunc(fileexist(%superq(reference_dir)/reference_fitted.csv)) eq 1,
        message=R fitted CSV is accessible
    );
    %p02_assert(
        condition=%sysfunc(fileexist(%superq(reference_dir)/reference_diagnostics.csv)) eq 1,
        message=R diagnostics CSV is accessible
    );
    /* R quotes numeric fields to preserve 17-digit precision. Do not infer types. */
    data work._p02_r_fitted;
        length model $8 usubjid $32 trt aval predicted residual 8;
        infile "&reference_dir./reference_fitted.csv"
            dsd dlm=',' firstobs=2 lrecl=32767 truncover;
        input model :$8. usubjid :$32. trt :best32. aval :best32.
              predicted :best32. residual :best32.;
        if _error_ then call symputx('import_bad',1,'L');
    run;
    %p02_assert(
        condition=&syserr=0 and &import_bad=0,
        message=R fitted CSV imports successfully
    );
    data work._p02_r_diag;
        length model $8 n expected_rank model_rank error_df sse mse 8;
        infile "&reference_dir./reference_diagnostics.csv"
            dsd dlm=',' firstobs=2 lrecl=32767 truncover;
        input model :$8. n :best32. expected_rank :best32. model_rank :best32.
              error_df :best32. sse :best32. mse :best32.;
        if _error_ then call symputx('import_bad',1,'L');
    run;
    %p02_assert(
        condition=&syserr=0 and &import_bad=0,
        message=R diagnostics CSV imports successfully
    );
    /* Keep every matched or unmatched key so differences can be inspected. */
    proc sql noprint;
        create table work.p02_r_fitted_compare as
          select coalescec(s.model,r.model) as model length=12,
                 coalescec(s.usubjid,r.usubjid) as usubjid length=32,
                 s.trt as sas_trt, r.trt as r_trt,
                 s.aval as sas_aval, r.aval as r_aval,
                 s.predicted as sas_predicted, r.predicted as r_predicted,
                 abs(s.predicted-r.predicted) as abs_predicted_diff,
                 s.residual as sas_residual, r.residual as r_residual,
                 abs(s.residual-r.residual) as abs_residual_diff,
                 case when missing(s.model) or missing(r.model)
                           or nmiss(s.trt,r.trt,s.aval,r.aval,
                                    s.predicted,r.predicted,s.residual,r.residual)>0
                           or s.trt ne r.trt
                           or abs(s.aval-r.aval)>1e-8+1e-8*abs(r.aval)
                           or abs(s.predicted-r.predicted)>1e-8+1e-8*abs(r.predicted)
                           or abs(s.residual-r.residual)>1e-8+1e-8*abs(r.residual)
                      then 1 else 0 end as mismatch
          from work.model_fitted as s full join work._p02_r_fitted as r
          on s.model=r.model and s.usubjid=r.usubjid;
        create table work.p02_r_diagnostics_compare as
          select coalescec(s.model,r.model) as model length=12,
                 s.n as sas_n, r.n as r_n,
                 s.model_rank as sas_rank, r.model_rank as r_rank,
                 s.error_df as sas_error_df, r.error_df as r_error_df,
                 s.sse as sas_sse, r.sse as r_sse,
                 abs(s.sse-r.sse) as abs_sse_diff,
                 s.mse as sas_mse, r.mse as r_mse,
                 abs(s.mse-r.mse) as abs_mse_diff,
                 case when missing(s.model) or missing(r.model)
                           or nmiss(s.n,r.n,s.model_rank,r.model_rank,
                                    s.error_df,r.error_df,s.sse,r.sse,s.mse,r.mse)>0
                           or s.n ne r.n or s.model_rank ne r.model_rank
                           or s.error_df ne r.error_df
                           or abs(s.sse-r.sse)>1e-8+1e-8*abs(r.sse)
                           or abs(s.mse-r.mse)>1e-8+1e-8*abs(r.mse)
                      then 1 else 0 end as mismatch
          from work.model_diagnostics as s full join work._p02_r_diag as r
          on s.model=r.model;
        create table work.p02_r_summary as
          select model, count(*) as compared_rows,
                 sum(mismatch) as mismatched_rows,
                 max(abs_predicted_diff) as max_abs_predicted_diff,
                 max(abs_residual_diff) as max_abs_residual_diff
          from work.p02_r_fitted_compare group by model;
    quit;
    %p02_assert(
        condition=&sqlrc eq 0,
        message=R comparison tables were created
    );

    proc sort data=work.p02_r_fitted_compare;
        by model usubjid;
    run;
    data work._p02_compare_preview;
        set work.p02_r_fitted_compare;
        by model;
        retain row_in_model;
        if first.model then row_in_model=0;
        row_in_model+1;
        if row_in_model<=3 then output;
        drop row_in_model;
    run;
    title 'SAS versus R: fitted-value comparison by model';
    proc print data=work.p02_r_summary noobs; run;
    title 'SAS versus R: example fitted values (three subjects per model)';
    proc print data=work._p02_compare_preview noobs;
        var model usubjid sas_trt r_trt sas_predicted r_predicted
            abs_predicted_diff sas_residual r_residual abs_residual_diff mismatch;
        format sas_predicted r_predicted sas_residual r_residual 16.10
               abs_predicted_diff abs_residual_diff e12.4;
    run;
    title 'SAS versus R: model diagnostics';
    proc print data=work.p02_r_diagnostics_compare noobs;
        format sas_sse r_sse sas_mse r_mse 16.10
               abs_sse_diff abs_mse_diff e12.4;
    run;
    title;
    %let p02_fitted_rows=0;
    %let p02_diag_rows=0;
    %let p02_bad=1;
    %let p02_diag_bad=1;
    proc sql noprint;
        select count(*),sum(mismatch) into :p02_fitted_rows,:p02_bad
          from work.p02_r_fitted_compare;
        select count(*),sum(mismatch) into :p02_diag_rows,:p02_diag_bad
          from work.p02_r_diagnostics_compare;
    quit;
    %p02_assert(
        condition=&sqlrc eq 0,
        message=R comparison counts succeed
    );
    %p02_assert(
        condition=&p02_fitted_rows eq 1500 and &p02_diag_rows eq 3,
        message=R comparison row counts agree
    );
    %if &p02_bad>0 %then %do;
        title 'SAS versus R: first 20 fitted-value mismatches';
        proc sql outobs=20;
            select * from work.p02_r_fitted_compare
              where mismatch=1 order by model,usubjid;
        quit;
        title;
    %end;
    %p02_assert(
        condition=&p02_bad eq 0,
        message=R input outcomes fitted values and residuals agree
    );
    %p02_assert(
        condition=&p02_diag_bad eq 0,
        message=R SSE MSE and degrees of freedom agree
    );
    %put NOTE: Program 02 R reference comparison passed.;
    %put NOTE: SAS and R outcome-model comparisons passed. See WORK.P02_R_SUMMARY and WORK.P02_R_*_COMPARE.;
%mend;
%p02_compare_r;

data work._p02_two; set work.analysis_data; where trt in (0,1); run;
%car_fit(data=work._p02_two);
%p02_assert(
    condition=&car_fit_rc=0,
    message=Two-arm fit succeeds
);
proc sql noprint;
    select count(*) into :p02_n from work.model_fitted;
quit;
%p02_assert(
    condition=&p02_n=906,
    message=Two-arm population preserved
);

%car_fit(method=ANCOVA);
%p02_assert(
    condition=&car_fit_rc=0,
    message=Single-method API succeeds
);
%p02_assert(
    condition=%sysfunc(exist(work.car_model_anova,ITEMSTOR))=0,
    message=Previous item stores removed
);

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
        %p02_assert(
            condition=&car_fit_rc=1,
            message=Invalid input is rejected
        );
        %p02_assert(
            condition=%sysfunc(exist(work.model_fitted))=0,
            message=No stale or partial fitted output
        );
        %p02_assert(
            condition=%sysfunc(exist(work.car_model_anova,ITEMSTOR))=0,
            message=No stale or partial store
        );
    %end;
%mend;
%p02_negative_tests;
%car_fit(data=work._p02_missing);
%p02_assert(
    condition=&car_fit_rc=1,
    message=Absent dataset rejected
);
%car_fit(method=INVALID);
%p02_assert(
    condition=&car_fit_rc=1,
    message=Invalid method rejected
);

/* Restore the default outputs for subsequent work. */
%car_fit();
%p02_assert(
    condition=&car_fit_rc=0,
    message=Default results restored
);
%put NOTE: Program 02 tests passed. R comparison runs only when REFERENCE_DIR is set.;
