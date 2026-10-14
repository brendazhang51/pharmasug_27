# Base R only. Run from repository root:
# Rscript validation/reference_outcome_models.R robincar_example_data.csv output_dir [0,1]
# Omit the third argument to retain all source arms. Never interpret y0/y1/y2.
script_argument <- grep("^--file=", commandArgs(), value = TRUE)
script_directory <- dirname(normalizePath(sub("^--file=", "", script_argument[[1L]])))
source(file.path(script_directory, "..", "utilities", "reference_helpers.R"))

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2L) stop("Supply input CSV and output directory; optional arms: 0,1")
df <- read.csv(args[[1L]], check.names = FALSE)
stopifnot(all(c("A", "y", "x1", "x3") %in% names(df)))
df$USUBJID <- sprintf("SRC%08d", seq_len(nrow(df)))
if (length(args) >= 3L) {
  arms <- as.numeric(strsplit(args[[3L]], ",", fixed = TRUE)[[1L]])
  stopifnot(length(arms) >= 2L, !anyNA(arms), all(arms %in% df$A))
  df <- df[df$A %in% arms, , drop = FALSE]
}
stopifnot(nrow(df) > 0L, all(is.finite(as.matrix(df[, c("A", "y", "x1", "x3")]))))
df$TRT <- factor(df$A, levels = sort(unique(df$A)))
stopifnot(nlevels(df$TRT) >= 2L, all(table(df$TRT) >= 2L))
formulas <- list(ANOVA = y ~ TRT, ANCOVA = y ~ TRT + x1 + x3,
                 ANHECOVA = y ~ TRT * (x1 + x3))
fitted_rows <- list()
diagnostic_rows <- list()
for (method in names(formulas)) {
  fit <- lm(formulas[[method]], data = df, na.action = na.fail)
  expected_rank <- switch(method, ANOVA = nlevels(df$TRT),
                          ANCOVA = nlevels(df$TRT) + 2L,
                          ANHECOVA = 3L * nlevels(df$TRT))
  stopifnot(fit$rank == expected_rank, df.residual(fit) > 0L)
  fitted_rows[[method]] <- data.frame(
    MODEL = method, USUBJID = df$USUBJID, TRT = df$A, AVAL = df$y,
    PREDICTED = unname(fitted(fit)), RESIDUAL = unname(residuals(fit)))
  sse <- sum(residuals(fit)^2)
  diagnostic_rows[[method]] <- data.frame(
    MODEL = method, N = nrow(df), EXPECTED_RANK = expected_rank,
    MODEL_RANK = fit$rank, ERROR_DF = df.residual(fit),
    SSE = sse, MSE = sse / df.residual(fit))
}
dir.create(args[[2L]], recursive = TRUE, showWarnings = FALSE)
write_precise_reference(
  do.call(rbind, fitted_rows),
  file.path(args[[2L]], "reference_fitted.csv")
)
write_precise_reference(
  do.call(rbind, diagnostic_rows),
  file.path(args[[2L]], "reference_diagnostics.csv")
)
writeLines(c(R.version.string, paste("Input MD5:", tools::md5sum(args[[1L]])),
             paste("Rows:", nrow(df)), paste("Arms:", paste(levels(df$TRT), collapse = ","))),
           file.path(args[[2L]], "reference_provenance.txt"))
