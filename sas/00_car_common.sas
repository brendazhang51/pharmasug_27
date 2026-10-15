/*==========================================================================
 Program : 00_car_common.sas
 Project : Robust Covariate Adjustment under CAR (SAS / RobinCar)
 Purpose : Provide shared input checks, output guards and failure handling
           for 04-07.
 Status  : See doc/validation_status.md for verified configurations.

 INPUT  : Macro arguments, analysis/result datasets and preceding SAS step
          statuses.
 OUTPUT : Validated/ordered WORK._CAR_* tables and shared CAR_RC /
          _CAR_ERROR_RC.

 IMPORTANT:
 - Load this file before calling Programs 04-07.
 - Treatment labels are numeric; arm indices are consecutive integers 1...K.
 - Each call handles one population/model/estimator; filter stacked inputs.
 - WORK._CAR_* tables are reserved; macro calls are not re-entrant.
 - Validate all output names before clearing any public result tables.
 - CAR_RC: 0=success, 1=failure, 2=reference unavailable in Program 07.
==========================================================================*/

/* Public return codes are published by completed entrypoints only. */
%global car_rc _car_error_rc;
/* Open-code %IF requires a %DO/%END block on the target SAS server. */
%if %length(%superq(car_rc)) = 0 %then %do;
    %let car_rc = 1;
%end;
%let _car_error_rc = 0;

/*==========================================================================
 Macro   : car_error
 Purpose : Record and report a failure without cancelling the caller.

 INPUT  : MESSAGE: diagnostic text.
 OUTPUT : Sets CAR_RC=1 and _CAR_ERROR_RC=1; writes an ERROR log message.

 IMPORTANT:
 - Use keyword MESSAGE= so equals signs in messages are not parsed as
   arguments.
==========================================================================*/
%macro car_error(message=);
    %global car_rc _car_error_rc;
    %let _car_error_rc = 1;
    %let car_rc = 1;
    %put ERROR: [CAR] &message;
%mend;

/*==========================================================================
 Macro   : car_words
 Purpose : Normalize whitespace in a macro name list.

 INPUT  : TEXT: a possibly multiline, space-separated list.
 OUTPUT : Macro text with runs of whitespace replaced by a single blank.

 IMPORTANT:
 - Preserves punctuation within names; returns no text for an empty input.
==========================================================================*/
%macro car_words(text);
    %if %length(%superq(text)) = 0 %then %do;
    %end;
    %else %do;
        %qsysfunc(prxchange(%str(s/\s+/ /), -1, %superq(text)))
    %end;
%mend;

/*==========================================================================
 Macro   : car_nwords
 Purpose : Count entries in a normalized space-separated macro list.

 INPUT  : TEXT: a possibly empty name list.
 OUTPUT : Macro text containing the number of entries.

 IMPORTANT:
 - Returns zero for empty input without calling COUNTW with no argument.
==========================================================================*/
%macro car_nwords(text);
    %local words;
    %let words = %car_words(%superq(text));
    %if %length(%superq(words)) = 0 %then %do;
        0
    %end;
    %else %do;
        %sysfunc(countw(%superq(words), %str( )))
    %end;
%mend;

/*==========================================================================
 Macro   : car_step
 Purpose : Check the immediately preceding SAS step execution status.

 INPUT  : CONTEXT, SYSERR; SQL=YES also checks SQLRC.
 OUTPUT : Sets shared failure codes and logs a message when the step failed.

 IMPORTANT:
 - Never resets an earlier failure; call immediately after the relevant
   step.
==========================================================================*/
%macro car_step(
    context =,
    sql     = NO
);
    %if &syserr > 4 %then
        %car_error(message=&context failed with SYSERR=&syserr.);
    %if &sql = YES %then %do;
        %if &sqlrc ne 0 %then
            %car_error(message=&context failed with SQLRC=&sqlrc.);
    %end;
%mend;

