# Generate original/calibrated inference reference CSVs. Requires RobinCar 1.2.0.
# Usage: Rscript validation/reference_inference.R input.csv output_dir
#        [ANOVA|ANCOVA|ANHECOVA] [simple|permuted-block] [0,1] [alpha]
# Design is an explicit algorithm setting; do not infer it from these data.

# ---- Configuration -----------------------------------------------------------

script_argument <- grep("^--file=", commandArgs(), value = TRUE)
script_directory <- dirname(normalizePath(sub("^--file=", "", script_argument[[1L]])))
source(file.path(script_directory, "..", "utilities", "reference_helpers.R"))

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2L) stop("Supply input CSV and output directory")
if (!requireNamespace("RobinCar", quietly = TRUE)) stop("Install RobinCar 1.2.0 first")
if (as.character(utils::packageVersion("RobinCar")) != "1.2.0") {
  stop("This reference script requires RobinCar 1.2.0; review before changing the pin")
}

alpha <- reference_alpha(if (length(args) >= 6L) args[[6L]] else "0.05")

model <- if (length(args) >= 3L) args[[3L]] else "ANOVA"
scheme <- if (length(args) >= 4L) args[[4L]] else "simple"
arms <- strsplit(
  if (length(args) >= 5L) args[[5L]] else "0,1",
  ",",
  fixed = TRUE
)[[1L]]

stopifnot(
  model %in% c("ANOVA", "ANCOVA", "ANHECOVA"),
  scheme %in% c("simple", "permuted-block"),
  length(arms) >= 2L,
  !anyDuplicated(arms)
)

# ---- Analysis data -----------------------------------------------------------

d <- utils::read.csv(args[[1L]], stringsAsFactors = FALSE)
needed <- c("A", "y", "strata_cross", "x1", "x3", "z1", "z2")
if (!all(needed %in% names(d))) stop("Required input columns are absent")

for (name in c("A", "y", "x1", "x3", "z1", "z2")) {
  assert_finite(d[[name]], paste0("Input ", name))
}
if (anyNA(d$strata_cross) || any(!nzchar(trimws(d$strata_cross)))) {
  stop("Missing randomization strata")
}
if (!identical(as.character(d$strata_cross), paste(d$z1, d$z2, sep = "-"))) {
  stop("strata_cross disagrees with z1/z2")
}
if (any(!arms %in% as.character(d$A))) stop("Requested arm is absent")

d$usubjid <- sprintf("SRC%08d", seq_len(nrow(d))) # before arm selection
d <- d[as.character(d$A) %in% arms, , drop = FALSE]
d$trt <- factor(as.character(d$A), levels = arms)
d$aval <- d$y
d$strata <- factor(d$strata_cross)
d$x1_analysis <- d$x1
d$x3_analysis <- d$x3

if (nrow(d) == 0L || anyNA(d[c(needed, "trt")])) stop("Empty or incomplete analysis")
if (any(table(d$trt) < 2L)) stop("At least two observations per arm required")
if (scheme == "permuted-block" && any(table(d$trt, d$strata) == 0L)) {
  stop("PB reference requires complete arm-by-stratum support")
}

# ---- Working model and joint calibration -------------------------------------

formula <- switch(model,
  ANOVA = aval ~ trt,
  ANCOVA = aval ~ trt + x1_analysis + x3_analysis,
  ANHECOVA = aval ~ trt * (x1_analysis + x3_analysis)
)

fit <- RobinCar::robincar_glm(
  d,
  treat_col = "trt",
  response_col = "aval",
  formula = formula,
  car_strata_cols = "strata",
  car_scheme = scheme,
  g_family = stats::gaussian(),
  variance_type = 1
)

cal <- RobinCar::robincar_calibrate(fit, joint = TRUE)

# ---- Export helpers ----------------------------------------------------------

dir.create(args[[2L]], recursive = TRUE, showWarnings = FALSE)
outdir <- args[[2L]]

# Collect and validate all tables before writing any new reference files.
tables <- list()
write <- function(x, name) {
  for (column in names(x)) {
    if (is.numeric(x[[column]])) assert_finite(x[[column]], paste(name, column))
    else if (anyNA(x[[column]])) stop("Missing reference field in ", name)
  }
  tables[[name]] <<- x
}

k <- length(arms)

long_predictions <- function(mu) {
  stopifnot(nrow(mu) == nrow(d), ncol(mu) == k)
  data.frame(
    usubjid = rep(d$usubjid, each = k),
    arm_index = rep(seq_len(k), nrow(d)),
    mu_tilde = as.vector(t(mu))
  )
}

