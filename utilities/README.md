# Shared Utilities and Configuration

`config.example.json` is the committed configuration template.
`config.local.json` contains personal server paths and analysis settings and is
ignored by Git. Create it with `python run/project.py init`; existing settings
are never overwritten by that command.

`utilities.SAS` defines `%car_config` without running it. The entry-point builder
embeds a call from the JSON configuration before importing data. Direct SAS
callers may still call `%car_config(csv_path=..., arms=0 1 2, scheme=simple,
alpha=0.05, outcome_reference_dir=..., inference_reference_dir=..., export_dir=..., model=ANCOVA)` themselves.
Do not put personal paths back into shared analysis sources.

`reference_helpers.R` provides finite-value checks, confidence-level validation
and CSV export with 17 significant digits. Both R exporters load it relative to
their script locations. Executable tests and exporters stay in `validation/`.

See [the quick start](../doc/quickstart.md) for local versus server paths and the
shared analysis settings.

Set `server_export_dir` in `config.local.json` to an existing writable SAS
directory for CSV results, the HTML report and PNG plots. For example:

```json
"server_export_dir": "/server/home/results"
```

After changing JSON, rebuild and submit `run/run.sas` so the current SAS session
receives the new path. The inference run automatically invokes the compact
export macros defined in `sas/inference_pipeline.sas`; no separate submission
is needed.
The exporter reads `car_export_dir` set by `%car_config`; it does not read the
local JSON directly. It does not create directories. The other existing path
settings remain unchanged. Existing local configurations need the new
`server_export_dir` key; `init` preserves existing files.
