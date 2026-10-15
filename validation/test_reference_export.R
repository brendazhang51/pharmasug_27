# Run from any directory; default checks helpers and real RobinCar exports.
# Use --helpers-only for base-R checks without RobinCar installed.
script_argument <- grep("^--file=", commandArgs(), value = TRUE)
script_directory <- dirname(normalizePath(sub("^--file=", "", script_argument[[1L]])))
source(file.path(script_directory, "..", "utilities", "reference_helpers.R"))
args <- commandArgs(trailingOnly = TRUE)
if (length(args) > 1L || any(!args %in% "--helpers-only")) {
  stop("Usage: Rscript test_reference_export.R [--helpers-only]")
}

expect_error <- function(expr) {
  failed <- tryCatch(
    {
      force(expr); FALSE
    },
    error = function(e) TRUE
  )
  stopifnot(failed)
}

values <- c(1 / 7, pi, 1 + .Machine$double.eps, -1e-250, 1e250, 0)
path <- tempfile(fileext = ".csv")
write_precise_reference(data.frame(id = seq_along(values), value = values), path)
roundtrip <- utils::read.csv(path)
stopifnot(identical(roundtrip$value, values))
stopifnot(any(grepl(sprintf("%.17g", 1 / 7), readLines(path), fixed = TRUE)))

for (value in c("", ".", "NaN", "Inf", "0", "1", "-0.1", "1+2", "1e-300")) {
  expect_error(reference_alpha(value))
}
stopifnot(reference_alpha("0.05") == .05, reference_alpha("1e-2") == .01)
expect_error(assert_finite(c(1, NA_real_), "test"))
expect_error(assert_finite(c(1, Inf), "test"))
expect_error(write_precise_reference(data.frame(value = NaN), path))
expect_error(write_precise_reference(data.frame(value = numeric()), path))
expect_error(write_precise_reference(data.frame(id = NA_character_), path))
unlink(path)
message("Reference helpers: precision roundtrip and invalid-input checks passed")

if ("--helpers-only" %in% args) quit(status = 0L)

if (!requireNamespace("RobinCar", quietly = TRUE) ||
  as.character(utils::packageVersion("RobinCar")) != "1.2.0") {
  stop("Integration checks require RobinCar 1.2.0")
}

root <- normalizePath(file.path(script_directory, ".."))
script <- file.path(root, "validation", "reference_inference.R")
input <- file.path(root, "data", "robincar_example_data.csv")
rscript <- file.path(R.home("bin"), "Rscript")
source_data <- utils::read.csv(input)

# Independent Program 03 references are cached by population, not by design.
# Check downstream native-input centering against RobinCar without executing SAS.
aipw_cache <- new.env(parent = emptyenv())
base_aipw <- function(arms) {
  if (!exists(arms, envir = aipw_cache, inherits = FALSE)) {
    directory <- tempfile("base-aipw-")
    log <- tempfile("base-aipw-log-")
    result <- system2(
      rscript,
      vapply(c(file.path(root, "validation", "reference_aipw.R"),
               input, directory, arms), shQuote, ""),
      stdout = log,
      stderr = log
    )
    if (result != 0L) stop(paste(readLines(log), collapse = "\n"))
    assign(arms, list(
      predictions = utils::read.csv(file.path(directory, "reference_aipw_predictions.csv")),
      means = utils::read.csv(file.path(directory, "reference_aipw_means.csv"))
    ), envir = aipw_cache)
  }
  get(arms, envir = aipw_cache, inherits = FALSE)
}

