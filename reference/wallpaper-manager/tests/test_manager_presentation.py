"""Render and interact with the actual Manager presentation in a disposable Qt host."""
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

@unittest.skipUnless(QT_RUNNER, "Qt Quick Test is required for presentation checks")
class ManagerPresentationTests(unittest.TestCase):
    def test_selection_actions_layout_and_motion(self):
        with tempfile.TemporaryDirectory(prefix="wallpaper-presentation-check-") as temp:
            base = Path(temp)
            (base / "components").symlink_to(ROOT / "integration/wallpaper-manager", target_is_directory=True)
            commons = base / "qs/Commons"; commons.mkdir(parents=True)
            (commons / "qmldir").write_text("module qs.Commons\nsingleton Color 1.0 Color.qml\nsingleton Motion 1.0 Motion.qml\n")
            (commons / "Color.qml").write_text('pragma Singleton\nimport QtQuick\nQtObject { property color background: "#101216"; property color foreground:"#e7e8eb";property color accent:"#b7bdca" }')
            (commons / "Motion.qml").write_text('pragma Singleton\nimport QtQuick\nQtObject {property bool reducedMotion:false;property int micro:80;property int standard:180;property int easeMicro:Easing.OutQuad}')
            shutil.copyfile(ROOT / "tests/qml/tst_PremiumManager.qml", base / "tst_PremiumManager.qml")
            env=dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software")
            run=subprocess.run([QT_RUNNER,"-input",str(base),"-import",str(base)],env=env,capture_output=True,text=True,timeout=30)
            self.assertEqual(run.returncode,0,run.stdout+run.stderr)
            self.assertIn("0 failed",run.stdout)
