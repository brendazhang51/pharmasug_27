/*==========================================================================
 Program : utilities.SAS
 Purpose : Configure server-specific paths for the RobinCar SAS programs.

 Run this file FIRST in the same SAS session as 01_data_preparation.sas.
 Each colleague changes only the CSV_PATH value in the call at the bottom.
 The CSV must already be uploaded to a directory accessible to their SAS
 Compute Server. The path refers to the server, not the local VS Code machine.
 Re-run this file after changing the path or starting a new SAS session.
==========================================================================*/

%macro car_config(csv_path=);
    %global input_csv;
    /* Clear any previous configuration before validating the new value. */
    %let input_csv=;
    %if %length(%superq(csv_path))=0 %then %do;
        %put ERROR: Supply the full server CSV path in %nrstr(%car_config).;
        %abort cancel;
    %end;
    %let input_csv=%superq(csv_path);
%mend car_config;

/* EDIT HERE: full CSV path on your own SAS server, without quotation marks.
   %nrstr protects special characters such as commas, percent signs, and &. */
%car_config(
    csv_path=%nrstr(/export/viya/homes/jz472@duke.edu/robincar_example_data.csv)
);
