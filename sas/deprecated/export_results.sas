/*==========================================================================
 Compact inference export, called automatically by generated run/run.sas.
 Loading this source only defines macros. It uses the already open CARFULL
 HTML destination and the JSON-configured CAR_EXPORT_DIR.
 Exports eight core CSVs, four PNG plots and conditional failure/QC evidence.
 Existing output files may be overwritten; no older files are deleted.
==========================================================================*/

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
            yaxis label="Estimate and confidence interval";
        run;
        %if &syserr>4 %then %let _car_report_failed=1;
        %else %let car_export_plot_count=%eval(&car_export_plot_count+1);
    %end;
%mend;

%macro car_export_results;
    %global car_export_count car_export_plot_count;
    %local tables i table dsid n_qc close_rc _car_report_failed;
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