/*==========================================================================
 Macro   : car_number
 Purpose : Validate a finite numeric literal before macro arithmetic.

 INPUT  : NAME, VALUE; optional LOWER/UPPER bounds and open/integer flags.
 OUTPUT : Sets shared failure codes for invalid syntax, missing values or
          range errors.

 IMPORTANT:
 - Rejects expressions, special missing values, NaN and nonnumeric strings.
==========================================================================*/
%macro car_number(
    name       =,
    value      =,
    lower      = .,
    upper      = .,
    lower_open = NO,
    upper_open = NO,
    integer    = NO
);
    %local valid;
    %let valid = 0;
    data _null_;
        length raw $32767;
        raw = strip(symget('value'));
        number = input(raw, ?? best32.);
        /* RAW is fixed-width; strip padding at the point of regex matching. */
        valid = not missing(number)
            and prxmatch('/^[+-]?(\d+(\.\d*)?|\.\d+)([eE][+-]?\d+)?$/', strip(raw)) > 0;
        if valid then do;
            lo = input(symget('lower'), ?? best32.);
            hi = input(symget('upper'), ?? best32.);
            if not missing(lo) then do;
                if number < lo then valid = 0;
                if symget('lower_open') = 'YES' and number = lo then valid = 0;
            end;
            if not missing(hi) then do;
                if number > hi then valid = 0;
                if symget('upper_open') = 'YES' and number = hi then valid = 0;
            end;
            if symget('integer') = 'YES' and number ne int(number) then valid = 0;
        end;
        call symputx('valid', valid, 'L');
    run;
    %car_step(context=Numeric parameter check);
    %if &valid ne 1 %then
        %car_error(message=&name must be a finite numeric literal within its allowed range.);
%mend;

/*==========================================================================
 Macro   : car_alpha
 Purpose : Validate alpha and the derived normal quantile probability.

 INPUT  : VALUE: the requested alpha.
 OUTPUT : Sets shared failure codes for invalid alpha or rounded endpoint
          probability.

 IMPORTANT:
 - Requires 0 < alpha < 1 and a representable 0 < 1-alpha/2 < 1.
==========================================================================*/
%macro car_alpha(value=);
    %local valid;
    %car_number(
        name       = ALPHA,
        value      = %superq(value),
        lower      = 0,
        upper      = 1,
        lower_open = YES,
        upper_open = YES
    );
    %if &_car_error_rc %then %return;
    %let valid=0;
    data _null_;
        alpha=input(symget('value'), ?? best32.);
        probability=1-alpha/2;
        call symputx('valid', probability>0 and probability<1, 'L');
    run;
    %car_step(context=Normal quantile parameter);
    %if &valid ne 1 %then
        %car_error(message=ALPHA cannot produce a finite normal quantile at machine precision.);
%mend;

