/* Source for generated run/run_inference.sas. The builder embeds configuration,
   all macro dependencies and Program 01 before this driver. */
%macro _car_run_inference;
    %car_worked_example(
        car_scheme=&analysis_scheme,
        alpha=&analysis_alpha
    );
    %put NOTE: EXAMPLE_RC=&car_rc;
    %if &car_rc ne 0 %then %do;
        %put ERROR: Analysis failed. Reference comparison was not run.;
        %abort cancel;
    %end;
    %car_test_inference(
        reference_dir=%superq(car_inference_reference_dir)
    );
    %put NOTE: CAR_SUITE_RC=&car_suite_rc;
    %put NOTE: Expected CAR_SUITE_RC=0 and all summary checks PASS.;
    %if %sysfunc(exist(work.car_validation_suite)) %then %do;
        proc print data=work.car_validation_suite;
        run;
    %end;
    %if &car_suite_rc=1
        and %sysfunc(exist(work.car_validation_details)) %then %do;
        proc print data=work.car_validation_details(obs=50);
        run;
    %end;
%mend;
%_car_run_inference;
