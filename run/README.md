# Run Entry Points

`project.py` uses Python's standard library to build complete SAS submissions
and to invoke the R reference generators with the same local configuration.
Run it from repository root; it also resolves its source files when called
by absolute path from another working directory.

```bash
python run/project.py init
python run/project.py build smoke
python run/project.py build outcome_models
python run/project.py build inference
```

The generated `run_*.sas` files contain dependencies in order and their final
calls. Open the required file and submit it **in full** through the VS Code
SAS extension. They require no server-side source checkout and are ignored by
Git because data-based submissions embed personal server paths. Rebuild them
after modifying sources or config. A fresh checkout must generate them first.

```bash
python run/project.py reference outcome_models
python run/project.py reference inference
```

R reads the local CSV and writes to `output/`; upload those CSVs to the configured
Viya reference directories before submitting the corresponding SAS file.
`inference_driver.sas` is source used by the builder, not a standalone entry point.

An alternate configuration can be supplied before the subcommand:

```bash
python run/project.py --config /path/to/config.json build inference
```

The current inference bridge is ANCOVA/type 1/joint calibration, with ascending
numeric treatment order. Program 02's automated fixture requires the original
three-arm data. See [the quick start](../doc/quickstart.md) for prerequisites,
expected return codes and verification records.