/*==========================================================================
 Macro   : car_output_guard
 Purpose : Validate every output name before allowing output removal.

 INPUT  : INPUTS, OUTPUTS and EXPECTED output count.
 OUTPUT : Sets shared failure codes for unsafe, duplicate or overlapping
          names.

 IMPORTANT:
 - Accepts plain V7 names; checks library aliases and reserved scratch
   names.
 - Never deletes datasets; callers clear outputs only after this guard
   passes.
==========================================================================*/
%macro car_output_guard(
    inputs   =,
    outputs  =,
    expected =
);
    %local i j candidate normalized other bad output_list defaultlib inputlib
        output_path input_path;
    %let inputs = %car_words(%superq(inputs));
    %let outputs = %car_words(%superq(outputs));
    %let defaultlib = %sysfunc(getoption(user));
    %if %length(%superq(defaultlib)) = 0 %then %do;
        %if %sysfunc(libref(USER)) = 0 %then %let defaultlib = USER;
        %else %let defaultlib = WORK;
    %end;
    %if %car_nwords(%superq(outputs)) ne &expected %then %do;
        %car_error(message=All output dataset names must be supplied.);
        %return;
    %end;
    %let output_list =;
    %do i = 1 %to %car_nwords(%superq(outputs));
        %let candidate = %scan(%superq(outputs), &i, %str( ));
        %let bad = 1;
        data _null_;
            length name $128;
            name = strip(symget('candidate'));
            /* NAME is padded to $128; validate its trimmed value. */
            valid = prxmatch('/^(?:[A-Za-z_][A-Za-z0-9_]{0,7}\.)?[A-Za-z_][A-Za-z0-9_]{0,31}$/', strip(name)) > 0;
            call symputx('bad', not valid, 'L');
        run;
        %car_step(context=Output name check);
        %if &bad %then %do;
            %car_error(message=Invalid output dataset name: %superq(candidate).);
            %return;
        %end;
        %let normalized = %upcase(&candidate);
        %if %index(&normalized, .) = 0 %then %do;
            %if "%qupcase(%superq(defaultlib))" ne "WORK" %then %do;
                %car_error(message=Use explicit two-level output names when USER is configured.);
                %return;
            %end;
            %let normalized = WORK.&normalized;
        %end;
        %if %sysfunc(libref(%scan(&normalized, 1, .))) ne 0 %then %do;
            %car_error(message=Output library is not assigned.);
            %return;
        %end;
        %if %sysfunc(exist(&normalized, VIEW)) %then %do;
            %car_error(message=Output name refers to a view rather than a DATA table.);
            %return;
        %end;
        %if %index(%scan(&normalized, 2, .), _CAR_) = 1 %then %do;
            %car_error(message=Output cannot use reserved _CAR_ names.);
            %return;
        %end;
        %if %length(%superq(output_list)) > 0 %then %do;
            %do j = 1 %to %car_nwords(%superq(output_list));
                %let other = %scan(&output_list, &j, %str( ));
                /* Avoid FINDW with a blank argument in this SAS environment. */
                %if &normalized = &other %then %do;
                    %car_error(message=Output dataset names must be distinct.);
                    %return;
                %end;
                %let output_path = %sysfunc(pathname(%scan(&normalized, 1, .)));
                %let input_path = %sysfunc(pathname(%scan(&other, 1, .)));
                %if "%superq(output_path)" = "%superq(input_path)"
                    and %scan(&normalized, 2, .) = %scan(&other, 2, .) %then %do;
                    %car_error(message=Output dataset names refer to the same physical table.);
                    %return;
                %end;
            %end;
        %end;
        %do j = 1 %to %car_nwords(%superq(inputs));
            %let other = %upcase(%scan(%superq(inputs), &j, %str( )));
            data _null_;
                valid = prxmatch('/^(?:[A-Za-z_][A-Za-z0-9_]{0,7}\.)?[A-Za-z_][A-Za-z0-9_]{0,31}$/',
                    strip(symget('other'))) > 0;
                call symputx('bad', not valid, 'L');
            run;
            %car_step(context=Input name check);
            %if &bad %then %do;
                %car_error(message=Use plain V7 input dataset names without dataset options.);
                %return;
            %end;
            %if %index(&other, .) = 0 %then %do;
                %if "%qupcase(%superq(defaultlib))" ne "WORK" %then %do;
                    %car_error(message=Use explicit two-level input names when USER is configured.);
                    %return;
                %end;
                %let other = WORK.&other;
            %end;
            %if &normalized = &other %then %do;
                %car_error(message=Output cannot overwrite an input dataset.);
                %return;
            %end;
            /* Different librefs may point to the same physical directory. */
            %let inputlib = %scan(&other, 1, .);
            %if %sysfunc(libref(&inputlib)) = 0 %then %do;
                %let output_path = %sysfunc(pathname(%scan(&normalized, 1, .)));
                %let input_path = %sysfunc(pathname(&inputlib));
                %if "%superq(output_path)" = "%superq(input_path)"
                    and %scan(&normalized, 2, .) = %scan(&other, 2, .) %then %do;
                    %car_error(message=Output library aliases an input table.);
                    %return;
                %end;
            %end;
        %end;
        %let output_list = &output_list &normalized;
    %end;
    %if %length(%superq(output_list)) = 0 %then
        %car_error(message=Output dataset names are required.);
%mend;

/*==========================================================================
 Macro   : car_clear
 Purpose : Delete the validated public output tables once.

 INPUT  : OUTPUTS: dataset names already approved by CAR_OUTPUT_GUARD.
 OUTPUT : Removes existing DATA tables and records cleanup execution errors.

 IMPORTANT:
 - Call only after all output names pass the guard; never clear input
   tables.
==========================================================================*/
%macro car_clear(outputs=);
    %local i name lib member;
    %let outputs = %car_words(%superq(outputs));
    %do i = 1 %to %car_nwords(%superq(outputs));
        %let name = %scan(&outputs, &i, %str( ));
        %if %index(&name, .) = 0 %then %let name = WORK.&name;
        %let lib = %scan(&name, 1, .);
        %let member = %scan(&name, 2, .);
        %if %sysfunc(exist(&name)) %then %do;
            proc datasets library=&lib nolist nowarn;
                delete &member / memtype=data;
            quit;
            %car_step(context=Output invalidation);
        %end;
    %end;
