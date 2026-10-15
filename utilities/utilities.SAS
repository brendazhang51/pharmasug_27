/* Define shared configuration only; generated run files call this macro.
   Personal settings live in utilities/config.local.json, not in source code. */
%macro car_config(
    csv_path=,
    arms=0 1 2,
    scheme=NOT_VERIFIED,
    alpha=0.05,
    outcome_reference_dir=,
    inference_reference_dir=,
    export_dir=,
    model=ANCOVA
);
    %global input_csv analysis_arms analysis_scheme analysis_alpha reference_dir
        car_inference_reference_dir car_export_dir analysis_model;
    %if "%qupcase(%superq(model))" ne "ANOVA" and
        "%qupcase(%superq(model))" ne "ANCOVA" and
        "%qupcase(%superq(model))" ne "ANHECOVA" %then %do;
        %put ERROR: MODEL must be ANOVA, ANCOVA, or ANHECOVA.;
        %abort cancel;
    %end;
    %let analysis_model=%qupcase(%superq(model));
    %let input_csv=;
    %if %length(%superq(csv_path))=0 %then %do;
        %put ERROR: Supply the SAS server CSV path in CAR_CONFIG.;
        %abort cancel;
    %end;
    %let input_csv=%superq(csv_path);
    %let analysis_arms=%superq(arms);
    %let analysis_scheme=%superq(scheme);
    %let analysis_alpha=%superq(alpha);
    %let reference_dir=%superq(outcome_reference_dir);
    %let car_inference_reference_dir=%superq(inference_reference_dir);
    %let car_export_dir=%superq(export_dir);
%mend;

/* Capture all displayed inference output, including GLM tables/plots and the
   final validation checks. Open before Program 01, close after the suite. */
%macro car_report_start;
    %global car_report_open;
    %let car_report_open=0;
    %local dirid close_rc;
    filename _carrpt "&car_export_dir";
    %let dirid=%sysfunc(dopen(_carrpt));
    %if &dirid=0 %then %do;
        filename _carrpt clear;
        %put ERROR: Create the configured SERVER_EXPORT_DIR before running inference: &car_export_dir..;
        %abort cancel;
    %end;
    %let close_rc=%sysfunc(dclose(&dirid));
    filename _carrpt clear;
    ods html(id=carfull) path="&car_export_dir" (url=none)
        gpath="&car_export_dir" (url=none)
        file="full_results.html" style=HTMLBlue image_dpi=300;
    ods graphics on / push outputfmt=png imagename="analysis_plot";
    %let car_report_open=1;
%mend;

%macro car_report_finish;
    %if not %symexist(car_report_open) %then %return;
    %if &car_report_open ne 1 %then %return;
    ods html(id=carfull) close;
    ods graphics / pop;
    %let car_report_open=0;
    %put NOTE: Full ODS output saved to &car_export_dir./full_results.html. Check CAR_SUITE_RC for validation status.;
%mend;
