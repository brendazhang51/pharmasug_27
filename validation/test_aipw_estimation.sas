/* Run Programs 01, 02, and 03 in one SAS session before this file.
   Optional: set reference_dir to the SAS-server directory containing
   reference_aipw_predictions.csv and reference_aipw_means.csv. */

/* Set REFERENCE_DIR in the session to enable optional R comparison. */


%macro p03_assert(condition=,message=);
    %if not (&condition) %then %do;
        %put ERROR: PROGRAM 03 TEST FAILED: &message;
        %abort cancel;
    %end;
%mend;

%car_aipw();
%p03_assert(condition=&car_aipw_rc eq 0,message=Three-arm AIPW calculation succeeds);
proc sql noprint;
    select count(*),count(distinct model),
           coalesce(sum(missing(predicted)),0),
           coalesce(sum((observed_trt=target_trt and
                         missing(observed_residual)) or
                        (observed_trt ne target_trt and
                         not missing(observed_residual))),0)
      into :p03_predictions,:p03_models,:p03_missing,:p03_residual_bad
      from work.aipw_predictions;
    select count(*),coalesce(sum(n_total ne 500 or n_arm<2 or
           nmiss(observed_mean,mean_pred_all,mean_pred_arm,
                 mean_residual_arm,aipw_mean)>0 or
           abs(aipw_mean-observed_mean+mean_pred_arm-mean_pred_all)>1e-8),0)
      into :p03_means,:p03_bad from work.aipw_means;
    select count(*) into :p03_anova_bad
      from work.aipw_means where model='ANOVA' and
           abs(aipw_mean-observed_mean)>1e-8;
quit;
%p03_assert(condition=&sqlrc eq 0,message=Program 03 summary queries succeed);
%p03_assert(condition=&p03_predictions eq 4500 and &p03_models eq 3 and
            &p03_missing eq 0 and &p03_residual_bad eq 0,message=
            Expected prediction population);
%p03_assert(condition=&p03_means eq 9 and &p03_bad eq 0 and
            &p03_anova_bad eq 0,message=AIPW means and ANOVA identity);

