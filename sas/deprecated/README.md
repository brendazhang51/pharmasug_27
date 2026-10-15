# Historical sources

`export_results.sas` is a historical copy. Its active macros now live in
[`../inference_pipeline.sas`](../inference_pipeline.sas), which the builder
embeds into `run/run.sas`. This directory is not a build dependency. Do not
submit the archived source after the pipeline; it could redefine active macros.
