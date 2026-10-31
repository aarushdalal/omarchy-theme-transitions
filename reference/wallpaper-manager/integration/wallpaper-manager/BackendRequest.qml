import QtQuick
import Quickshell.Io

Item {
    id: bridge
    property string backend
    property string interpreter: "/usr/bin/python3"
    property int startTimeout: 3000
    readonly property bool busy: requestActive
    property bool requestActive: false
    property bool processStarted: false
    property bool receivedResult: false
    property string requestBody: ""
    signal eventReceived(var event)
    signal diagnostic(string text)
    signal finished()

    function send(payload) {
        if (busy) return false
        requestBody = JSON.stringify(payload) + "\n"
        receivedResult = false
        processStarted = false
        requestActive = true
        launchTimeout.restart()
        process.running = true
        return true
    }
    function fail(message) {
        receivedResult = true
        eventReceived({event: "result", ok: false, message: message})
    }
    Process {
        id: process
        // Request bodies can exceed Linux's per-argument size limit. Send one
        // JSON line over stdin; only this fixed command reaches execve.
        command: [bridge.interpreter, bridge.backend, "--request", "-"]
        stdinEnabled: true
        onStarted: {
            bridge.processStarted = true
            launchTimeout.stop()
            write(bridge.requestBody)
            bridge.requestBody = ""
        }
        stdout: SplitParser {
            onRead: data => {
                try {
                    var event = JSON.parse(data)
                    if (event.event === "result") bridge.receivedResult = true
                    bridge.eventReceived(event)
                } catch (e) { bridge.diagnostic(data) }
            }
        }
        stderr: StdioCollector { onStreamFinished: if (text) bridge.diagnostic(text) }
        onExited: function(code) {
            launchTimeout.stop()
            bridge.requestActive = false
            bridge.requestBody = ""
            if (!bridge.receivedResult)
                bridge.fail("The wallpaper helper stopped without a result (exit " + code + "). Your queued batches are kept. Open Details for the error.")
            bridge.finished()
        }
    }
    Timer {
        id: launchTimeout
        interval: bridge.startTimeout
        onTriggered: {
            if (!bridge.requestActive || bridge.processStarted) return
            bridge.requestActive = false
            bridge.requestBody = ""
            bridge.fail("Could not start the wallpaper helper. Your queued batches are kept. Open Details and retry.")
            bridge.finished()
        }
    }
}