%macro p03_compare_r;
    proc datasets library=work nolist nowarn;
        delete p03_r_mean_compare _p03_r_predictions _p03_r_means;
    quit;
    %if not %symexist(reference_dir) %then %return;
    %if %length(%superq(reference_dir))=0 %then %return;
    %p03_assert(condition=%sysfunc(fileexist(%superq(reference_dir)/reference_aipw_predictions.csv)) eq 1,message=R predictions CSV is accessible);
    %p03_assert(condition=%sysfunc(fileexist(%superq(reference_dir)/reference_aipw_means.csv)) eq 1,message=R means CSV is accessible);
    data work._p03_r_predictions;
        length model $12 usubjid $11;
        infile "&reference_dir./reference_aipw_predictions.csv"
            dsd firstobs=2 truncover lrecl=32767;
        input model :$12. usubjid :$11. observed_trt :best32.
              target_trt :best32. aval :best32. predicted :best32.
              observed_residual :best32.;
    run;
    data work._p03_r_means;
        length model $12;
        infile "&reference_dir./reference_aipw_means.csv"
            dsd firstobs=2 truncover lrecl=32767;
        input model :$12. target_trt :best32. n_total :best32.
              n_arm :best32. observed_mean :best32. mean_pred_all :best32.
              mean_pred_arm :best32. mean_residual_arm :best32.
              aipw_mean :best32.;
    run;
    proc sql noprint;
        select count(*) into :p03_r_n from work._p03_r_predictions;
        select count(*) into :p03_r_means_n from work._p03_r_means;
    quit;
    %p03_assert(condition=&sqlrc eq 0,message=R reference counts succeed);
    %p03_assert(condition=&p03_r_n eq 4500 and &p03_r_means_n eq 9,message=R reference population);
    proc sql noprint;
        select count(*) into :p03_bad
          from work.aipw_predictions as s full join work._p03_r_predictions as r
          on s.model=r.model and s.usubjid=r.usubjid and
             s.target_trt=r.target_trt
          where missing(s.model) or missing(r.model) or
                s.observed_trt ne r.observed_trt or
                nmiss(s.aval,r.aval,s.predicted,r.predicted)>0 or
                abs(s.aval-r.aval)>1e-8+1e-8*abs(r.aval) or
                abs(s.predicted-r.predicted)>1e-8+1e-8*abs(r.predicted) or
                (s.target_trt=s.observed_trt and
                 (nmiss(s.observed_residual,r.observed_residual)>0 or
                  abs(s.observed_residual-r.observed_residual)>
                  1e-8+1e-8*abs(r.observed_residual)));
    quit;
    %p03_assert(condition=&sqlrc eq 0,message=R prediction comparison query succeeds);
    %p03_assert(condition=&p03_bad eq 0,message=R arm-specific predictions agree);
    proc sql noprint;
        select count(*) into :p03_bad
          from work.aipw_means as s full join work._p03_r_means as r
          on s.model=r.model and s.target_trt=r.target_trt
          where missing(s.model) or missing(r.model) or
                s.n_total ne r.n_total or s.n_arm ne r.n_arm or
                nmiss(s.observed_mean,r.observed_mean,
                      s.mean_pred_all,r.mean_pred_all,
                      s.mean_pred_arm,r.mean_pred_arm,
                      s.mean_residual_arm,r.mean_residual_arm,
                      s.aipw_mean,r.aipw_mean)>0 or
                abs(s.aipw_mean-r.aipw_mean)>1e-8+1e-8*abs(r.aipw_mean) or
                abs(s.observed_mean-r.observed_mean)>
                    1e-8+1e-8*abs(r.observed_mean) or
                abs(s.mean_pred_all-r.mean_pred_all)>
                    1e-8+1e-8*abs(r.mean_pred_all) or
                abs(s.mean_pred_arm-r.mean_pred_arm)>
                    1e-8+1e-8*abs(r.mean_pred_arm) or
                abs(s.mean_residual_arm-r.mean_residual_arm)>
                    1e-8+1e-8*abs(r.mean_residual_arm);
    quit;
    %p03_assert(condition=&sqlrc eq 0,message=R means comparison query succeeds);
    %p03_assert(condition=&p03_bad eq 0,message=R AIPW means agree);
    proc sql;
        create table work.p03_r_mean_compare as
          select s.model,s.target_trt,s.n_arm,
                 s.aipw_mean as sas_aipw_mean,
                 r.aipw_mean as r_aipw_mean,
                 abs(s.aipw_mean-r.aipw_mean) as absolute_difference
          from work.aipw_means as s inner join work._p03_r_means as r
          on s.model=r.model and s.target_trt=r.target_trt
          order by s.model,s.target_trt;
    quit;
    %p03_assert(condition=&sqlrc eq 0,message=R display table was created);
    title 'Program 03: SAS versus R AIPW arm means';
    proc print data=work.p03_r_mean_compare noobs;
        format sas_aipw_mean r_aipw_mean 16.10 absolute_difference e12.4;
    run;
    title;
    %put NOTE: Program 03 SAS/R predictions and AIPW means agree.;
%mend;
%p03_compare_r;

/* The API must also work when Programs 02 and 03 use the same two-arm subset. */
data work._p03_two;
    set work.analysis_data;
    where trt in (0,1);
run;
%car_fit(data=work._p03_two);
%p03_assert(condition=&car_fit_rc eq 0,message=Two-arm working models succeed);
%car_aipw(data=work._p03_two);
%p03_assert(condition=&car_aipw_rc eq 0,message=Two-arm AIPW calculation succeeds);
proc sql noprint;
    select count(*) into :p03_predictions from work.aipw_predictions;
    select count(*) into :p03_means from work.aipw_means;
quit;
%p03_assert(condition=&sqlrc eq 0,message=Two-arm count queries succeed);
%p03_assert(condition=&p03_predictions eq 1812 and &p03_means eq 6,message=Two-arm output sizes);

/* Restore the full population and outputs for later programs. */
%car_fit();
%p03_assert(condition=&car_fit_rc eq 0,message=Three-arm working models restored);
%car_aipw();
%p03_assert(condition=&car_aipw_rc eq 0,message=Three-arm AIPW outputs restored);
%put NOTE: Program 03 tests passed. R comparison runs only when REFERENCE_DIR is set.;
