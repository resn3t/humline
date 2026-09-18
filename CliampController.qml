// cliamp state + actions; loaded only while the card is open on cliamp.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

Item {
  id: ctl

  // The nowpip BarWidget, passed in by the Loader before bindings run.
  required property var widget

  property bool shuffle: false
  property string repeat: "Off"
  property bool fav: false
  property string path: ""
  property string message: ""
  property bool stateAgain: false
  readonly property bool busy: actionProc.running

  function flash(text) {
    message = text
    messageTimer.restart()
  }

  function apply(r) {
    if (!r || !r.ok) return
    if (r.shuffle !== undefined) shuffle = r.shuffle
    if (r.repeat !== undefined) repeat = r.repeat
    if (r.fav !== undefined) fav = r.fav
    if (r.path !== undefined) path = r.path
  }

  function refresh() {
    if (stateProc.running) stateAgain = true
    else stateProc.running = true
  }

  // One action at a time; `done(reply)` runs after the helper exits.
  function run(args, done) {
    if (actionProc.running) {
      flash("cliamp is busy…")
      return false
    }
    actionProc.done = done || null
    actionProc.command = ["bash", widget.cliampHelper].concat(args)
    actionProc.running = true
    return true
  }

  function toggleFavorite() {
    run(["fav", path], function(r) {
      if (r.ok) flash(r.fav ? "Added to favorites" : "Removed from favorites")
      else ctl.refresh()
    })
  }

  Component.onCompleted: refresh()

  Connections {
    target: widget
    function onTitleChanged() { refreshTimer.restart() }
    function onTrackUrlChanged() { refreshTimer.restart() }
  }

  Timer { id: refreshTimer; interval: 400; onTriggered: ctl.refresh() }
  Timer { id: messageTimer; interval: 3000; onTriggered: ctl.message = "" }

  Process {
    id: stateProc
    command: ["bash", widget.cliampHelper, "state"]
    stdout: StdioCollector {
      onStreamFinished: ctl.apply(widget.parseReply(text))
    }
    onExited: if (ctl.stateAgain) {
      ctl.stateAgain = false
      Qt.callLater(ctl.refresh)
    }
  }

  Process {
    id: actionProc
    property var done: null
    stdout: StdioCollector {
      onStreamFinished: {
        var r = widget.parseReply(text)
        if (r.ok) ctl.apply(r)
        else ctl.flash(r.error || "cliamp error")
        var cb = actionProc.done
        actionProc.done = null
        if (cb) cb(r)
      }
    }
  }
}
