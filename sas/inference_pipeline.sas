/*
 * Use the generated run/run.sas for configuration and dependencies.
 * The inference pipeline directly consumes the selected model outputs from Programs 02 and 03.
 * Run Program 02 and the unchanged Program 03 before invoking this macro.
 * Supports the numeric arms retained by 01, including all three source arms.
 * Requires SAS/STAT and SAS/IML. See doc/validation_status.md for verification scope.
 * Pass the documented design explicitly. Example:
 * %car_inference(car_scheme=simple);
 * That is an algorithm demonstration unless the actual design is verified.
 * R comparison: use the same selected model and the identical arm subset/order.
 */

%macro car_inference(
    car_scheme = ,
    alpha      = 0.05,
    model      = ANCOVA
);
    %local n _car_example_outputs _car_macro_index _car_required_macro;
    %global car_rc _car_error_rc;
    %let car_rc = 1;
    %let _car_error_rc = 0;
    %if not %sysmacexist(car_output_guard) %then %do;
        %let car_rc=1;
        %put ERROR: [CAR] Load 00_car_common.sas before the pipeline.;
        %return;
    %end;
    /* Check dependencies before fitting or invalidating previous outputs. */
    %do _car_macro_index=1 %to 3;
        %let _car_required_macro=%scan(car_calibrate car_variance car_contrast,
            &_car_macro_index);
        %if not %sysmacexist(&_car_required_macro) %then %do;
            %let _car_error_rc=1;
            %put ERROR: [CAR] Required macro &_car_required_macro is not loaded. Load Programs 04-06 in this SAS session.;
            %return;
        %end;
    %end;
    %let _car_example_outputs = work.car_run_settings work.car_mean_vcov
        work.car_mean_inference work.car_variance_components work.car_stratum_residuals
        work.car_contrast_coefficients work.car_contrast_results work.car_contrast_vcov
        work.car_cal_predictions work.car_cal_means work.car_cal_diagnostics
        work.car_cal_vcov work.car_cal_inference work.car_cal_components
        work.car_cal_stratum_residuals work.car_cal_contrasts work.car_cal_contrast_vcov;
    %car_output_guard(
        inputs   = work.analysis_data work.aipw_predictions work.aipw_means,
        outputs  = &_car_example_outputs,
        expected = 17
    );
    %if &_car_error_rc %then %return;
    %car_clear(outputs=&_car_example_outputs);
    %if &_car_error_rc %then %goto example_fail;
    %let model=%qupcase(%superq(model));
    %if "%superq(model)" ne "ANOVA" and "%superq(model)" ne "ANCOVA"
        and "%superq(model)" ne "ANHECOVA" %then %do;
        %car_error(message=MODEL must be ANOVA or ANCOVA or ANHECOVA.);
        %goto example_fail;
    %end;
    %car_alpha(value=%superq(alpha));
    %if &_car_error_rc %then %goto example_fail;
    %if %length(%superq(car_scheme)) = 0 %then %do;
        %car_error(message=Supply the documented CAR_SCHEME before running this pipeline.);
        %goto example_fail;
    %end;

    %if not %symexist(car_aipw_rc) %then %do;
        %car_error(message=Run Program 03 successfully before inference.);
        %goto example_fail;
    %end;
    %if &car_aipw_rc ne 0 %then %do;
        %car_error(message=Program 03 did not succeed. Its outputs cannot be used.);
        %goto example_fail;
    %end;
    proc sql noprint;
        select count(*) into :n trimmed from work.analysis_data;
    quit;
    %car_step(context=Analysis population count, sql=YES);
    %if &_car_error_rc %then %goto example_fail;

    %car_variance(
        model          = &model,
        car_scheme = &car_scheme,
        alpha      = &alpha
    );
    %if &_car_error_rc %then
        %goto example_fail;

    /* Active-minus-lowest-treatment coefficients, keyed by actual labels. */
    proc sql;
        create table work.car_contrast_coefficients as
        select cats('DIFF',put(a.arm_index-1,best12.)) as contrast_id length=12,
            catx(' ','Treatment',put(a.trt,best12.),'minus',put(b.trt,best12.))
                as label length=80,
            c.trt as target_trt,
            (c.trt=a.trt)-(c.trt=b.trt) as coefficient,0 as null_value
        from work._car_arms a cross join work._car_arms b cross join work._car_arms c
        where a.arm_index>1 and b.arm_index=1
        order by contrast_id,target_trt;
    quit;
    %car_step(context=Treatment contrasts, sql=YES);
    %if &_car_error_rc %then %goto example_fail;

    %car_contrast(model=&model, alpha=&alpha);
    %if &_car_error_rc %then
        %goto example_fail;
    %car_calibrate(model=&model);
    %if &_car_error_rc %then
        %goto example_fail;
    %car_variance(
        model          = &model,
        predictions    = work.car_cal_predictions,
        means          = work.car_cal_means,
        car_scheme     = &car_scheme,
        alpha          = &alpha,
        out_vcov       = work.car_cal_vcov,
        out_inference  = work.car_cal_inference,
        out_components = work.car_cal_components,
        out_residuals  = work.car_cal_stratum_residuals
    );
    %if &_car_error_rc %then
        %goto example_fail;
    %car_contrast(
        model    = &model,
        means    = work.car_cal_means,
        vcov     = work.car_cal_vcov,
        alpha    = &alpha,
        out      = work.car_cal_contrasts,
        out_vcov = work.car_cal_contrast_vcov
    );
    %if &_car_error_rc %then
        %goto example_fail;

    proc print data = work.car_mean_inference;
    run;
    %car_step(context=Inference step);
    %if &_car_error_rc %then %goto example_fail;

    proc print data = work.car_contrast_results;
    run;
    %car_step(context=Inference step);
    %if &_car_error_rc %then %goto example_fail;

    proc print data = work.car_cal_inference;
    run;
    %car_step(context=Inference step);
    %if &_car_error_rc %then %goto example_fail;

    proc print data = work.car_cal_contrasts;
    run;
    %car_step(context=Inference step);
    %if &_car_error_rc %then %goto example_fail;

    /* Saved settings identify this exact analysis run for independent validation. */
    data work.car_run_settings;
        length model $8 car_scheme $14 joint $3 add_x $256;
        model = "&model";
        car_scheme = lowcase("&car_scheme");
        variance_type = 1;
        alpha = &alpha;
        joint = 'YES';
        add_x = '';
        n = &n;
    run;
    %car_step(context=Run settings publication);
    %if &_car_error_rc %then %goto example_fail;
    %let car_rc = 0;
    %put NOTE: [CAR] Computation complete. Invoke CAR_TEST_INFERENCE to compare reference results.;
    %return;