compare_aipw_mapping <- function(reference, model, mapping, read, n) {
  p <- reference$predictions[reference$predictions$MODEL == model, ]
  m <- reference$means[reference$means$MODEL == model, ]
  arm <- match(as.character(p$TARGET_TRT), as.character(mapping$trt))
  delta <- m$MEAN_RESIDUAL_ARM[match(p$TARGET_TRT, m$TARGET_TRT)]
  mapped <- data.frame(
    usubjid = p$USUBJID, arm_index = mapping$arm_index[arm],
    mu_raw = p$PREDICTED, mu_tilde = p$PREDICTED + delta
  )
  check <- function(x, y, keys, value, expected_rows) {
    both <- merge(x, y, by = keys, all = TRUE, suffixes = c("_base", "_robin"))
    actual <- both[[paste0(value, "_base")]]
    expected <- both[[paste0(value, "_robin")]]
    stopifnot(
      nrow(both) == expected_rows, all(is.finite(actual)), all(is.finite(expected)),
      all(abs(actual - expected) <= 1e-8 + 1e-6 * abs(expected))
    )
  }
  check(mapped[c("usubjid", "arm_index", "mu_raw")], read("original_raw_predictions"),
        c("usubjid", "arm_index"), "mu_raw", n * nrow(mapping))
  check(mapped[c("usubjid", "arm_index", "mu_tilde")], read("original_predictions"),
        c("usubjid", "arm_index"), "mu_tilde", n * nrow(mapping))
  means <- data.frame(
    arm_index = mapping$arm_index[match(as.character(m$TARGET_TRT), as.character(mapping$trt))],
    estimate = m$AIPW_MEAN
  )
  check(means, read("original_estimates"), "arm_index", "estimate", nrow(mapping))
}

run_case <- function(model, scheme, arms, alpha = .05) {
  directory <- tempfile("car-reference-")
  log <- tempfile("car-reference-log-")
  result <- system2(
    rscript,
    vapply(c(script, input, directory, model, scheme, arms, as.character(alpha)), shQuote, ""),
    stdout = log,
    stderr = log
  )
  if (result != 0L) stop(paste(readLines(log), collapse = "\n"))
  read <- function(name) utils::read.csv(file.path(directory, paste0(name, ".csv")))
  selected <- strsplit(arms, ",", fixed = TRUE)[[1L]]
  n <- sum(as.character(source_data$A) %in% selected)
  k <- length(selected)
  settings <- read("settings")
  stopifnot(
    settings$alpha == alpha, settings$n == n, settings$arms == arms,
    settings$model == model, settings$car_scheme == scheme,
    settings$package_version == "1.2.0"
  )
  analysis <- read("analysis")
  stopifnot(nrow(analysis) == n, !anyDuplicated(analysis$usubjid))
  stopifnot(identical(as.character(read("arm_map")$trt), selected))
  compare_aipw_mapping(base_aipw(arms), model, read("arm_map"), read, n)
  for (stage in c("original", "calibrated")) {
    predictions <- read(paste0(stage, "_predictions"))
    means <- read(paste0(stage, "_estimates"))
    covariance <- read(paste0(stage, "_vcov"))
    contrasts <- read(paste0(stage, "_contrasts"))
    stopifnot(
      nrow(predictions) == n * k, nrow(means) == k,
      nrow(covariance) == k * k, nrow(contrasts) == k - 1L
    )
    stopifnot(!anyDuplicated(predictions[c("usubjid", "arm_index")]))
    expected_means <- aggregate(mu_tilde ~ arm_index, predictions, mean)
    stopifnot(max(abs(expected_means$mu_tilde - means$estimate)) < 1e-10)
    observed <- merge(predictions, analysis, by = "usubjid")
    mapping <- read("arm_map")
    observed <- merge(observed, mapping[c("arm_index", "trt")],
      by = "arm_index", suffixes = c("_observed", "_prediction")
    )
    observed <- observed[observed$trt_observed == observed$trt_prediction, ]
    centered_residuals <- aggregate(I(aval - mu_tilde) ~ arm_index, observed, mean)
    stopifnot(max(abs(centered_residuals[[2L]])) < 1e-8)
    for (table in list(predictions, means, covariance, contrasts)) {
      for (column in table) {
        if (is.numeric(column)) stopifnot(all(is.finite(column)))
      }
    }
  }
  message("PASS: ", model, " / ", scheme, " / ", arms, " / alpha=", alpha)
  read("calibrated_inference")
}

for (model in c("ANOVA", "ANCOVA", "ANHECOVA")) {
  for (scheme in c("simple", "permuted-block")) {
    for (arms in c("0,1", "0,1,2")) run_case(model, scheme, arms)
  }
}
invisible(run_case("ANCOVA", "simple", "2,1,0"))
wide <- run_case("ANCOVA", "simple", "0,1,2", .05)
narrow <- run_case("ANCOVA", "simple", "0,1,2", .10)
stopifnot(
  identical(wide$estimate, narrow$estimate), identical(wide$se, narrow$se),
  all(narrow$ucl - narrow$lcl < wide$ucl - wide$lcl)
)
message("Real RobinCar reference integration checks passed")
message("Independent base-R AIPW output mapping agrees with RobinCar in all scenarios")
