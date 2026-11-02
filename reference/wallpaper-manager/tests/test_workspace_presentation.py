"""Exercise the actual workspace presentation without opening a native desktop overlay."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]

@unittest.skipUnless(shutil.which("quickshell"), "Quickshell is required for workspace presentation checks")
class WorkspacePresentationTests(unittest.TestCase):
    def test_interrupted_entry_reduced_motion_and_compact_controls(self):
        with tempfile.TemporaryDirectory(prefix="wallpaper-workspace-view-") as temp:
            base=Path(temp)
            shutil.copytree(ROOT / "integration/wallpaper-manager",base / "components")
            workspace=base / "components/Workspace.qml"
            text=workspace.read_text()
            old='''    PanelWindow {
        id: panel
        visible: root.opened
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "omarchy-wallpaper-manager"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None'''
            self.assertIn(old,text,"Native wrapper changed; review the isolated adapter")
            # Only replace the native layer-shell wrapper; all production layout/control code stays intact.
            workspace.write_text(text.replace(old,'    Item {\n        id: panel\n        visible: root.opened\n        anchors.fill: parent',1))
            commons=base / "Commons"; commons.mkdir()
            (commons / "qmldir").write_text("module qs.Commons\nsingleton Color 1.0 Color.qml\nsingleton Motion 1.0 Motion.qml\n")
            (commons / "Color.qml").write_text('pragma Singleton\nimport QtQuick\nQtObject {property color background:"#101216";property color foreground:"#e7e8eb";property color accent:"#b7bdca"}')
            (commons / "Motion.qml").write_text('pragma Singleton\nimport QtQuick\nQtObject {property bool reducedMotion:false;property int micro:80;property int standard:180;property int easeMicro:Easing.OutQuad}')
            home=base / "home";backend=home / "Projects/wallpaper-importer/wallpaper_manager.py";backend.parent.mkdir(parents=True)
            backend.write_text('import json\nprint(json.dumps({"event":"result","ok":True,"draft_batches":[],"items":[],"groups":[],"jobs":[]}))\n')
            receipt=base / "result.json"
            expected_index=1 if 'id: targetBox; currentIndex: 1;' in text else 0
            # The reference also includes objectName between id/currentIndex after presentation changes.
            if 'id: targetBox; objectName: "manager-target"; currentIndex: 1;' in text:
                expected_index=1
            qml='''import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io
import qs.Commons as ShellCommons
import "components" as Manager
ShellRoot {
 id: scene
 property int switches:0
 property bool finished:false
 FileView {id:receipt;path:RECEIPT;printErrors:false}
 function finish(ok,message) {if(finished)return;finished=true;receipt.setText(JSON.stringify({ok:ok,message:message,switches:switches,progress:manager.presentationProgress,reducedMotion:manager.reducedMotion}));Qt.callLater(Qt.quit)}
 function find(item,name) {if(item.objectName===name)return item;var children=item.children||[];for(var i=0;i<children.length;i++){var found=find(children[i],name);if(found)return found}return null}
 function inside(child,parent) {if(!child)return false;var p=child.mapToItem(parent,0,0);return p.x>=-1 && p.y>=-1 && p.x+child.width<=parent.width+1 && p.y+child.height<=parent.height+1}
 Window {
  id:window;visible:true;width:1200;height:760
  Manager.Workspace {id:manager;anchors.fill:parent}
 }
 Timer {
  id:cycles;interval:15;running:true;repeat:true
  onTriggered:{manager.opened=scene.switches%2===0;scene.switches++;if(scene.switches===20){stop();manager.opened=true;settle.start()}}
 }
 Timer {
  id:settle;interval:300
  onTriggered:{
   if(!manager.opened || Math.abs(manager.presentationProgress-1)>0.001){scene.finish(false,"Interrupted entry did not settle");return}
   ShellCommons.Motion.reducedMotion=true
   manager.opened=false;manager.opened=true
   if(!manager.reducedMotion || manager.presentationProgress!==1){scene.finish(false,"Reduced motion did not snap to final state");return}
   window.width=900;window.height=650;bounds.start()
  }
 }
 Timer {
  id:bounds;interval:100
  onTriggered:{
   var panel=scene.find(manager,"manager-panel-card"),target=scene.find(manager,"manager-target")
   var names=["manager-search","manager-library-nav","manager-add-nav","manager-target"]
   for(var i=0;i<names.length;i++)if(!scene.inside(scene.find(manager,names[i]),panel)){scene.finish(false,names[i]+" clipped outside compact panel");return}
   if(target.currentIndex!==EXPECTED){scene.finish(false,"Operation target default changed");return}
   scene.finish(true,"20 interrupted entries, immediate reduced-motion state and compact primary controls verified")
  }
 }
 Timer {interval:6000;running:true;onTriggered:scene.finish(false,"Workspace test timed out")}
}'''.replace("RECEIPT",json.dumps(str(receipt))).replace("EXPECTED",str(expected_index))
            (base / "shell.qml").write_text(qml)
            env=dict(os.environ,HOME=str(home),XDG_CONFIG_HOME=str(home / ".config"),XDG_STATE_HOME=str(home / ".local/state"),QT_QPA_PLATFORM="offscreen",QT_QUICK_BACKEND="software")
            run=subprocess.run(["quickshell","-p",str(base),"--no-color"],env=env,capture_output=True,text=True,timeout=12)
            self.assertEqual(run.returncode,0,run.stdout+run.stderr)
            self.assertTrue(receipt.is_file(),run.stdout+run.stderr)
            result=json.loads(receipt.read_text())
            self.assertTrue(result["ok"],str(result)+run.stdout+run.stderr)
            self.assertEqual(result["switches"],20)
