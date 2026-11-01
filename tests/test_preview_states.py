"""Exercise Theme Deck image states and isolated selection export with real Qt image I/O.

The exact release QML is compiled in a hidden owned Wayland process. Interaction
checks replace only the layer-shell window host for offscreen execution; no desktop
setting, theme, selection, audio or service is changed. Requires an Omarchy shell
Commons module and Quickshell. Missing runtime dependencies are explicit skips.
"""
import hashlib
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile
import unittest
import zlib

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "reference/ImagePicker.qml" if (ROOT / "reference/ImagePicker.qml").is_file()
          else ROOT / "plugins/community.image-picker/ImagePicker.qml")


def commons_path():
    candidates = [Path(os.environ.get("OMARCHY_PATH", str(Path.home()/".local/share/omarchy"))) / "shell/Commons",
                  Path("/usr/share/omarchy/shell/Commons")]
    return next((p for p in candidates if (p/"qmldir").is_file()), None)


def png(path, rgb):
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind+data)&0xffffffff)
    scan = b"".join(b"\x00" + bytes(rgb)*16 for _ in range(16))
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB",16,16,8,2,0,0,0))
                     + chunk(b"IDAT",zlib.compress(scan)) + chunk(b"IEND",b""))


@unittest.skipUnless(shutil.which("quickshell") and commons_path(), "Quickshell and Omarchy Commons required")
class PreviewStateTests(unittest.TestCase):
    def stage(self, folder):
        base=Path(folder)
        (base/"Commons").symlink_to(commons_path(),target_is_directory=True)
        shutil.copy2(SOURCE,base/"ImagePicker.qml")
        shutil.copy2(SOURCE.with_name("ImagePickerModel.js"),base/"ImagePickerModel.js")
        return base

    def run_qml(self, base, platform):
        env=dict(os.environ,QT_QPA_PLATFORM=platform,QT_FORCE_STDERR_LOGGING="1")
        if platform=="offscreen": env["QT_QUICK_BACKEND"]="software"
        result=subprocess.run(["quickshell","-p",str(base),"--no-color"],env=env,capture_output=True,text=True,timeout=15)
        log=result.stdout+result.stderr
        self.assertEqual(result.returncode,0,log)
        self.assertNotIn("Failed to load configuration",log)
        self.assertNotIn("ReferenceError",log)
        self.assertNotIn("TypeError",log)
        return log

    def save_evidence(self, name, data, log):
        data=dict(data,sourceSha256=hashlib.sha256(SOURCE.read_bytes()).hexdigest())
        target=os.environ.get("DAEMONOS_PREVIEW_TEST_EVIDENCE")
        if target:
            folder=Path(target);folder.mkdir(parents=True,exist_ok=True)
            (folder/(name+".json")).write_text(json.dumps(data,indent=2)+"\n")
            (folder/(name+".log")).write_text(log)

    @unittest.skipUnless(os.environ.get("WAYLAND_DISPLAY"),"Hidden native compile needs Wayland")
    def test_exact_release_qml_compiles_hidden(self):
        with tempfile.TemporaryDirectory(prefix="theme-preview-compile-") as folder:
            base=self.stage(folder)
            (base/"shell.qml").write_text('import QtQuick\nimport Quickshell\nShellRoot { ImagePicker { soundEnabled:false } Timer { interval:300; running:true; onTriggered:{ console.log("PREVIEW-COMPILE-PASS"); Qt.quit() } } }\n')
            log=self.run_qml(base,"wayland")
            self.assertIn("PREVIEW-COMPILE-PASS",log)
            self.save_evidence("native-compile",{"ok":True,"source":str(SOURCE),"visible":False},log)

    def test_preview_states_and_isolated_apply(self):
        with tempfile.TemporaryDirectory(prefix="theme-preview-state-") as folder:
            base=self.stage(folder);assets=base/"assets";assets.mkdir()
            for name,rgb in [("alpha.png",(29,48,74)),("beta.png",(74,36,29)),("alpha-thumb.png",(29,48,74)),("beta-thumb.png",(74,36,29)),("valid-master.png",(33,64,45))]: png(assets/name,rgb)
            (assets/"corrupt.png").write_text("not an image")
            # Platform adapter only; product bindings, images, navigation and exports stay exact.
            source=(base/"ImagePicker.qml").read_text()
            source=source.replace('  PanelWindow {\n','  FloatingWindow {\n',1)
            source=source.replace('    anchors { top: true; bottom: true; left: true; right: true }\n','    implicitWidth:1920\n    implicitHeight:1080\n',1)
            for line in ['    WlrLayershell.namespace: "omarchy-image-selector"\n','    WlrLayershell.layer: WlrLayer.Overlay\n','    WlrLayershell.keyboardFocus: root.opened && root.imagesLoaded ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None\n','    exclusionMode: ExclusionMode.Ignore\n']:
                self.assertIn(line,source);source=source.replace(line,'',1)
            (base/"ImagePicker.qml").write_text(source)
            config={"base":str(base),"alpha":str(assets/"alpha.png"),"beta":str(assets/"beta.png"),"alphaThumb":str(assets/"alpha-thumb.png"),"betaThumb":str(assets/"beta-thumb.png"),"corrupt":str(assets/"corrupt.png"),"missing":str(assets/"missing.png"),"valid":str(assets/"valid-master.png")}
            (base/"shell.qml").write_text(HARNESS.replace("CONFIG",json.dumps(config)))
            log=self.run_qml(base,"offscreen")
            self.assertTrue((base/"result.json").is_file(),log)
            receipt=json.loads((base/"result.json").read_text())
            self.save_evidence("preview-states",receipt,log)
            self.assertTrue(receipt["ok"],str(receipt)+log)
            self.assertEqual(len(receipt["checks"]),16)
            self.assertTrue(all(row["ok"] for row in receipt["checks"]))
            self.assertEqual((base/"selection-final").read_text().strip(),config["beta"])
            self.assertEqual((base/"selection-late").read_text().strip(),config["alpha"])
            self.assertEqual((base/"selection-new").read_text().strip(),config["beta"])
            self.assertTrue(all((base/("done-"+suffix)).exists() for suffix in ["initial","group","final","late","new"]))


