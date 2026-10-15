/* Standalone regression checks for import failure protection.
   First submit a generated inference run to load the Program 01 macros.
   Then submit this ENTIRE file in a test SAS session. It intentionally clears
   reserved analysis outputs and emits expected ERROR messages. Rerun the full
   inference workflow afterward; do not reuse the fixture data for analysis.
   Require CAR_DATA_TEST_FAILURES=0. No server-side source checkout is needed. */
%macro _car_data_assert(ok, message);
    %if not (&ok) %then %do;
        %let car_data_test_failures=%eval(&car_data_test_failures+1);
        %put ERROR: [DATA TEST] &message;
    %end;
%mend;

%macro car_test_data_preparation;
    %global car_data_test_failures;
    %local original_input fixture missing_path tables i table;
    %let car_data_test_failures=0;
    %if not %sysmacexist(_car_import_source) %then %do;
        %let car_data_test_failures=1;
        %put ERROR: Load Program 01 via the generated run before these checks.;
        %return;
    %end;
    %let original_input=%superq(input_csv);
    %let fixture=%sysfunc(pathname(work))/car_import_fixture.csv;
    %let missing_path=%sysfunc(pathname(work))/car_missing_fixture.csv;
    filename _cdtest "&fixture";
    data _null_;
        file _cdtest;
        put 'z1,z2,y0,y1,y2,A,y,strata_cross,x1,x3';
        put '0,1,1,2,3,0,1,0-1,0,0.1';
        put '1,2,1,2,3,1,2,1-2,1,0.2';
    run;
    %let input_csv=&fixture;
    %_car_import_source;
    %check_columns;
    %_car_data_assert(&car_data_rc=0, Valid CSV must import and pass schema checks.);

    /* Simulate a previous successful analysis before the next import fails. */
    data work.analysis_data work.aipw_means work.car_mean_inference
         work.car_validation_suite work.qc_issues;
        sentinel=1;
    run;
    %_car_data_reset;
    %let tables=robincar_raw standardized_all analysis_data aipw_means
        car_mean_inference car_validation_suite qc_issues;
    %do i=1 %to %sysfunc(countw(&tables));
        %let table=%scan(&tables,&i);
        %_car_data_assert(%sysfunc(exist(work.&table))=0, Stale WORK.&table must be removed.);
    %end;
    %_car_data_assert(&car_fit_rc=1 and &car_aipw_rc=1 and &car_suite_rc=1,
        Old success return codes must be invalidated.);
    %let input_csv=&missing_path;
    %_car_import_source;
    %_car_data_assert(&car_data_rc=1, Missing CSV must fail.);
    %_car_data_assert(%sysfunc(exist(work.robincar_raw))=0, Missing CSV must not reuse old raw data.);

    /* An existing directory passes FILEEXIST but is not a readable CSV file. */
    %let input_csv=%sysfunc(pathname(work));
    %_car_import_source;
    %_car_data_assert(&car_data_rc=1, PROC IMPORT failure must not report success.);
    %_car_data_assert(%sysfunc(exist(work.robincar_raw))=0, Failed import must remove partial raw data.);

    /* Missing columns, incorrect types and empty input are distinct failures. */
    data _null_;
        file _cdtest;
        put 'A,y'; put '0,1';
    run;
    %let input_csv=&fixture;
    %_car_import_source;
    %check_columns;
    %_car_data_assert(&car_data_rc=1, Incomplete schema must fail.);
    data work.robincar_raw;
        length z1 $3 strata_cross $3;
        z1='bad'; z2=1; y0=1; y1=2; y2=3; A=0; y=1;
        strata_cross='0-1'; x1=0; x3=0.1;
    run;
    %check_columns;
    %_car_data_assert(&car_data_rc=1, Nonnumeric numeric-required column must fail.);
    data _null_;
        file _cdtest;
        put 'z1,z2,y0,y1,y2,A,y,strata_cross,x1,x3';
    run;
    %_car_import_source;
    %_car_data_assert(&car_data_rc=1, Header-only CSV must fail.);

    %_car_data_reset;
    %let input_csv=%superq(original_input);
    data _null_; rc=fdelete('_cdtest'); run;
    filename _cdtest clear;
    %put NOTE: CAR_DATA_TEST_FAILURES=&car_data_test_failures;
    %put NOTE: Rerun the full inference workflow before using analysis results.;
%mend;
%car_test_data_preparation;
