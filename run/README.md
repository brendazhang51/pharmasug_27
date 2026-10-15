# Run Entry Point

`run/` contains one generator, `project.py`, and one generated SAS submission,
`run.sas`. The generator uses Python's standard library. Run from repository
root and choose the required mode:

```bash
python run/project.py init
python run/project.py build smoke
```

Submit the **entire contents** of `run/run.sas` to the SAS session.
Each build replaces this same file, so build and submit one mode at a time:

| Mode | Command | Purpose |
|---|---|---|
| `smoke` | `python run/project.py build smoke` | Synthetic tests, no uploads/config needed |
| `outcome_models` | `python run/project.py build outcome_models` | Program 02 tests and reference comparison |
| `inference` | `python run/project.py build inference` | Programs 01–07 and complete inference comparison |

The generated header identifies the mode. Dependencies and configured paths
are embedded; no server-side source checkout is needed. `run.sas` is ignored
by Git. Rebuild it after changing sources/configuration. Source and bundle
hashes are recorded under `output/build/<mode>.json`.

The inference orchestration lives together in
`sas/inference_pipeline.sas`: prepare/fitting, native 03 input consumption,
inference and reference comparison. The builder calls preparation before the
unchanged, automatically executing Program 03 and comparison after loading
all remaining definitions. Loading `inference_pipeline.sas` only defines macros; the builder inserts their
calls in the generated submission in this order:

1. Program 01 imports and prepares the analysis population.
2. Program 02 defines the model macros; `%_car_pipeline_prepare` clears previous
   pipeline results and fits ANOVA, ANCOVA and ANHECOVA.
3. Program 03 executes its unchanged automatic driver, producing predictions
   and AIPW means for all three models.
4. After the remaining definitions are loaded, `%_car_pipeline_finish` calls
   `%car_inference` for the selected model: Program 05/06 original inference, Program 04
   joint calibration, then Program 05/06 calibrated inference.
5. The finish macro invokes the Program 07/reference comparison suite.

The two orchestration stages preserve Program 03's automatic execution order.
The statistical implementations remain in `sas/`. Independent experimental
examples, including binomial/MI, remain in `examples/` and are not embedded.

```bash
python run/project.py reference outcome_models
python run/project.py reference inference
```

R reads the local CSV and writes to `output/`; upload those CSVs to the configured
server reference directories before submitting the corresponding data-based mode.
An alternate configuration can be supplied before the subcommand:

```bash
python run/project.py --config /path/to/config.json build inference
```

Inference selects `analysis_model` (default ANCOVA), type 1 and joint
calibration, with ascending numeric treatment order. Program 02's automated fixture requires the original three-arm data.
See [the quick start](../doc/quickstart.md) for prerequisites and expected codes.

For result export, set `server_export_dir` in the same JSON configuration.
The directory must already exist and be writable. Rebuild and submit
`run/run.sas`: it runs analysis, validation and compact export in one submission.
The builder embeds `sas/inference_pipeline.sas` and calls `%car_export_results`
after the suite and before closing the full report. No separate export
submission is required.

Default outputs are eight core CSVs, `full_results.html` and PNG plots.
Detailed comparison CSVs are added on validation failure; QC findings are
exported only when nonempty. No duplicate HTML report or intermediate data
CSVs are generated. Download the report and its PNGs together. See the
[save instructions](../doc/quickstart.md#save-result-tables-and-graphics).

## Select the inference model

Set `analysis_model` in `utilities/config.local.json` to `ANOVA`, `ANCOVA` or
`ANHECOVA`. Omission defaults to ANCOVA; invalid names and `ALL` are rejected.
Each submission performs inference for one selected model, while Programs 02/03
still fit and score all three working models.

After changing the model:

```bash
python run/project.py reference inference
python run/project.py build inference
```

Upload all newly generated reference CSVs to `server_inference_reference_dir`,
then submit the whole `run/run.sas`. The suite rejects references for a different
model. Use distinct existing `server_export_dir` and reference directories per
model when retaining comparisons: filenames remain unchanged and are overwritten
when reusing a directory. `MODEL` columns, run settings, the log and plot axes
identify the selected model. Changing only the export directory does not require
new references; changing the analysis model does.

The integrated ANCOVA path has supplied SAS execution evidence. Configurable ANOVA and
ANHECOVA inference require their own SAS runs; local checks do not execute SAS.
