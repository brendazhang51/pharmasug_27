/* Define shared configuration only; generated run files call this macro.
   Personal settings live in utilities/config.local.json, not in source code. */
%macro car_config(
    csv_path=,
    arms=0 1 2,
    scheme=NOT_VERIFIED,
    alpha=0.05,
    outcome_reference_dir=,
    inference_reference_dir=
);
    %global input_csv analysis_arms analysis_scheme analysis_alpha reference_dir
        car_inference_reference_dir;
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
%mend;
