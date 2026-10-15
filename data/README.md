# Example Input

`robincar_example_data.csv` is the versioned example input. R reads this local
file. Upload the same bytes to the SAS server and configure `server_input_csv` separately.
Subject IDs are generated from CSV row order, so retain the original row order
when comparing SAS and R. `y` is the observed outcome; `y0/y1/y2` are retained
source fields, not documented arm-specific potential outcomes.
