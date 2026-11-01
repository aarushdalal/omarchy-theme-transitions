"""Exercise themed select materials and Qt keyboard selection in an isolated window."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
QT_RUNNER = "/usr/lib/qt6/bin/qmltestrunner"
if not Path(QT_RUNNER).is_file():
    QT_RUNNER = shutil.which("qmltestrunner")


@unittest.skipUnless(QT_RUNNER, "Qt Quick Test runner is required for themed control checks")
class ThemedControlTests(unittest.TestCase):
    def test_materials_models_and_native_keyboard_selection(self):
        with tempfile.TemporaryDirectory(prefix="wallpaper-select-check-") as temp:
            base = Path(temp)
            (base / "components").symlink_to(ROOT / "integration/wallpaper-manager", target_is_directory=True)
            commons = base / "qs/Commons"
            commons.mkdir(parents=True)
            (commons / "qmldir").write_text("module qs.Commons\nsingleton Color 1.0 Color.qml\n")
            (commons / "Color.qml").write_text(
                'pragma Singleton\nimport QtQuick\nQtObject { property color foreground: "#dadde2"; '
                'property color background: "#101216"; property color accent: "#9dbaff" }\n')
            shutil.copyfile(ROOT / "tests/qml/tst_ThemedComboBox.qml", base / "tst_ThemedComboBox.qml")
            env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software")
            run = subprocess.run([QT_RUNNER, "-input", str(base), "-import", str(base)],
                                 env=env, capture_output=True, text=True, timeout=20)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            self.assertIn("0 failed", run.stdout)