%mend;

/*==========================================================================
 Macro   : car_result_values
 Purpose : Reject missing numeric results before publishing success.

 INPUT  : DATA, VALUES and INFERENCE flag.
 OUTPUT : WORK._CAR_BADNUMERIC; shared failure codes when numeric checks
          fail.

 IMPORTANT:
 - For INFERENCE=YES, OK rows require z/p-value; ZERO_SE rows may omit them.
==========================================================================*/
%macro car_result_values(
    data      =,
    values    =,
    inference = NO
);
    %local bad;
    data work._car_badnumeric;
        set &data;
        if nmiss(of &values) > 0
            %if &inference = YES %then %do;
                or (status = 'OK' and nmiss(z, p_value) > 0)
            %end;
            then output;
    run;
    %car_step(context=Published numeric checks);
    %if &_car_error_rc %then %return;
    proc sql noprint;
        select count(*) into :bad trimmed from work._car_badnumeric;
    quit;
    %car_step(
        context = Published numeric checks,
        sql     = YES
    );
    %if &bad > 0 %then %car_error(message=Published output contains missing numeric results.);
%mend;

/*==========================================================================
 Macro   : car_require
 Purpose : Check that a dataset and its required schema are available.

 INPUT  : DATA; VARS, NUMERIC and CHARACTER variable lists.
 OUTPUT : Sets shared failure codes for missing datasets, columns or wrong
          types.

 IMPORTANT:
 - This helper checks metadata; separate checks validate row values and
   keys.
==========================================================================*/
%macro car_require(
    data      =,
    vars      =,
    numeric   =,
    character =
);
    %local dsid i name v rc;
    %let vars = %car_words(%superq(vars));
    %let numeric = %car_words(%superq(numeric));
    %let character = %car_words(%superq(character));
    %if %length(%superq(data)) = 0 %then %do;
        %car_error(message=A dataset name is required.);
        %return;
    %end;

    %if not %sysfunc(exist(&data)) %then %do;
        %car_error(message=Dataset &data does not exist.);
        %return;
    %end;

    %let dsid = %sysfunc(open(&data, i));
    %if &dsid = 0 %then %do;
        %car_error(message=Cannot open &data.);
        %return;
    %end;
    %do i = 1 %to %car_nwords(%superq(vars));
        %let name = %scan(&vars, &i);
        %if %sysfunc(varnum(&dsid, &name)) = 0 %then
            %car_error(message=Required variable &name is absent from &data.);
    %end;
    %do i = 1 %to %car_nwords(%superq(numeric));
        %let name = %scan(&numeric, &i);
        %let v = %sysfunc(varnum(&dsid, &name));
        %if &v > 0 %then %do;
            %if %sysfunc(vartype(&dsid, &v)) ne N %then
                %car_error(message=&data..&name must be numeric.);
        %end;
    %end;
    %do i = 1 %to %car_nwords(%superq(character));
        %let name = %scan(&character, &i);
        %let v = %sysfunc(varnum(&dsid, &name));
        %if &v > 0 %then %do;
            %if %sysfunc(vartype(&dsid, &v)) ne C %then
                %car_error(message=&data..&name must be character.);
        %end;
    %end;

    %let rc = %sysfunc(close(&dsid));
%mend;