HARNESS = r'''import QtQuick
import Quickshell
import Quickshell.Io
ShellRoot {
 id: scene
 property var config: CONFIG
 property int stage: 0
 property int ticks: 0
 property var checks: []
 property bool finished: false
 property string rows: config.alpha + "\t" + config.alphaThumb + "\n" + config.beta + "\t" + config.betaThumb + "\n" + config.corrupt + "\t" + config.corrupt + "\n" + config.missing + "\t" + config.missing + "\n" + config.corrupt + "-fallback\t" + config.alphaThumb + "\n" + config.valid + "\t" + config.missing
 function check(ok, reason) {
   checks.push({ok:!!ok,reason:reason,path:deck.currentPath(),label:deck.currentLabel(),state:deck.currentPreviewState(),stage:stage})
   if (!ok) finish(false, reason)
 }
 function finish(ok,reason) {
   if (finished) return
   finished = true
   receipt.setText(JSON.stringify({ok:ok,reason:reason,checks:checks,stage:stage},null,2))
   Qt.callLater(Qt.quit)
 }
 function open(rows,path,suffix) { deck.openSelector("",rows,path,config.base+"/selection-"+suffix,config.base+"/done-"+suffix,true,true) }
 FileView { id: receipt; path: scene.config.base+"/result.json"; printErrors:false }
 FileView { id: selection; path: scene.config.base+"/selection-final"; printErrors:false; watchChanges:true }
 FileView { id: lateSelection; path: scene.config.base+"/selection-late"; printErrors:false; watchChanges:true }
 FileView { id: finalSelection; path: scene.config.base+"/selection-new"; printErrors:false; watchChanges:true }
 ImagePicker { id: deck; soundEnabled:false }
 Component.onCompleted: { open(rows,config.alpha,"initial"); check(deck.currentPreviewState()==="empty" || deck.currentPreviewState()==="loading","cold request has a defined pending/empty state") }
 Timer {
  interval:40; running:true; repeat:true
  onTriggered: {
   if (scene.finished) return
   if (++scene.ticks > 200) { scene.finish(false,"Timed out at stage "+scene.stage); return }
   if (scene.stage === 0 && deck.currentPreviewState()==="ready") {
    scene.check(deck.currentPath()===scene.config.alpha,"cold decode retains Alpha identity")
    deck.select(1);deck.select(0);deck.select(1);deck.select(0);deck.select(1)
    scene.check(deck.currentPath()===scene.config.beta,"rapid reversing ends on Beta")
    scene.stage=1
   } else if (scene.stage===1 && deck.currentPreviewState()==="ready") {
    scene.check(deck.currentLabel()==="Beta","warm Beta preview and title agree")
    deck.togglePeek();deck.togglePeek();deck.togglePeek();deck.togglePeek()
    scene.check(deck.currentPath()===scene.config.beta && deck.currentPreviewState()==="ready","repeated peek preserves selected preview")
    deck.updateFilter("alpha")
    scene.check(deck.currentPath()===scene.config.alpha,"search selects matching Alpha")
    deck.updateFilter("no-matching-item")
    scene.check(deck.currentPath()==="" && deck.currentPreviewState()==="empty","empty search does not reuse stale artwork identity")
    deck.updateFilter("");deck.select(2);scene.stage=2
   } else if (scene.stage===2 && deck.currentPreviewState()==="error") {
    scene.check(deck.currentPath()===scene.config.corrupt,"corrupt item reports unavailable for its own path")
    deck.select(3);scene.stage=3
   } else if (scene.stage===3 && deck.currentPreviewState()==="error") {
    scene.check(deck.currentPath()===scene.config.missing,"missing item reports unavailable for its own path")
    deck.select(4);scene.stage=4
   } else if (scene.stage===4 && deck.currentPreviewState()==="ready") {
    scene.check(deck.currentPath()===scene.config.corrupt+"-fallback","valid same-item thumbnail survives unavailable master")
    deck.select(5);scene.stage=5
   } else if (scene.stage===5 && deck.currentPreviewState()==="ready") {
    scene.check(deck.currentPath()===scene.config.valid,"valid master recovers unavailable thumbnail")
    scene.open(scene.config.beta+"\t"+scene.config.betaThumb+"\n"+scene.config.alpha+"\t"+scene.config.alphaThumb,scene.config.alpha,"group")
    scene.stage=6
   } else if (scene.stage===6 && deck.currentPreviewState()==="ready") {
    scene.check(deck.currentPath()===scene.config.alpha && deck.selectedIndex===1,"group replacement restores selection by path rather than old index")
    deck.updateFilter("beta");deck.updateFilter("");deck.selectAdjacent(1);deck.select(0)
    scene.open(scene.rows,scene.config.beta,"final");scene.stage=7
   } else if (scene.stage===7 && deck.currentPreviewState()==="ready") {
    scene.check(deck.currentPath()===scene.config.beta,"rapid group change final selected path is Beta")
    deck.applySelected();scene.stage=8
   } else if (scene.stage===8) {
    selection.reload()
    if (String(selection.text()).trim()===scene.config.beta && !deck.opened) {
      scene.check(true,"explicit Apply writes final Beta to isolated selection file and closes")
      scene.open(scene.rows,scene.config.alpha,"late");scene.stage=9
    }
   } else if (scene.stage===9 && deck.currentPreviewState()==="ready") {
    deck.applySelected();scene.open(scene.rows,scene.config.beta,"new");scene.stage=10
   } else if (scene.stage===10) {
    lateSelection.reload()
    if (String(lateSelection.text()).trim()===scene.config.alpha) { scene.stage=11; scene.ticks=0 }
   } else if (scene.stage===11 && scene.ticks>8) {
    scene.check(deck.opened && deck.currentPath()===scene.config.beta,"old Apply completion cannot close a newer request or replace its selected identity")
    deck.applySelected();scene.stage=12
   } else if (scene.stage===12) {
    finalSelection.reload()
    if (String(finalSelection.text()).trim()===scene.config.beta && !deck.opened) {
      scene.check(true,"newest Apply exports Beta after superseded request")
      scene.finish(true,"Preview state, navigation, replacement and isolated Apply checks passed")
    }
   }
  }
 }
}
'''

if __name__ == "__main__": unittest.main(verbosity=2)
