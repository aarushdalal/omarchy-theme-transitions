import QtQuick
import QtQuick.Controls.Basic
import QtTest
import qs.Commons as ShellCommons
import "components" as Manager

Rectangle {
    id: scene
    width: 1180; height: 660; color: "#101216"
    QtObject {
        id: model
        property string page: "library"
        property var items: [
            {slug:"one",title:"One — deliberately long wallpaper title with Unicode café and a second line",group:"Noir",type:"static",targets:["omarchy","daemon-os"],preview:"",active:true,stock:false},
            {slug:"two",title:"Two",group:"Noir",type:"video",targets:["omarchy","daemon-os"],preview:"",active:false,stock:false},
            {slug:"three",title:"Three",group:"Figures",type:"static",targets:["omarchy","daemon-os"],preview:"",active:false,stock:false},
            {slug:"four",title:"Four",group:"",type:"static",targets:["omarchy","daemon-os"],preview:"",active:false,stock:true}
        ]
        property var groups: ["Noir","Figures"]
        property string groupFilter: "All themes"
        property string search: ""
        property var selected: ({})
        readonly property var selectedSlugs: Object.keys(selected).filter(function(k) {return selected[k]})
        readonly property var visibleItems: items.filter(function(i) {return (groupFilter === "All themes" || (groupFilter === "Ungrouped" ? !i.group : i.group === groupFilter)) && (!search || i.title.toLowerCase().indexOf(search.toLowerCase()) !== -1)})
        property bool busy: false
        property color bg: "#101216"
        property color fg: "#e7e8eb"
        property color accent: "#b7bdca"
        property color surface: "#1b1d22"
        property color outline: "#35383f"
        property var lastRequest: ({})
        property var lastConfirmation: ({})
        function request(p) {lastRequest = p}
        function confirmOperation(p) {lastConfirmation=p}
        function oneSelected() {return selectedSlugs[0] || ""}
        function target() {return "both"}
        function chooseAll() {var chosen={};visibleItems.forEach(function(i){chosen[i.slug]=true});selected=chosen}
    }
    Manager.LibraryPane {id:pane;anchors.fill:parent;anchors.margins:12;manager:model}
    Manager.ManagerMotion {id:policy}

    Component {id:groupFactory;Manager.GroupPicker {x:20;y:20;z:1000;groups:["Existing group","Other group"]}}
    TestCase {
        id:testCase
        name:"PremiumManager"
        when:windowShown
        property var originalItems: []
        function initTestCase() { originalItems = model.items.slice() }
        function item(name) {var value=findChild(pane,name);verify(value!==null,"Missing control "+name);return value}
        function init() {
            model.items = originalItems.slice()
            scene.width=1180;scene.height=660
            model.page="library";model.groupFilter="All themes";model.search="";model.busy=false;model.selected=({});pane.anchor=""
            model.lastRequest=({});model.lastConfirmation=({})
            item("selection-group-name").text="";item("selection-theme-name").text=""
            var scroll=item("selection-inspector");scroll.contentItem.contentY=0
            ShellCommons.Motion.reducedMotion=false
            wait(180)
        }
        function showControl(control) {
            var scroll=item("selection-inspector")
            var pos=control.mapToItem(scroll.contentItem.contentItem,0,0)
            scroll.contentItem.contentY=Math.max(0,Math.min(scroll.contentItem.contentHeight-scroll.availableHeight,pos.y-40))
            wait(30)
        }
        function activate(name) {var control=item(name);verify(control.enabled,"Disabled "+name);showControl(control);mouseClick(control,control.width/2,control.height/2)}
        function test_zero_one_many_context_and_action_gates() {
            compare(item("selection-title").text,"Select a wallpaper")
            verify(!item("apply-selected").enabled);verify(!item("remove-selected").enabled)
            mouseClick(item("apply-selected"));compare(model.lastRequest.action,undefined)
            model.selected=({one:true});wait(50)
            compare(item("selection-title").text,model.items[0].title)
            verify(item("apply-selected").enabled);verify(item("use-group-cover").enabled)
            model.selected=({one:true,two:true});wait(50)
            compare(item("selection-title").text,"2 wallpapers selected")
            verify(!item("apply-selected").enabled);verify(!item("use-group-cover").enabled);verify(item("remove-selected").enabled)
            model.selected=({retired:true});wait(20)
            compare(item("selection-title").text,"Selection unavailable")
        }
        function test_group_counts_filter_empty_and_keyboard_selection() {
            compare(pane.groupCounts.Noir,2);compare(pane.groupCounts.Figures,1);compare(pane.groupCounts.Ungrouped,1)
            var first=item("theme-card-one")
            mouseClick(first,30,70)
            compare(model.selectedSlugs.length,1)
            keyClick(Qt.Key_Right,Qt.ShiftModifier)
            compare(model.selectedSlugs.length,2)
            keyClick(Qt.Key_Right,Qt.ControlModifier)
            compare(model.selectedSlugs.length,2)
            keyClick(Qt.Key_Space)
            compare(model.selectedSlugs.length,3)
            mouseClick(item("clear-selection"));compare(model.selectedSlugs.length,0)
            model.search="no-such-wallpaper";wait(30)
            compare(item("library-grid").count,0)
            model.search="";model.groupFilter="Noir";wait(30)
            compare(item("library-grid").count,2)
            mouseClick(item("select-visible"));compare(model.selectedSlugs.length,2)
        }
        function test_all_action_payloads_preserved() {
            model.selected=({one:true,two:true})
            item("selection-group-name").text="Moved"
            activate("move-group");compare(model.lastRequest.action,"group");compare(model.lastRequest.group,"Moved");compare(model.lastRequest.slugs.length,2)
            activate("leave-ungrouped");compare(model.lastRequest.group,"")
            model.selected=({one:true})
            activate("use-group-cover");compare(model.lastRequest.action,"first");compare(model.lastRequest.slugs[0],"one")
            item("selection-theme-name").text="Edited display name"
            activate("rename-theme");compare(model.lastRequest.action,"rename-theme");compare(model.lastRequest.title,"Edited display name")
            activate("apply-selected");compare(model.lastRequest.action,"apply");compare(model.lastRequest.slug,"one")
            activate("remove-selected");compare(model.lastConfirmation.action,"remove");compare(model.lastConfirmation.target,"both");compare(model.lastConfirmation.items[0].slug,"one")
            model.selected=({});model.groupFilter="Noir";item("selection-group-name").text="Renamed"
            activate("rename-group");compare(model.lastRequest.action,"rename-group");compare(model.lastRequest.old,"Noir");compare(model.lastRequest.group,"Renamed")
            model.groupFilter="Figures"
            activate("dissolve-group");compare(model.lastConfirmation.action,"delete-group");compare(model.lastConfirmation.old,"Figures")
        }
        function test_user_group_names_do_not_collide_with_prototypes() {
            model.items = originalItems.concat([
                {slug:"prototype-group",title:"Prototype group",group:"__proto__",type:"static",preview:"",active:false,stock:false},
                {slug:"constructor-group",title:"Constructor group",group:"constructor",type:"static",preview:"",active:false,stock:false}
            ])
            compare(pane.groupCounts["__proto__"],1)
            compare(pane.groupCounts["constructor"],1)
            compare(pane.groupCounts.Noir,2)
            compare(Object.getPrototypeOf(pane.groupCounts),null)
        }
        function test_busy_disables_mutating_actions() {
            model.selected=({one:true});model.groupFilter="Noir";item("selection-group-name").text="Name";item("selection-theme-name").text="Name";model.busy=true
            var names=["move-group","leave-ungrouped","use-group-cover","rename-group","dissolve-group","rename-theme","apply-selected","remove-selected"]
            for(var i=0;i<names.length;i++)verify(!item(names[i]).enabled,names[i]+" must remain gated")
        }
        function test_layout_data() {return [{tag:"compact",w:760,h:520},{tag:"normal",w:1024,h:620},{tag:"wide",w:1280,h:760}]}
        function test_layout(data) {
            scene.width=data.w;scene.height=data.h;wait(100)
            var grid=item("library-grid"),scroll=item("selection-inspector"),groups=item("library-groups")
            verify(grid.width>=180,"Gallery should retain an operable card width")
            verify(grid.height>180)
            var g=grid.mapToItem(scene,0,0),s=scroll.mapToItem(scene,0,0),n=groups.mapToItem(scene,0,0)
            verify(g.x>n.x+groups.width,"Navigation must not overlap the gallery")
            verify(s.x>=g.x+grid.width,"Inspector must not overlap the gallery")
            verify(s.x+scroll.width<=scene.width,"Inspector must remain inside window")
            var apply=item("apply-selected");var p=apply.mapToItem(scroll,0,0)
            verify(p.y>=0 && p.y+apply.height<=scroll.height,"Primary apply should be visible at inspector entry")
            showControl(item("remove-selected"))
            p=item("remove-selected").mapToItem(scroll,0,0)
            verify(p.y>=0 && p.y+item("remove-selected").height<=scroll.height,"Final action must be reachable by scrolling")
        }
        function test_keyboard_focus_reveals_scrolled_actions() {
            scene.width=760;scene.height=520;model.selected=({"one":true});wait(40)
            // Use an actual fixture slug so the final removal control is enabled.
            var first=model.items[0];model.selected=({});var selected={};selected[first.slug]=true;model.selected=selected
            var scroll=item("selection-inspector"),last=item("remove-selected")
            scroll.contentItem.contentY=0;last.forceActiveFocus();wait(30)
            verify(last.activeFocus);var position=last.mapToItem(scroll,0,0)
            verify(position.y>=0 && position.y+last.height<=scroll.height,"Keyboard focus must reveal the final action")
            var apply=item("apply-selected");apply.forceActiveFocus();wait(30);position=apply.mapToItem(scroll,0,0)
            verify(position.y>=0 && position.y+apply.height<=scroll.height,"Returning focus must reveal Apply")
        }
        function test_motion_policy_reduced_and_hover_is_finite() {
            verify(!policy.reducedMotion);verify(policy.micro>0);verify(policy.standard>0)
            var card=item("theme-card-one"),body=findChild(card,"theme-card-surface")
            var width=card.width,height=card.height
            mouseMove(card,30,70);wait(policy.micro+40)
            compare(card.width,width);compare(card.height,height)
            var settled=body.color
            wait(250);compare(body.color,settled)
            ShellCommons.Motion.reducedMotion=true
            compare(policy.reducedMotion,true);compare(policy.micro,0);compare(policy.standard,0)
            mouseMove(card,10,5);wait(20)
            compare(card.width,width);compare(card.height,height)
        }
        function test_group_edit_stays_stable_during_autosave() {
            var picker=createTemporaryObject(groupFactory,scene)
            verify(picker!==null);picker.setGroup("Existing group")
            picker.contentItem.forceActiveFocus();keyClick(Qt.Key_A,Qt.ControlModifier);keyClick(Qt.Key_Backspace)
            wait(400);compare(picker.editText,"");compare(picker.groupValue,"")
            keyClick(Qt.Key_M);wait(300);keyClick(Qt.Key_Y);wait(300);keyClick(Qt.Key_Space);wait(300)
            compare(picker.editText,"my ")
            picker.groups=["Existing group","External group"];wait(300);compare(picker.editText,"my ")
            keyClick(Qt.Key_G);wait(300);compare(picker.groupValue,"my g");compare(picker.editText,"my g")
            keyClick(Qt.Key_A,Qt.ControlModifier);keyClick(Qt.Key_Backspace);wait(300)
            pane.forceActiveFocus();wait(300);compare(picker.groupValue,"");compare(picker.editText,"Ungrouped")
        }
    }
}