/*==========================================================================
 Macro   : car_unique
 Purpose : Check complete, unique dataset keys.

 INPUT  : DATA and KEYS.
 OUTPUT : WORK._CAR_BADKEYS, WORK._CAR_DUPLICATES; shared failure codes.

 IMPORTANT:
 - Rejects missing key values and duplicate key combinations.
==========================================================================*/
%macro car_unique(
    data =,
    keys =
);
    %local bad duplicates i sqlkeys;
    %let keys = %car_words(%superq(keys));
    %let sqlkeys =;
    %do i = 1 %to %car_nwords(%superq(keys));
        %if &i > 1 %then %let sqlkeys = &sqlkeys,;
        %let sqlkeys = &sqlkeys %scan(&keys, &i);
    %end;

    data work._car_badkeys;
        set &data;
        if cmiss(of &keys) > 0;
    run;
    %car_step(context=Input validation);
    %if &_car_error_rc %then %return;

    proc sql noprint;
        select count(*) into :bad trimmed
        from work._car_badkeys;
        create table work._car_duplicates as
        select &sqlkeys, count(*) as _car_count
        from &data
        group by &sqlkeys
        having calculated _car_count > 1;
        select count(*) into :duplicates trimmed
        from work._car_duplicates;
    quit;
    %car_step(
        context = Input validation,
        sql     = YES
    );
    %if &_car_error_rc %then %return;

    %if &bad > 0 or &duplicates > 0 %then
        %car_error(message=&data contains missing or duplicate keys: &keys.);
%mend;

/*==========================================================================
 Macro   : car_inputs
 Purpose : Validate and align analysis, treatment-arm and prediction data.

 INPUT  : DATA, PREDICTIONS, ARM_MAP; optional numeric ADD_X columns.
 OUTPUT : Ordered WORK._CAR_DATA, WORK._CAR_ARMS, WORK._CAR_GRID and
          diagnostics.

 IMPORTANT:
 - Requires the complete subject-by-arm prediction grid and empirical
   PI_HAT.
 - Rejects inconsistent counts, missing values and invalid treatment
   mappings.
==========================================================================*/
%macro car_inputs(
    data        =,
    predictions =,
    arm_map     =,
    add_x       =
);
    %local n k rows bad;
    %car_require(
        data      = &data,
        vars      = usubjid trt aval strata &add_x,
        numeric   = trt aval &add_x,
        character = usubjid strata
    );
    %car_require(
        data      = &predictions,
        vars      = usubjid arm_index mu_tilde,
        numeric   = arm_index mu_tilde,
        character = usubjid
    );
    %car_require(
        data    = &arm_map,
        vars    = arm_index trt n_arm pi_hat,
        numeric = arm_index trt n_arm pi_hat
    );
    %if &_car_error_rc %then
        %return;
    %car_unique(
        data = &data,
        keys = usubjid
    );
    %car_unique(
        data = &predictions,
        keys = usubjid arm_index
    );
    %car_unique(
        data = &arm_map,
        keys = arm_index
    );
    %car_unique(
        data = &arm_map,
        keys = trt
    );
    %if &_car_error_rc %then
        %return;

    proc sort data = &data out = work._car_data;
        by usubjid;
    run;
    %car_step(context=Input validation);
    %if &_car_error_rc %then %return;

    proc sort data = &arm_map out = work._car_arms;
        by arm_index;
    run;
    %car_step(context=Input validation);
    %if &_car_error_rc %then %return;

    proc sql noprint;
        select count(*) into :n trimmed
        from work._car_data;
        select count(*) into :k trimmed
        from work._car_arms;
        select count(*) into :rows trimmed
        from &predictions;
    quit;
    %car_step(
        context = Input validation,
        sql     = YES
    );
    %if &_car_error_rc %then %return;

    %if &n = 0 or &k < 2 %then %do;
        %car_error(message=At least two arms and a nonempty analysis population are required.);
        %return;
    %end;

    data work._car_bad;
        set work._car_data;
        if cmiss(of trt aval strata &add_x) > 0;
    run;
    %car_step(context=Input validation);
    %if &_car_error_rc %then %return;

    proc sql noprint;
        select count(*) into :bad trimmed
        from work._car_bad;
    quit;
    %car_step(
        context = Input validation,
        sql     = YES
    );
    %if &_car_error_rc %then %return;

    %if &bad > 0 %then
        %car_error(message=Analysis values or covariates are missing.);

    data work._car_bad;
        set work._car_arms;
        if cmiss(of arm_index trt n_arm pi_hat) > 0
            or arm_index ne _n_
            or n_arm < 2
            or n_arm ne int(n_arm)
            or pi_hat <= 0
            or pi_hat >= 1;
    run;
    %car_step(context=Input validation);
    %if &_car_error_rc %then %return;

    proc sql noprint;
        select count(*) into :bad trimmed
        from work._car_bad;
    quit;
    %car_step(
        context = Input validation,
        sql     = YES
    );
    %if &_car_error_rc %then %return;

    %if &bad > 0 %then
        %car_error(message=Invalid arm map: use consecutive indices and at least two observations per arm.);

    proc sql noprint;
        select count(*) into :bad trimmed
        from work._car_data d
        left join work._car_arms a
        on d.trt = a.trt
        where missing(a.arm_index);
    quit;
    %car_step(
        context = Input validation,
        sql     = YES
    );
    %if &_car_error_rc %then %return;

    %if &bad > 0 %then
        %car_error(message=Observed treatment is absent from the arm map.);

    proc sql;
        create table work._car_counts as
        select trt, count(*) as actual_n
        from work._car_data
        group by trt;
    quit;
    %car_step(
        context = Input validation,
        sql     = YES
    );
    %if &_car_error_rc %then %return;

    proc sql noprint;
        select count(*) into :bad trimmed
        from work._car_arms a
        left join work._car_counts c
        on a.trt = c.trt
        where missing(c.actual_n)
            or a.n_arm ne c.actual_n
            or abs(a.pi_hat - c.actual_n / &n) > 1e-10;
        create table work._car_grid as
        select d.usubjid, a.arm_index, p.mu_tilde
        from work._car_data d
        cross join work._car_arms a
        left join &predictions p
        on d.usubjid = p.usubjid and a.arm_index = p.arm_index
        order by d.usubjid, a.arm_index;
    quit;
    %car_step(
        context = Input validation,
        sql     = YES
    );
    %if &_car_error_rc %then %return;

    %if &bad > 0 %then
        %car_error(message=Arm counts or empirical probabilities disagree with the analysis population.);

    proc sql noprint;
        select count(*) into :bad trimmed
        from work._car_grid
        where missing(mu_tilde);
    quit;
    %car_step(
        context = Input validation,
        sql     = YES
    );
    %if &_car_error_rc %then %return;

    %if &bad > 0 or &rows ne %eval(&n * &k) %then
        %car_error(message=Predictions must contain exactly one finite value per subject and prediction arm.);
