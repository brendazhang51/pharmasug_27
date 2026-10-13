# Base-R helpers shared by the reference exporter and its local checks.
assert_finite <- function(x, name) {
  if (!is.numeric(x) || any(!is.finite(x))) {
    stop(name, " must contain only finite numeric values", call. = FALSE)
  }
  invisible(x)
}

reference_alpha <- function(value) {
  alpha <- suppressWarnings(as.numeric(value))
  if (length(alpha) != 1L || !is.finite(alpha) || alpha <= 0 || alpha >= 1) {
    stop("alpha must be a finite number strictly between zero and one", call. = FALSE)
  }
  probability <- 1 - alpha / 2
  if (probability <= 0 || probability >= 1) {
    stop("alpha cannot produce a finite normal quantile at machine precision", call. = FALSE)
  }
  alpha
}

write_precise_reference <- function(x, file) {
  if (!is.data.frame(x) || nrow(x) == 0L) {
    stop("Reference tables must be nonempty data frames", call. = FALSE)
  }
  for (name in names(x)) {
    if (is.numeric(x[[name]])) {
      assert_finite(x[[name]], name)
      x[[name]] <- sprintf("%.17g", x[[name]])
    } else if (anyNA(x[[name]])) {
      stop("Missing reference field: ", name, call. = FALSE)
    }
  }
  utils::write.table(
    x,
    file,
    sep = ",",
    row.names = FALSE,
    col.names = TRUE,
    quote = TRUE
  )
}
