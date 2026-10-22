# Example Input

## ACTG175

`ACTG175.csv` is a byte-stable CSV export of `data(ACTG175)` from
`speff2trial` 1.0.5. It preserves all 2,139 rows and 27 columns in their
source order, including missing values. No filtering, recoding, or outcome
derivation is applied in this raw export. See `ACTG175_provenance.txt` for the
export fingerprint and run `Rscript data/extract_actg175.R` to reproduce it.

Install the pinned source package if needed:

```r
install.packages("speff2trial", repos = "https://cloud.r-project.org")
```

The package and dataset are distributed under the package's GPL-2 terms.
Retain the source attribution and package license when redistributing this
dataset. The analysis subset, derived outcome, and QC checks belong in a
separate reproducible preparation step; do not edit this raw export.

`robincar_example_data.csv` is the versioned example input. R reads this local
file. Upload the same bytes to the SAS server and configure `server_input_csv` separately.
Subject IDs are generated from CSV row order, so retain the original row order
when comparing SAS and R. `y` is the observed outcome; `y0/y1/y2` are retained
source fields, not documented arm-specific potential outcomes.
