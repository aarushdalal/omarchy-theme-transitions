"""Real GUI request/response wiring with disposable source folders and home."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which('quickshell') and os.environ.get('WAYLAND_DISPLAY'), 'Quickshell and a Wayland session are required')
class FolderWorkspaceTests(unittest.TestCase):
    def test_scan_to_queue_keeps_folders_groups_and_rescans_independent(self):
        with tempfile.TemporaryDirectory(prefix='wallpaper-folder-ui-check-') as temp:
            base = Path(temp)
            home = base / 'home'; home.mkdir()
            project = home / 'Projects/wallpaper-importer'; project.mkdir(parents=True)
            folders = [base / 'drive one/Anime', base / 'drive #two/Anime']
            for index, folder in enumerate(folders):
                folder.mkdir(parents=True)
                Image.new('RGB', (24, 16)).save(folder / f'Wallpaper {index}.png')
            (project / 'wallpaper_manager.py').write_text(
                'import sys\nfrom pathlib import Path\n'
                f'sys.path.insert(0,{str(ROOT)!r})\n'
                'import wallpaper_add as core\nimport wallpaper_manager as manager\n'
                f'core.PROJECT=Path({str(project)!r})\nraise SystemExit(manager.main())\n')
            (base / 'components').symlink_to(ROOT / 'integration/wallpaper-manager', target_is_directory=True)
            (base / 'Commons').symlink_to(ROOT / 'tests/qml/Commons', target_is_directory=True)
            receipt = base / 'result.json'
            qml = '''import QtQuick
import Quickshell
import Quickshell.Io
import "components" as Manager
ShellRoot {
 id: scene
 property int stage: 0
 property var paths: PATHS
 FileView { id: receipt; path: OUTPUT; printErrors: false }
 Manager.Workspace { id: workspace }
 function finish(ok, message) { receipt.setText(JSON.stringify({ok:ok,message:message})); Qt.callLater(Qt.quit) }
 property bool started: false
 Timer {
  interval: 30; repeat: true; running: true
  onTriggered: {
   if (!scene.started) {
    if (!workspace.draftLoaded) return
    scene.started=true
    workspace.discoverFolders(scene.paths,{mode:"auto",allow_static_scenes:false,replace:false})
    return
   }
   if (workspace.busy || !workspace.lastResult.event) return
   if (!workspace.lastResult.ok) { scene.finish(false,workspace.lastResult.message); return }
   var batches=workspace.queuedBatches
   if (batches.length!==2 || workspace.queuedCount!==2 || batches[0].label!==scene.paths[0] || batches[1].label!==scene.paths[1]) { scene.finish(false,"Folder queue was mixed or incomplete"); return }
   if (scene.stage===0) {
    if (batches[0].group!=="" || batches[1].group!=="") { scene.finish(false,"Groups were assigned automatically"); return }
    workspace.setQueuedGroup(0,"Chosen new group")
    workspace.setQueuedGroup(1,"Other group")
    if (workspace.availableGroups.indexOf("Chosen new group")<0) { scene.finish(false,"New group cannot be reused"); return }
    scene.stage=1
    workspace.discoverFolders(scene.paths,{mode:"auto"})
   } else {
    scene.finish(batches[0].group==="Chosen new group" && batches[1].group==="Other group","Separate queue batches, explicit groups and repeat-scan deduplication verified")
   }
  }
 }
 Timer { interval: 7000; running: true; onTriggered: scene.finish(false,"Scan did not finish") }
}
'''
            qml = qml.replace('PATHS', json.dumps(list(map(str, folders)))).replace('OUTPUT', json.dumps(str(receipt)))
            (base / 'shell.qml').write_text(qml)
            env = dict(os.environ, HOME=str(home), XDG_CONFIG_HOME=str(home / '.config'),
                       XDG_DATA_HOME=str(home / '.local/share'), XDG_STATE_HOME=str(home / '.local/state'),
                       QT_QPA_PLATFORM='wayland', QT_QUICK_BACKEND='software', QT_FORCE_STDERR_LOGGING='1')
            run = subprocess.run(['quickshell', '-p', str(base), '--no-color'], env=env,
                                 text=True, capture_output=True, timeout=12)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            self.assertTrue(receipt.exists(), run.stdout + run.stderr)
            result = json.loads(receipt.read_text())
            self.assertTrue(result['ok'], str(result) + run.stdout + run.stderr)
            self.assertFalse((home / '.config/omarchy/themes').exists(), 'Scanning must not install wallpapers')
            self.assertFalse((project / 'data/jobs').exists(), 'Scanning must not start imports')
