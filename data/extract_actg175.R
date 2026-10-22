#!/usr/bin/env Rscript

# Export the unmodified ACTG175 dataset distributed in the speff2trial source
# package. This reads the package's text data directly, so package compilation
# and the package's analysis dependencies are not needed.
# Usage from repository root: Rscript data/extract_actg175.R

package_version <- "1.0.5"
package_url <- paste0(
  "https://cran.r-project.org/src/contrib/speff2trial_",
  package_version, ".tar.gz"
)
# SHA-256 recorded for the pinned CRAN source archive.
package_sha256 <- "ecb3579670c360786da55346f783091f6b71bf6a49a920ab1224d254cd55e4a1"

script_arg <- grep("^--file=", commandArgs(), value = TRUE)
script_dir <- if (length(script_arg)) {
  dirname(normalizePath(sub("^--file=", "", script_arg[[1L]])))
} else {
  normalizePath("data")
}
repo_root <- normalizePath(file.path(script_dir, ".."))
output_file <- file.path(repo_root, "data", "ACTG175.csv")
provenance_file <- file.path(repo_root, "data", "ACTG175_provenance.txt")

work_dir <- tempfile("actg175-package-")
dir.create(work_dir)
archive_file <- file.path(work_dir, paste0("speff2trial_", package_version, ".tar.gz"))
utils::download.file(package_url, archive_file, mode = "wb", quiet = TRUE)

# Check the archive fingerprint using sha256sum (Linux/macOS) or certutil
# (Windows) before extracting the data file.
sha256_file <- function(path) {
  if (.Platform$OS.type == "windows") {
    output <- system2("certutil", c("-hashfile", shQuote(path), "SHA256"),
                      stdout = TRUE, stderr = TRUE)
    if (!length(output) || !is.null(attr(output, "status"))) {
      stop("Could not verify the archive; certutil SHA256 failed.")
    }
    hash <- tolower(gsub("[^[:xdigit:]]", "", output[grepl("^[[:xdigit:] ]+$", output)][1L]))
  } else {
    hash_tool <- Sys.which("sha256sum")
    hash_args <- shQuote(path)
    if (!nzchar(hash_tool)) {
      hash_tool <- Sys.which("shasum")
      hash_args <- c("-a", "256", shQuote(path))
    }
    if (!nzchar(hash_tool)) stop("Install sha256sum or shasum to verify the archive.")
    output <- system2(hash_tool, hash_args, stdout = TRUE, stderr = TRUE)
    if (!length(output) || !is.null(attr(output, "status"))) {
      stop("Could not verify the archive; sha256sum is required.")
    }
    hash <- strsplit(output[[1L]], "[[:space:]]+")[[1L]][1L]
  }
  tolower(hash)
}
archive_hash <- sha256_file(archive_file)
if (!identical(archive_hash, package_sha256)) {
  stop("The downloaded speff2trial archive checksum does not match the pinned source.")
}

extract_dir <- file.path(work_dir, "extract")
dir.create(extract_dir)
utils::untar(archive_file, files = "speff2trial/data/ACTG175.txt", exdir = extract_dir)
source_file <- file.path(extract_dir, "speff2trial", "data", "ACTG175.txt")
if (!file.exists(source_file)) stop("ACTG175.txt was not found in the source package.")
actg175 <- utils::read.table(source_file, header = TRUE, na.strings = "NA",
                             check.names = FALSE, stringsAsFactors = FALSE)

expected_columns <- c(
  "pidnum", "age", "wtkg", "hemo", "homo", "drugs", "karnof",
  "oprior", "z30", "zprior", "preanti", "race", "gender", "str2",
  "strat", "symptom", "treat", "offtrt", "cd40", "cd420", "cd496",
  "r", "cd80", "cd820", "cens", "days", "arms"
)
if (!identical(names(actg175), expected_columns)) {
  stop("ACTG175 schema differs from the pinned 27-column package definition.")
}
if (nrow(actg175) != 2139L || ncol(actg175) != 27L) {
  stop("Unexpected ACTG175 dimensions: ", nrow(actg175), " rows x ",
       ncol(actg175), " columns.")
}

# Preserve source row order, column order, values, and missing values.
utils::write.csv(actg175, output_file, row.names = FALSE, na = "")
csv_md5 <- unname(tools::md5sum(output_file))
writeLines(c(
  "Dataset: ACTG175",
  "Source package: speff2trial",
  paste("Source package version:", package_version),
  paste("Source archive URL:", package_url),
  paste("Source archive SHA-256:", archive_hash),
  "Source package file: speff2trial/data/ACTG175.txt",
  "Transformation: none; original row and column order retained",
  paste("Dimensions:", nrow(actg175), "rows x", ncol(actg175), "columns"),
  paste("CSV MD5:", csv_md5),
  R.version.string
), provenance_file)

message("Wrote ", normalizePath(output_file))
message("Rows: ", nrow(actg175), "; columns: ", ncol(actg175))
message("Source archive SHA-256: ", archive_hash)
message("CSV MD5: ", csv_md5)
unlink(work_dir, recursive = TRUE)
