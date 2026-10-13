/*
 * Shared input checks for programs 04-07. Load once before using their macros.
 * SAS/IML is required by 04-06. All arms are numeric, indexed 1,...,K.
 * Each call handles ONE analysis/model/estimator; filter stacked inputs first.
 * WORK._CAR_* are reserved scratch tables; macros are not re-entrant.
 * CAR_RC: 0 success, 1 failure, 2 reference unavailable (validation only).
 * After safe output-name checks, failures invalidate the specified outputs.
 */

/* Public return codes are published by completed entrypoints only. */
%global car_rc _car_error_rc;
%if %length(%superq(car_rc)) = 0 %then %let car_rc = 1;
%let _car_error_rc = 0;

%macro car_error(message);
    %global car_rc _car_error_rc;
    %let _car_error_rc = 1;
    %let car_rc = 1;
    %put ERROR: [CAR] &message;
%mend;

/* Normalize multiline name lists without changing punctuation within names. */
%macro car_words(text);
    %if %length(%superq(text)) = 0 %then %do;
    %end;
    %else %do;
        %qsysfunc(prxchange(%str(s/\s+/ /), -1, %superq(text)))
    %end;
%mend;

/* COUNTW() cannot be called with no argument after macro expansion. */
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

/* Capture the immediately preceding step's status; never reset a failure. */
%macro car_step(
    context =,
    sql     = NO
);
    %if &syserr > 4 %then
        %car_error(&context failed with SYSERR=&syserr.);
    %if &sql = YES %then %do;
        %if &sqlrc ne 0 %then
            %car_error(&context failed with SQLRC=&sqlrc.);
    %end;
%mend;

/* Parse literals before macro arithmetic. Blank, special missing, NaN and
   expressions are rejected, rather than passed to %SYSEVALF. */
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
        valid = not missing(number)
            and prxmatch('/^[+-]?(\d+(\.\d*)?|\.\d+)([eE][+-]?\d+)?$/', raw) > 0;
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
        %car_error(&name must be a finite numeric literal within its allowed range.);
%mend;

/* Guard the derived quantile probability against rounding to an endpoint. */
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
        %car_error(ALPHA cannot produce a finite normal quantile at machine precision.);
%mend;

/* V7 one/two-level DATA names only. Canonicalize one-level names to WORK.
   Validate the entire list before allowing any output removal. */
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
        %car_error(All output dataset names must be supplied.);
        %return;
    %end;
    %let output_list =;
    %do i = 1 %to %car_nwords(%superq(outputs));
        %let candidate = %scan(%superq(outputs), &i, %str( ));
        %let bad = 1;
        data _null_;
            length name $128;
            name = strip(symget('candidate'));
            valid = prxmatch('/^(?:[A-Za-z_][A-Za-z0-9_]{0,7}\.)?[A-Za-z_][A-Za-z0-9_]{0,31}$/', name) > 0;
            call symputx('bad', not valid, 'L');
        run;
        %car_step(context=Output name check);
        %if &bad %then %do;
            %car_error(Invalid output dataset name.);
            %return;
        %end;
        %let normalized = %upcase(&candidate);
        %if %index(&normalized, .) = 0 %then %do;
            %if "%qupcase(%superq(defaultlib))" ne "WORK" %then %do;
                %car_error(Use explicit two-level output names when USER is configured.);
                %return;
            %end;
            %let normalized = WORK.&normalized;
        %end;
        %if %sysfunc(libref(%scan(&normalized, 1, .))) ne 0 %then %do;
            %car_error(Output library is not assigned.);
            %return;
        %end;
        %if %sysfunc(exist(&normalized, VIEW)) %then %do;
            %car_error(Output name refers to a view rather than a DATA table.);
            %return;
        %end;
        %if %index(%scan(&normalized, 2, .), _CAR_) = 1 %then %do;
            %car_error(Output cannot use reserved _CAR_ names.);
            %return;
        %end;
        %if %length(%superq(output_list)) > 0 %then %do;
            %if %sysfunc(findw(&output_list, &normalized, %str( ))) > 0 %then %do;
                %car_error(Output dataset names must be distinct.);
                %return;
            %end;
            %do j = 1 %to %car_nwords(%superq(output_list));
                %let other = %scan(&output_list, &j, %str( ));
                %let output_path = %sysfunc(pathname(%scan(&normalized, 1, .)));
                %let input_path = %sysfunc(pathname(%scan(&other, 1, .)));
                %if "%superq(output_path)" = "%superq(input_path)"
                    and %scan(&normalized, 2, .) = %scan(&other, 2, .) %then %do;
                    %car_error(Output dataset names refer to the same physical table.);
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
                %car_error(Use plain V7 input dataset names without dataset options.);
                %return;
            %end;
            %if %index(&other, .) = 0 %then %do;
                %if "%qupcase(%superq(defaultlib))" ne "WORK" %then %do;
                    %car_error(Use explicit two-level input names when USER is configured.);
                    %return;
                %end;
                %let other = WORK.&other;
            %end;
            %if &normalized = &other %then %do;
                %car_error(Output cannot overwrite an input dataset.);
                %return;
            %end;
            /* Different librefs may point to the same physical directory. */
            %let inputlib = %scan(&other, 1, .);
            %if %sysfunc(libref(&inputlib)) = 0 %then %do;
                %let output_path = %sysfunc(pathname(%scan(&normalized, 1, .)));
                %let input_path = %sysfunc(pathname(&inputlib));
                %if "%superq(output_path)" = "%superq(input_path)"
                    and %scan(&normalized, 2, .) = %scan(&other, 2, .) %then %do;
                    %car_error(Output library aliases an input table.);
                    %return;
                %end;
            %end;
        %end;
        %let output_list = &output_list &normalized;
    %end;
    %if %length(%superq(output_list)) = 0 %then
        %car_error(Output dataset names are required.);