long_vcov <- function(v) {
  data.frame(
    arm_i = rep(seq_len(nrow(v)), each = ncol(v)),
    arm_j = rep(seq_len(ncol(v)), nrow(v)),
    covariance = as.vector(t(v))
  )
}

export_result <- function(obj, prefix) {
  stopifnot(identical(as.character(obj$result$treat), arms))
  write(long_predictions(obj$mu_a), paste0(prefix, "_predictions"))
  write(
    data.frame(arm_index = seq_len(k), estimate = obj$result$estimate),
    paste0(prefix, "_estimates")
  )
  write(long_vcov(obj$varcov), paste0(prefix, "_vcov"))

  se <- sqrt(diag(obj$varcov))
  write(
    data.frame(
      arm_index = seq_len(k),
      estimate = obj$result$estimate,
      se = se,
      lcl = obj$result$estimate - qnorm(1 - alpha / 2) * se,
      ucl = obj$result$estimate + qnorm(1 - alpha / 2) * se
    ),
    paste0(prefix, "_inference")
  )

  contrast <- RobinCar::robincar_contrast(obj, contrast_h = "diff")
  write(
    data.frame(
      contrast_id = paste0("DIFF", seq_len(k - 1L)),
      estimate = contrast$result$estimate,
      se = contrast$result$se,
      lcl = contrast$result$estimate - qnorm(1 - alpha / 2) * contrast$result$se,
      ucl = contrast$result$estimate + qnorm(1 - alpha / 2) * contrast$result$se,
      p_value = 2 * pnorm(-abs(contrast$result$estimate / contrast$result$se))
    ),
    paste0(prefix, "_contrasts")
  )

  ids <- paste0("DIFF", seq_len(k - 1L))
  vc <- long_vcov(contrast$varcov)
  vc$contrast_i <- ids[vc$arm_i]
  vc$contrast_j <- ids[vc$arm_j]
  write(
    vc[c("contrast_i", "contrast_j", "covariance")],
    paste0(prefix, "_contrast_vcov")
  )
}

# ---- Original and calibrated results -----------------------------------------

export_result(fit, "original")
export_result(cal, "calibrated")

# ---- Raw predictions ---------------------------------------------------------

raw <- vapply(
  arms,
  function(a) {
    nd <- d
    nd$trt <- factor(rep(a, nrow(d)), levels = arms)
    nd$treat <- nd$trt # RobinCar internally standardizes the treatment name
    nd$response <- nd$aval

    as.numeric(stats::predict(fit$mod, newdata = nd, type = "response"))
  },
  numeric(nrow(d))
)

rawlong <- long_predictions(raw)
names(rawlong)[3L] <- "mu_raw"
write(rawlong, "original_raw_predictions")

cal_raw <- vapply(
  arms,
  function(a) {
    nd <- cal$original_df
    nd$trt <- factor(rep(a, nrow(d)), levels = arms)
    nd$treat <- nd$trt
    nd$response <- nd$aval
    as.numeric(stats::predict(cal$mod, newdata = nd, type = "response"))
  },
  numeric(nrow(d))
)
cal_raw_long <- long_predictions(cal_raw)
names(cal_raw_long)[3L] <- "mu_cal_raw"
write(cal_raw_long, "calibrated_raw_predictions")

write(
  data.frame(
    usubjid = d$usubjid,
    trt = as.numeric(as.character(d$trt)),
    aval = d$aval,
    strata = as.character(d$strata),
    x1_analysis = d$x1_analysis,
    x3_analysis = d$x3_analysis
  ),
  "analysis"
)

# ---- Arm mapping and reproducibility metadata --------------------------------

write(
  data.frame(
    arm_index = seq_len(k),
    trt = as.numeric(arms),
    n_arm = as.integer(table(d$trt)),
    pi_hat = as.numeric(table(d$trt)) / nrow(d)
  ),
  "arm_map"
)
write(
  data.frame(
    model = model,
    car_scheme = scheme,
    variance_type = 1L,
    joint = "YES",
    add_x = "",
    alpha = alpha,
    arms = paste(arms, collapse = ","),
    n = nrow(d),
    package_version = as.character(utils::packageVersion("RobinCar")),
    package_remote_sha = {
      desc <- utils::packageDescription("RobinCar")
      if (is.null(desc$RemoteSha)) "not-recorded" else desc$RemoteSha
    },
    input_md5 = unname(tools::md5sum(args[[1L]]))
  ),
  "settings"
)

for (name in names(tables)) {
  write_precise_reference(tables[[name]], file.path(outdir, paste0(name, ".csv")))
}

capture.output(
  utils::sessionInfo(),
  file = file.path(outdir, "sessionInfo.txt")
)

message("Reference files written to ", outdir)
