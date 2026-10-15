"""Check configuration and standalone submission assembly without SAS or network."""

from contextlib import redirect_stdout
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import shutil
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("car_project", ROOT / "run/project.py")
project = importlib.util.module_from_spec(spec)
spec.loader.exec_module(project)


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
        text = (self.root / "run/run_smoke.sas").read_text()
        self.assertNotIn("%include", text.lower())
        for definition in ("car_error", "car_calibrate", "car_variance", "car_contrast",
                           "car_validate", "car_test_inference"):
            self.assertLess(text.index("%macro " + definition), text.index("%car_smoke_require;"))
        self.assertIn("%put NOTE: CAR_TEST_FAILURES=", text)

    def test_inference_embeds_configuration_before_import_and_driver_after_definitions(self):
        with redirect_stdout(io.StringIO()):
            project.build("inference", self.path)
        path = self.root / "run/run_inference.sas"
        text = path.read_text()
        self.assertLess(text.index("%car_config("), text.index("%require_config;"))
        self.assertLess(text.index("%macro car_test_inference"), text.index("%_car_run_inference;"))
        self.assertLess(text.index("%macro car_worked_example"), text.index("%_car_run_inference;"))
        self.assertEqual(text.count("%_car_run_inference;"), 1)
        self.assertIn("csv_path=%nrstr(/server/data.csv)", text)
        self.assertNotIn("%include", text.lower())
        manifest = json.loads((self.root / "output/build/inference.json").read_text())
        self.assertEqual(manifest["configuration"], self.cfg)
        self.assertEqual(manifest["bundle_sha256"], hashlib.sha256(path.read_bytes()).hexdigest())

    def test_outcome_fixture_rejects_a_different_arm_population(self):
        self.cfg["analysis_arms"] = [0, 1]
        self.save()
        with self.assertRaisesRegex(ValueError, "original three arms"):
            project.build("outcome_models", self.path)
        self.assertFalse((self.root / "run/run_outcome_models.sas").exists())

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