%example_fail:
    %car_clear(outputs=&_car_example_outputs);
    %let car_rc=1;
%mend;

/*==========================================================================
 Macro   : _car_pipeline_prepare
 Purpose : Clear earlier pipeline results and fit the models needed by 03.

 INPUT  : WORK.ANALYSIS_DATA and loaded Program 02 macros.
 OUTPUT : Program 02 fits; initialized pipeline return codes.

 IMPORTANT:
 - The builder calls this before embedding the unchanged Program 03 source.
 - Program 03's automatic driver requires ALL working models.
==========================================================================*/
%macro _car_pipeline_prepare;
    %global car_rc _car_error_rc car_fit_rc car_aipw_rc car_suite_rc;
    %local _car_pipeline_outputs;
    %let car_rc=1;
    %let _car_error_rc=0;
    %let car_fit_rc=1;
    %let car_aipw_rc=1;
    %let car_suite_rc=1;
    /* Invalidate earlier pipeline results before 02/03 can fail or abort.
       Program 02 clears its own MODEL_* datasets and item stores. */
    %let _car_pipeline_outputs=work.aipw_predictions work.aipw_means
        work.car_run_settings work.car_mean_vcov
        work.car_mean_inference work.car_variance_components work.car_stratum_residuals
        work.car_contrast_coefficients work.car_contrast_results work.car_contrast_vcov
        work.car_cal_predictions work.car_cal_means work.car_cal_diagnostics
        work.car_cal_vcov work.car_cal_inference work.car_cal_components
        work.car_cal_stratum_residuals work.car_cal_contrasts work.car_cal_contrast_vcov
        work.car_validation_suite work.car_validation_details;
    %car_output_guard(
        inputs   = work.analysis_data,
        outputs  = &_car_pipeline_outputs,
        expected = 21
    );
    %if &_car_error_rc %then %abort cancel;
    %car_clear(outputs=&_car_pipeline_outputs);
    %if &_car_error_rc %then %abort cancel;

    %car_fit(data=work.analysis_data, method=ALL);
    %put NOTE: CAR_FIT_RC=&car_fit_rc;
    %if &car_fit_rc ne 0 %then %do;
        %put ERROR: Program 02 failed. Program 03 was not run.;
        %abort cancel;
    %end;
%mend;

