# Shared Utilities and Configuration

`config.example.json` is the committed configuration template.
`config.local.json` contains personal server paths and analysis settings and is
ignored by Git. Create it with `python run/project.py init`; existing settings
are never overwritten by that command.

`utilities.SAS` defines `%car_config` without running it. The entry-point builder
embeds a call from the JSON configuration before importing data. Direct SAS
callers may still call `%car_config(csv_path=..., arms=0 1 2, scheme=simple,
alpha=0.05, outcome_reference_dir=..., inference_reference_dir=...)` themselves.
Do not put personal paths back into shared analysis sources.

`reference_helpers.R` provides finite-value checks, confidence-level validation
and CSV export with 17 significant digits. Both R exporters load it relative to
their script locations. Executable tests and exporters stay in `validation/`.

See [the quick start](../doc/quickstart.md) for local versus Viya paths and the
shared analysis settings.
