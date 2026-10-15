"""Check configuration and standalone submission assembly without SAS or network."""

from contextlib import redirect_stdout
import hashlib
import importlib.util
import io
import json
import re
from pathlib import Path
import shutil
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("car_project", ROOT / "run/project.py")
project = importlib.util.module_from_spec(spec)
spec.loader.exec_module(project)


def sas_arguments(text):
    """Split a SAS macro argument list at unquoted top-level commas."""
    parts = []
    start = depth = 0
    quote = None
    for i, char in enumerate(text):
        if quote:
            if char == quote:
                quote = None
        elif char in "\"'":
            quote = char
        elif char == "(":
            depth += 1
        elif char == ")":
            depth -= 1
        elif char == "," and depth == 0:
            parts.append(text[start:i])
            start = i + 1
    parts.append(text[start:])
    return [part.strip() for part in parts if part.strip()]


def sas_invocations(text, name):
    """Read balanced macro calls for static interface checks, without SAS."""
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    for match in re.finditer(r"%" + name + r"\s*\(", text, flags=re.I):
        start = match.end()
        depth = 1
        quote = None
        for i in range(start, len(text)):
            char = text[i]
            if quote:
                if char == quote:
                    quote = None
            elif char in "\"'":
                quote = char
            elif char == "(":
                depth += 1
            elif char == ")":
                depth -= 1
                if depth == 0:
                    yield text[start:i]
                    break
        else:
            raise AssertionError(f"Unclosed %{name} call")


class ProjectTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        sources = {name for recipe in project.RECIPES.values() for name in recipe}
        sources.update({"utilities/utilities.SAS", "utilities/config.example.json",
                        "data/robincar_example_data.csv"})
        for name in sources:
            destination = self.root / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / name, destination)
        self.cfg = json.loads((self.root / "utilities/config.example.json").read_text())
        self.cfg.update(
            server_input_csv="/server/data.csv",
            server_export_dir="/server/results",
            server_outcome_reference_dir="/server/model_reference",
            server_inference_reference_dir="/server/inference_reference",
        )
        self.path = self.root / "utilities/config.local.json"
        self.save()
        self.addCleanup(patch.stopall)
        patch.object(project, "ROOT", self.root).start()

    def save(self):
        self.path.write_text(json.dumps(self.cfg))

    def test_smoke_needs_no_personal_config_or_server_source_paths(self):
        self.path.unlink()
        with redirect_stdout(io.StringIO()):
            project.build("smoke", self.path)
        text = (self.root / "run/run.sas").read_text()
        self.assertNotIn("%include", text.lower())
        for definition in ("car_error", "car_calibrate", "car_variance", "car_contrast",
                           "car_validate", "car_test_inference"):
            self.assertLess(text.index("%macro " + definition), text.index("%car_smoke_require;"))
        self.assertIn("%put NOTE: CAR_TEST_FAILURES=", text)

    def test_inference_embeds_configuration_before_import_and_driver_after_definitions(self):
        with redirect_stdout(io.StringIO()):
            project.build("inference", self.path)
        path = self.root / "run/run.sas"
        text = path.read_text()
        self.assertLess(text.index("%car_config("), text.index("%require_config;"))
        self.assertLess(text.index("%macro car_test_inference"), text.index("%_car_pipeline_finish;"))
        self.assertLess(text.index("%macro car_inference"), text.index("%_car_pipeline_finish;"))
        self.assertEqual(text.count("%_car_pipeline_finish;"), 1)
        self.assertIn("csv_path=%nrstr(/server/data.csv)", text)
        self.assertIn("export_dir=%nrstr(/server/results)", text)
        self.assertNotIn("%include", text.lower())
        manifest = json.loads((self.root / "output/build/inference.json").read_text())
        self.assertIn("sas/inference_pipeline.sas", manifest["source_sha256"])
        self.assertFalse(any(name.startswith("examples/") for name in manifest["source_sha256"]))
        self.assertEqual(manifest["configuration"], self.cfg)
        self.assertEqual(manifest["bundle_sha256"], hashlib.sha256(path.read_bytes()).hexdigest())

    def test_import_failure_guards_precede_analysis_and_capture_import_status(self):
        source = (self.root / "sas/01_data_preparation.sas").read_text()
        self.assertLess(source.index("%_car_data_reset;"), source.index("%require_config;"))
        helper = source.split("%macro _car_import_source;", 1)[1].split("%mend;", 1)[0]
        self.assertLess(helper.index("delete robincar_raw"), helper.index("fileexist("))
        self.assertRegex(helper, r"run;\s*/\*[\s\S]*?\*/\s*%let import_rc=&syserr;")
        self.assertIn("&import_rc>4 or not %sysfunc(exist(work.robincar_raw))", helper)
        self.assertIn("%if &n_raw=0", helper)
        self.assertLess(source.index("%if &car_data_rc ne 0"), source.index("data work.standardized_all;"))
        abort = source.split("%macro _car_data_abort(", 1)[1].split("%mend;", 1)[0]
        self.assertLess(abort.index("outfile="), abort.index("%abort cancel;"))
        self.assertLess(abort.index("%car_report_finish;"), abort.index("%abort cancel;"))

    def test_full_report_wraps_all_analysis_and_final_validation(self):
        with redirect_stdout(io.StringIO()):
            project.build("inference", self.path)
        text = (self.root / "run/run.sas").read_text()
        self.assertLess(text.index("%car_report_start;"),
                        text.index("/* ===== Source: sas/01_data_preparation.sas ===== */"))
        calls = text.rsplit("%_car_pipeline_finish;", 1)[1]
        self.assertIn("%car_export_results;\n%car_report_finish;", calls)
        self.assertEqual(text.count("%car_export_results;"), 1)
        self.assertLess(text.index("%macro car_export_results;"), text.index("%_car_pipeline_finish;"))
        self.assertEqual(text.count("%car_report_start;"), 1)
        self.assertTrue(text.rstrip().endswith("%car_report_finish;"))
        self.assertIn('file="full_results.html"', text)

    def test_inference_uses_active_pipeline_without_archived_export_dependency(self):
        self.assertTrue(all("deprecated/" not in name for name in project.RECIPES["inference"]))
        self.assertNotIn("sas/export_results.sas", project.RECIPES["inference"])
        with redirect_stdout(io.StringIO()):
            project.build("inference", self.path)
        text = (self.root / "run/run.sas").read_text()
        self.assertEqual(text.count("%macro car_export_results;"), 1)
        self.assertEqual(text.count("%macro _car_export_one("), 1)

    def test_compact_export_contains_only_core_default_tables_and_conditional_evidence(self):
        source = (self.root / "sas/inference_pipeline.sas").read_text()
        tables = re.search(r"%let tables=(.*?);", source, re.S).group(1).split()
        self.assertEqual(set(tables), {
            "car_mean_inference", "car_contrast_results", "car_cal_inference",
            "car_cal_contrasts", "car_run_settings", "car_validation_suite",
            "allocation_summary", "baseline_summary",
        })
        self.assertIn("%if &car_suite_rc=1 %then %do;", source)
        self.assertIn("%if &n_qc>0 %then %do;", source)
        self.assertNotIn('file="inference_report.html"', source)
        self.assertIn("%_car_export_one(car_validation_details,car_validation_details)", source)
        self.assertEqual(len(list(sas_invocations(source, "_car_export_plot"))), 4)

    def test_inference_consumes_unchanged_program_03_without_an_adapter(self):
        with redirect_stdout(io.StringIO()):
            project.build("inference", self.path)
        text = (self.root / "run/run.sas").read_text()
        source = (self.root / "sas/03_aipw_estimation.sas").read_text()
        start = text.index("/* ===== Source: sas/03_aipw_estimation.sas ===== */")
        self.assertIn(source, text[start:])
        self.assertLess(text.index("%require_config;"), text.index("%_car_pipeline_prepare;"))
        self.assertLess(text.index("%macro car_fit("), text.index("%_car_pipeline_prepare;"))
        self.assertLess(text.index("%macro _car_pipeline_prepare;"),
                        text.index("%_car_pipeline_prepare;"))
        self.assertEqual(text.count("%_car_pipeline_prepare;"), 1)
        self.assertLess(text.index("%_car_pipeline_prepare;"), start)
        self.assertLess(text.index("%_car_aipw_driver;"), text.index("%_car_pipeline_finish;"))
        self.assertEqual(text.count("%_car_aipw_driver;"), 1)
        self.assertIn("%car_fit(data=work.analysis_data, method=ALL);", text)
        self.assertLess(text.index("%car_clear(outputs=&_car_pipeline_outputs)"),
                        text.index("%car_fit(data=work.analysis_data, method=ALL);"))
        self.assertIn("%let car_aipw_rc=1;", text)
        self.assertIn("%let car_suite_rc=1;", text)
        pipeline = (self.root / "sas/inference_pipeline.sas").read_text().lower()
        self.assertNotIn("proc glm", pipeline)
        self.assertNotIn("proc plm", pipeline)
        self.assertNotIn("car_adapt_aipw", text)
        self.assertNotIn("utilities/aipw_adapter.sas", text)
        self.assertIn("predictions    = work.aipw_predictions", text)
        self.assertIn("means          = work.aipw_means", text)
        self.assertIn("out_means       = work.car_cal_means", text)
        self.assertIn("p.predicted+m.mean_residual_arm as mu_tilde", text)

    def test_all_modes_share_one_submission_and_record_the_selected_mode(self):
        for mode in project.RECIPES:
            with redirect_stdout(io.StringIO()):
                project.build(mode, self.path)
            path = self.root / "run/run.sas"
            self.assertIn(f"GENERATED FILE: {mode}", path.read_text())
            self.assertEqual(list((self.root / "run").glob("run*.sas")), [path])
            manifest = json.loads((self.root / f"output/build/{mode}.json").read_text())
            self.assertEqual(manifest["mode"], mode)
            self.assertEqual(manifest["bundle_sha256"], hashlib.sha256(path.read_bytes()).hexdigest())

    def test_native_sas_call_sites_match_public_signatures(self):
        # Catches obsolete or duplicate keyword arguments after the API change.
        names = ("car_inputs", "car_calibrate", "car_variance", "car_contrast",
                 "car_test_inference")
        sources = {name for recipe in project.RECIPES.values() for name in recipe}
        texts = {name: (self.root / name).read_text() for name in sources}
        combined = "\n".join(texts.values())
        for name in names:
            definition = re.search(r"%macro\s+" + name + r"\s*\((.*?)\);",
                                   combined, flags=re.S | re.I)
            self.assertIsNotNone(definition, name)
            allowed = {part.split("=", 1)[0].strip().lower()
                       for part in sas_arguments(definition.group(1))}
            for source, text in texts.items():
                for arguments in sas_invocations(text, name):
                    supplied = [part.split("=", 1)[0].strip().lower()
                                for part in sas_arguments(arguments)]
                    with self.subTest(source=source, macro=name, arguments=arguments):
                        self.assertEqual(len(supplied), len(set(supplied)))
                        self.assertTrue(set(supplied) <= allowed, set(supplied) - allowed)

    def test_outcome_fixture_rejects_a_different_arm_population(self):
        self.cfg["analysis_arms"] = [0, 1]
        self.save()
        with self.assertRaisesRegex(ValueError, "original three arms"):
            project.build("outcome_models", self.path)
        self.assertFalse((self.root / "run/run.sas").exists())

    def test_rejects_invalid_numeric_settings_and_arm_mapping(self):
        for alpha in (True, "0.05", 0, 1, float("inf"), 1e-300):
            with self.subTest(alpha=alpha):
                self.cfg["alpha"] = alpha
                self.save()
                with self.assertRaisesRegex(ValueError, "alpha"):
                    project.load_config(self.path)
        self.cfg["alpha"] = .05
        for arms in ([0, 0], [True, 1], [2, 1, 0]):
            with self.subTest(arms=arms):
                self.cfg["analysis_arms"] = arms
                self.save()
                with self.assertRaises(ValueError):
                    project.load_config(self.path)

    def test_server_paths_cannot_inject_sas_statements(self):
        for path in ("/server/x; %put injected;", "/server/x\nrun;", "/server/(x)"):
            self.cfg["server_input_csv"] = path
            self.save()
            with self.assertRaisesRegex(ValueError, "unsupported"):
                project.load_config(self.path)

    def test_all_models_reach_sas_configuration_and_matching_reference(self):
        for model in ("ANOVA", "ANCOVA", "ANHECOVA"):
            with self.subTest(model=model):
                self.cfg["analysis_model"] = model
                self.save()
                with redirect_stdout(io.StringIO()):
                    project.build("inference", self.path)
                text = (self.root / "run/run.sas").read_text()
                self.assertIn(f"model=%nrstr({model})", text)
                with patch.object(project.shutil, "which", return_value="Rscript"), \
                        patch.object(project.subprocess, "run") as run, \
                        redirect_stdout(io.StringIO()):
                    project.reference("inference", self.path)
                self.assertEqual(run.call_args.args[0][-4:],
                                 [model, "simple", "0,1,2", "0.05"])
                manifest = json.loads((self.root / "output/build/inference.json").read_text())
                self.assertEqual(manifest["configuration"]["analysis_model"], model)

    def test_model_defaults_for_older_configs_and_rejects_invalid_values(self):
        del self.cfg["analysis_model"]
        self.save()
        self.assertEqual(project.load_config(self.path)["analysis_model"], "ANCOVA")
        for model in (None, [], True, "", "ALL", "LOGISTIC", "ANCOVA; %put injected;"):
            with self.subTest(model=model):
                self.cfg["analysis_model"] = model
                self.save()
                with self.assertRaisesRegex(ValueError, "analysis_model"):
                    project.load_config(self.path)

    def test_pipeline_passes_model_to_every_inference_stage(self):
        source = (self.root / "sas/inference_pipeline.sas").read_text()
        for name, count in (("car_variance", 2), ("car_contrast", 2), ("car_calibrate", 1)):
            calls = list(sas_invocations(source, name))
            self.assertEqual(len(calls), count)
            for call in calls:
                self.assertRegex(call, r"model\s*=\s*&model")
        self.assertIn('model = "&model";', source)
        self.assertIn("model      = &analysis_model", source)
        self.assertIn('&_car_export_model estimate and confidence interval', source)

    def test_export_path_is_validated_and_propagated_from_json(self):
        self.cfg["server_export_dir"] = "/server/results for review"
        self.save()
        with redirect_stdout(io.StringIO()):
            project.build("inference", self.path)
        text = (self.root / "run/run.sas").read_text()
        self.assertIn("export_dir=%nrstr(/server/results for review)", text)
        self.assertIn("%let car_export_dir=%superq(export_dir);", text)
        for value in ("relative/path", "", "/server/x; %put injected;", "/your/viya/home/results"):
            with self.subTest(value=value):
                self.cfg["server_export_dir"] = value
                self.save()
                with self.assertRaises(ValueError):
                    project.load_config(self.path)

    def test_reference_and_sas_use_the_same_analysis_settings(self):
        self.cfg.update(analysis_arms=[0, 1], car_scheme="permuted-block", alpha=.1)
        self.save()
        with patch.object(project.shutil, "which", return_value="Rscript"), \
                patch.object(project.subprocess, "run") as run, \
                redirect_stdout(io.StringIO()):
            project.reference("inference", self.path)
        args = run.call_args.args[0]
        self.assertEqual(args[-4:], ["ANCOVA", "permuted-block", "0,1", "0.1"])
        self.assertIn("scheme=%nrstr(permuted-block)", project.sas_config(self.cfg))
        self.assertIn("alpha=%nrstr(0.1)", project.sas_config(self.cfg))

    def test_init_never_overwrites_existing_personal_settings(self):
        original = self.path.read_bytes()
        with patch("sys.argv", ["project.py", "--config", str(self.path), "init"]), \
                redirect_stdout(io.StringIO()):
            project.main()
        self.assertEqual(self.path.read_bytes(), original)


if __name__ == "__main__":
    unittest.main()