/*==========================================================================
 Macro   : _car_pipeline_finish
 Purpose : Run inference and reference comparison after Program 03 succeeds.

 INPUT  : Native Program 03 outputs and shared configuration.
 OUTPUT : Original/calibrated inference and validation reports.

 IMPORTANT:
 - Called by the builder after loading all macro dependencies.
 - Missing references return CAR_SUITE_RC=2; computation alone is unvalidated.
==========================================================================*/
%macro _car_pipeline_finish;
    %put NOTE: CAR_AIPW_RC=&car_aipw_rc;
    %if &car_aipw_rc ne 0 %then %do;
        %put ERROR: Program 03 failed. Inference was not run.;
        %abort cancel;
    %end;
    %car_inference(
        model      = &analysis_model,
        car_scheme = &analysis_scheme,
        alpha      = &analysis_alpha
    );
    %put NOTE: ANALYSIS_MODEL=&analysis_model;
    %put NOTE: EXAMPLE_RC=&car_rc;
    %if &car_rc ne 0 %then %do;
        %put ERROR: Analysis failed. Reference comparison was not run.;
        %abort cancel;
    %end;
    %car_test_inference(
        reference_dir = %superq(car_inference_reference_dir)
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

/* Automatic compact export; maintained here with the active pipeline. */
%macro _car_export_one(table,filename);
    %if %sysfunc(exist(work.&table)) %then %do;
        proc export data=work.&table
            outfile="&car_export_dir./&filename..csv"
            dbms=csv replace;
        run;
        %if &syserr>4 %then %do;
            %put ERROR: Failed to export WORK.&table.. Check directory permissions.;
            %car_report_finish;
            %abort cancel;
        %end;
        %let car_export_count=%eval(&car_export_count+1);
        %put NOTE: Exported WORK.&table to &car_export_dir./&filename..csv.;
    %end;
    %else %put WARNING: Expected result WORK.&table is unavailable for export.;
%mend;

%macro _car_export_plot(table,x,y,image);
    %if %sysfunc(exist(work.&table)) %then %do;
        ods graphics / reset=index imagename="&image";
        proc sgplot data=work.&table;
            scatter x=&x y=&y / yerrorlower=lcl yerrorupper=ucl;
            xaxis type=discrete;
            yaxis label="&_car_export_model estimate and confidence interval";
        run;
        %if &syserr>4 %then %let _car_report_failed=1;
        %else %let car_export_plot_count=%eval(&car_export_plot_count+1);
    %end;
%mend;

%macro car_export_results;
    %global car_export_count car_export_plot_count;
    %local tables i table dsid n_qc close_rc _car_report_failed _car_export_model;
    %let car_export_count=0;
    %let car_export_plot_count=0;
    %let _car_report_failed=0;
    %if not %symexist(car_export_dir) %then %do;
        %put ERROR: Run the generated inference workflow to configure the export path.;
        %abort cancel;
    %end;
    %if %length(%superq(car_export_dir))=0 %then %do;
        %put ERROR: Configure SERVER_EXPORT_DIR in JSON and rebuild the inference run.;
        %abort cancel;
    %end;

    /* Default compact deliverables: final results, context and verification. */
    %let tables=
        car_mean_inference car_contrast_results
        car_cal_inference car_cal_contrasts
        car_run_settings car_validation_suite
        allocation_summary baseline_summary
    ;
    %do i=1 %to %sysfunc(countw(&tables));
        %let table=%scan(&tables,&i);
        %_car_export_one(&table,&table);
    %end;

    /* Retain detailed comparisons only when the suite reports failure. */
    %if %symexist(car_suite_rc) %then %do;
        %if &car_suite_rc=1 %then %do;
            %_car_export_one(car_validation_details,car_validation_details);
        %end;
    %end;
    /* Empty QC tables add no findings to the deliverables. */
    %if %sysfunc(exist(work.qc_issues)) %then %do;
        %let dsid=%sysfunc(open(work.qc_issues,i));
        %if &dsid>0 %then %do;
            %let n_qc=%sysfunc(attrn(&dsid,nlobs));
            %let close_rc=%sysfunc(close(&dsid));
            %if &n_qc>0 %then %do;
                %_car_export_one(qc_issues,qc_issues);
            %end;
        %end;
        %else %put WARNING: Cannot inspect WORK.QC_ISSUES for export.;
    %end;

    proc sql noprint;
        select model into :_car_export_model trimmed from work.car_run_settings;
    quit;
    %if &sqlrc ne 0 %then %do;
        %put ERROR: Cannot read the selected model for export.;
        %car_report_finish;
        %abort cancel;
    %end;

    /* Append plots to full_results.html; no second HTML report is generated. */
    ods graphics on / push outputfmt=png width=7in height=4.5in;
    %_car_export_plot(car_mean_inference,target_trt,aipw_mean,original_means);
    %_car_export_plot(car_contrast_results,contrast_id,estimate,original_contrasts);
    %_car_export_plot(car_cal_inference,target_trt,aipw_mean,calibrated_means);
    %_car_export_plot(car_cal_contrasts,contrast_id,estimate,calibrated_contrasts);
    ods graphics / pop;

    /* Keep PASS/FAIL checks as the final table, after the appended plots. */
    %if %sysfunc(exist(work.car_validation_suite)) %then %do;
        proc print data=work.car_validation_suite noobs;
        run;
        %if &syserr>4 %then %let _car_report_failed=1;
    %end;
    %if &_car_report_failed %then %do;
        %put ERROR: Export report generation failed. Check the SAS log.;
        %car_report_finish;
        %abort cancel;
    %end;
    %put NOTE: Compact export complete: &car_export_count CSVs and &car_export_plot_count plots in &car_export_dir..;
    %put NOTE: Export completion does not establish validation success. Inspect CAR_SUITE_RC and CAR_VALIDATION_SUITE.;
%mend;