%mend;

/* Call ONLY after car_output_guard succeeded. Never clear input tables. */
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

/* Validate published numeric fields as well as procedure return codes.
   ZERO_SE deliberately leaves z/p_value missing; OK inference may not. */
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
    %if &bad > 0 %then %car_error(Published output contains missing numeric results.);
%mend;

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
        %car_error(A dataset name is required.);
        %return;
    %end;

    %if not %sysfunc(exist(&data)) %then %do;
        %car_error(Dataset &data does not exist.);
        %return;
    %end;

    %let dsid = %sysfunc(open(&data, i));
    %if &dsid = 0 %then %do;
        %car_error(Cannot open &data.);
        %return;
    %end;
    %do i = 1 %to %car_nwords(%superq(vars));
        %let name = %scan(&vars, &i);
        %if %sysfunc(varnum(&dsid, &name)) = 0 %then
            %car_error(Required variable &name is absent from &data.);
    %end;
    %do i = 1 %to %car_nwords(%superq(numeric));
        %let name = %scan(&numeric, &i);
        %let v = %sysfunc(varnum(&dsid, &name));
        %if &v > 0 %then %do;
            %if %sysfunc(vartype(&dsid, &v)) ne N %then
                %car_error(&data..&name must be numeric.);
        %end;
    %end;
    %do i = 1 %to %car_nwords(%superq(character));
        %let name = %scan(&character, &i);
        %let v = %sysfunc(varnum(&dsid, &name));
        %if &v > 0 %then %do;
            %if %sysfunc(vartype(&dsid, &v)) ne C %then
                %car_error(&data..&name must be character.);
        %end;
    %end;

    %let rc = %sysfunc(close(&dsid));
%mend;

/* Ensure one row per complete key. */

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
        %car_error(&data contains missing or duplicate keys: &keys.);
%mend;

/*
 * Sort and align subject, arm and prediction tables. Validate the complete
 * Cartesian product, not just a count of prediction rows.
 */

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
        %car_error(At least two arms and a nonempty analysis population are required.);
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
        %car_error(Analysis values or covariates are missing.);

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
        %car_error(Invalid arm map: use consecutive indices and at least two observations per arm.);

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
        %car_error(Observed treatment is absent from the arm map.);

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
        %car_error(Arm counts or empirical probabilities disagree with the analysis population.);

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
        %car_error(Predictions must contain exactly one finite value per subject and prediction arm.);
%mend;

/* Reject stale/incorrect point estimates before attaching inference. */

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
        %car_error(Point estimates do not match the supplied prediction matrix.);
%mend;
