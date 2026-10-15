# Independent base-R reference for Program 03. Run from the repository root:
# Rscript validation/reference_aipw.R data/robincar_example_data.csv output_dir [0,1]
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
prediction_rows <- list()
mean_rows <- list()
for (method in names(formulas)) {
  fit <- lm(formulas[[method]], data = df, na.action = na.fail)
  expected_rank <- switch(method, ANOVA = nlevels(df$TRT),
                          ANCOVA = nlevels(df$TRT) + 2L,
                          ANHECOVA = 3L * nlevels(df$TRT))
  stopifnot(fit$rank == expected_rank, df.residual(fit) > 0L)
  for (arm in levels(df$TRT)) {
    target <- as.numeric(arm)
    newdata <- df
    newdata$TRT <- factor(arm, levels = levels(df$TRT))
    predicted <- unname(predict(fit, newdata = newdata))
    observed <- df$A == target
    observed_residual <- rep(NA_real_, nrow(df))
    observed_residual[observed] <- df$y[observed] - predicted[observed]
    prediction_rows[[length(prediction_rows) + 1L]] <- data.frame(
      MODEL = method, USUBJID = df$USUBJID, OBSERVED_TRT = df$A,
      TARGET_TRT = target, AVAL = df$y, PREDICTED = predicted,
      OBSERVED_RESIDUAL = observed_residual)
    mean_pred_all <- mean(predicted)
    mean_pred_arm <- mean(predicted[observed])
    observed_mean <- mean(df$y[observed])
    mean_residual_arm <- mean(observed_residual[observed])
    mean_rows[[length(mean_rows) + 1L]] <- data.frame(
      MODEL = method, TARGET_TRT = target, N_TOTAL = nrow(df),
      N_ARM = sum(observed), OBSERVED_MEAN = observed_mean,
      MEAN_PRED_ALL = mean_pred_all, MEAN_PRED_ARM = mean_pred_arm,
      MEAN_RESIDUAL_ARM = mean_residual_arm,
      AIPW_MEAN = mean_pred_all + mean_residual_arm)
  }
}
dir.create(args[[2L]], recursive = TRUE, showWarnings = FALSE)
write_precise <- function(x, file) {
  for (name in names(x)) {
    if (is.numeric(x[[name]])) {
      x[[name]] <- ifelse(is.na(x[[name]]), "", sprintf("%.17g", x[[name]]))
    }
  }
  write.table(x, file, sep = ",", row.names = FALSE, col.names = TRUE, quote = TRUE)
}
write_precise(do.call(rbind, prediction_rows),
              file.path(args[[2L]], "reference_aipw_predictions.csv"))
write_precise(do.call(rbind, mean_rows),
              file.path(args[[2L]], "reference_aipw_means.csv"))
writeLines(c(R.version.string, paste("Input MD5:", tools::md5sum(args[[1L]])),
             paste("Rows:", nrow(df)),
             paste("Arms:", paste(levels(df$TRT), collapse = ","))),
           file.path(args[[2L]], "reference_aipw_provenance.txt"))
