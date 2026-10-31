"""Exercise the installed Quickshell Process implementation with large stdin."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which('quickshell'), 'Quickshell is required for live transport checks')
class QuickshellTransportTests(unittest.TestCase):
    def run_bridge(self, mode):
        with tempfile.TemporaryDirectory(prefix='wallpaper-request-check-') as temp:
            base = Path(temp)
            (base / 'components').symlink_to(ROOT / 'integration/wallpaper-manager', target_is_directory=True)
            helper = base / 'helper.py'
            helper.write_text('''import json,sys
if sys.argv[1] != '--request' or sys.argv[2] != '-': raise SystemExit(8)
request = json.loads(sys.stdin.readline())
if request.get('action') == 'no-result': raise SystemExit(7)
print(json.dumps({'event':'result','ok':True,'request':request}),flush=True)
''')
            result_file = base / 'result.json'
            qml = '''import QtQuick
import Quickshell
import Quickshell.Io
import "components" as Manager
ShellRoot {
    id: scene
    property int stage: 0
    property var first: ({})
    property var response: ({})
    property var receivedFirst: ({})
    property string mode: MODE
    function finish(ok, reason) {
        receipt.setText(JSON.stringify({ok:ok,reason:reason,expected:scene.first,received:scene.receivedFirst}))
        Qt.callLater(Qt.quit)
    }
    FileView { id: receipt; path: OUTPUT; printErrors: false }
    Manager.BackendRequest {
        id: bridge
        backend: HELPER
        interpreter: scene.mode === "failed-start" ? "/missing-wallpaper-helper" : "/usr/bin/python3"
        startTimeout: 250
        onEventReceived: event => scene.response = event
        onFinished: {
            if (busy) { scene.finish(false,"Busy stayed set after completion"); return }
            if (scene.mode !== "large") {
                scene.finish(scene.response.ok === false && scene.response.message.indexOf("queued batches are kept") >= 0, scene.response.message)
                return
            }
            if (scene.stage === 0) {
                if (!scene.response.ok) { scene.finish(false,"Large request did not return a result"); return }
                scene.receivedFirst = scene.response.request
                scene.stage = 1
                Qt.callLater(function() { bridge.send({action:"second-request",title:"Next request — café"}) })
            } else {
                scene.finish(scene.response.ok && scene.response.request.action === "second-request" && scene.response.request.title === "Next request — café", "Large and repeated requests arrived intact")
            }
        }
    }
    Component.onCompleted: {
        var items = []
        for (var i=0; i<694; ++i) items.push({source:"/wallpapers/" + "very-long-folder-name/".repeat(16) + i + ".png", title:"Café — wallpaper " + i, group:"Chosen group"})
        first = mode === "large" ? {action:"queue-import",confirmed:true,batches:[{group:"Chosen group",target:"both",items:items}]} : {action:"no-result"}
        if (mode === "large" && JSON.stringify(first).length <= 131072) { finish(false,"Fixture was too small"); return }
        bridge.send(first)
        if (!bridge.busy || bridge.send({action:"unexpected"})) finish(false,"Concurrent request was not blocked")
    }
    Timer { interval: 7000; running: true; onTriggered: scene.finish(false,"Request timed out") }
}
'''
            qml = qml.replace('MODE', json.dumps(mode)).replace('OUTPUT', json.dumps(str(result_file))).replace('HELPER', json.dumps(str(helper)))
            (base / 'shell.qml').write_text(qml)
            env = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software', QT_FORCE_STDERR_LOGGING='1')
            run = subprocess.run(['quickshell', '-p', str(base), '--no-color'], env=env,
                                 capture_output=True, text=True, timeout=12)
            self.assertEqual(run.returncode, 0, run.stderr + run.stdout)
            self.assertTrue(result_file.exists(), run.stderr + run.stdout)
            result = json.loads(result_file.read_text())
            if mode == 'large':
                # Qt can expose returned objects as QVariantMaps (sorted
                # keys). Compare all decoded values, not JSON key order.
                self.assertEqual(result.pop('received'), result.pop('expected'))
            self.assertTrue(result['ok'], str(result) + run.stderr + run.stdout)

    def test_large_and_repeated_requests(self):
        self.run_bridge('large')

    def test_failed_launch_releases_busy_and_reports_error(self):
        self.run_bridge('failed-start')

    def test_exit_without_result_reports_error(self):
        self.run_bridge('no-result')