%mend;

/*==========================================================================
 Macro   : car_estimates
 Purpose : Check supplied means against the re-centered prediction grid.

 INPUT  : ESTIMATES and previously validated WORK._CAR_GRID.
 OUTPUT : WORK._CAR_EXPECTED, WORK._CAR_ESTCHECK; shared failure codes.

 IMPORTANT:
 - Requires one mean per arm and agreement within 1e-8 + 1e-6*abs(expected).
==========================================================================*/
%macro car_estimates(estimates =);
    %local bad;
    %car_require(
        data    = &estimates,
        vars    = arm_index estimate,
        numeric = arm_index estimate
    );
    %if &_car_error_rc %then
        %return;
    %car_unique(
        data = &estimates,
        keys = arm_index
    );
    %if &_car_error_rc %then
        %return;

    proc sql;
        create table work._car_expected as
        select arm_index, mean(mu_tilde) as expected
        from work._car_grid
        group by arm_index;
        create table work._car_estcheck as
        select
            a.arm_index as expected_arm,
            e.arm_index as supplied_arm,
            a.expected,
            e.estimate
        from work._car_expected a
        full join &estimates e
        on a.arm_index = e.arm_index;
    quit;
    %car_step(
        context = Input validation,
        sql     = YES
    );
    %if &_car_error_rc %then %return;

    proc sql noprint;
        select count(*) into :bad trimmed
        from work._car_estcheck
        where missing(expected_arm)
            or missing(supplied_arm)
            or missing(estimate)
            or abs(expected - estimate) > 1e-8 + 1e-6 * abs(expected);
    quit;
    %car_step(
        context = Input validation,
        sql     = YES
    );
    %if &_car_error_rc %then %return;

    %if &bad > 0 %then
        %car_error(message=Point estimates do not match the supplied prediction matrix.);
%mend;
