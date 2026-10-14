/*==========================================================================
 Export the available Program 02 validation and Program 03 result tables.
 Submit this file in the SAME SAS session that created the WORK tables.
 Files are written on the SAS server, not the local VS Code machine.
==========================================================================*/

/* EDIT HERE: existing directory on the SAS server where CSVs should go. */
%let export_dir=/export/viya/homes/jz472@duke.edu;

%macro _car_export_one(table,filename);
    %if %sysfunc(exist(work.&table)) %then %do;
        proc export data=work.&table
            outfile="&export_dir./&filename..csv"
            dbms=csv replace;
        run;
        %if &syserr>4 %then %do;
            %put ERROR: Failed to export WORK.&table.. Check the SAS log and directory permissions.;
            %abort cancel;
        %end;
        %let car_export_count=%eval(&car_export_count+1);
        %put NOTE: Exported WORK.&table to &export_dir./&filename..csv.;
    %end;
    %else %put NOTE: Skipped WORK.&table because it does not exist in this SAS session.;
%mend;

%macro car_export_results;
    %global car_export_count;
    %local dirid close_rc;
    %let car_export_count=0;
    filename _carexpt "&export_dir";
    %let dirid=%sysfunc(dopen(_carexpt));
    %if &dirid=0 %then %do;
        %put ERROR: EXPORT_DIR does not exist or is not accessible: &export_dir..;
        filename _carexpt clear;
        %abort cancel;
    %end;
    %let close_rc=%sysfunc(dclose(&dirid));
    filename _carexpt clear;

    /* Program 02: SAS versus R validation. */
    %_car_export_one(p02_r_summary,p02_r_summary);
    %_car_export_one(p02_r_diagnostics_compare,p02_r_diagnostics_compare);
    %_car_export_one(p02_r_fitted_compare,p02_r_fitted_compare);

    /* Program 03: AIPW point estimates and optional SAS/R comparison. */
    %_car_export_one(aipw_means,sas_aipw_means);
    %_car_export_one(aipw_predictions,sas_aipw_predictions);
    %_car_export_one(p03_r_mean_compare,p03_r_mean_compare);

    %if &car_export_count=0 %then %do;
        %put WARNING: No result tables were available to export. Run the analysis and validation in this SAS session first.;
    %end;
    %else %put NOTE: Exported &car_export_count result tables to &export_dir..;
%mend;

%car_export_results;
