// cliamp state + actions. Loaded only while the card is open on cliamp (and
// kept alive until a running action finishes).
import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: ctl

  // The Humline BarWidget, passed in by the Loader before bindings run.
  required property var widget

  property bool shuffle: false
  property string repeat: "Off"
  property bool fav: false
  // cliamp's own track path (MPRIS only has a URL-encoded xesam:url).
  property string path: ""
  property string title: ""
  property string message: ""
  // True from launch until the reply has been handled (not just on exit).
  property bool busy: false
  onBusyChanged: ctl.widget.cliampBusy = busy
  Component.onDestruction: ctl.widget.cliampBusy = false
  // A state reply was dropped because an action ran; refresh after it.
  property bool stateStale: false
  // Bumped by every action so an older state reply can't undo its result.
  property int generation: 0
  property int stateGeneration: 0
  property bool stateAgain: false

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
    if (r.title !== undefined) title = r.title
  }

  function helper(args) {
    return ["python3", ctl.widget.cliampHelper].concat(args)
  }

  function refresh() {
    if (stateProc.running) {
      stateAgain = true
      return
    }
    stateGeneration = generation
    stateProc.command = helper(["state"])
    stateProc.running = true
  }

  // One action at a time; `done(reply)` runs after the helper exits.
  function run(args, done, owner) {
    if (busy) {
      flash("cliamp is busy…")
      return false
    }
    generation++
    busy = true
    actionProc.done = done || null
    actionProc.owner = owner || null
    actionProc.command = helper(args)
    actionProc.running = true
    return true
  }

  // A closing page drops its pending callback; the action still completes.
  function detach(owner) {
    if (actionProc.owner === owner) {
      actionProc.done = null
      actionProc.owner = null
    }
  }

  function toggleFavorite() {
    run(["fav", path], function(r) {
      if (r.ok) flash(r.fav ? "Added to favorites" : "Removed from favorites")
      else ctl.refresh()
    })
  }

  Component.onCompleted: refresh()

  Connections {
    target: ctl.widget
    // Forget the old track at once so nothing acts on it meanwhile.
    function onTitleChanged() { ctl.trackChanged() }
    function onTrackUrlChanged() { ctl.trackChanged() }
  }

  function trackChanged() {
    path = ""
    title = ""
    fav = false
    refreshTimer.restart()
  }

  Timer { id: refreshTimer; interval: 400; onTriggered: ctl.refresh() }
  Timer { id: againTimer; interval: 0; onTriggered: ctl.refresh() }
  Timer { id: messageTimer; interval: 3000; onTriggered: ctl.message = "" }

  Process {
    id: stateProc
    stdout: StdioCollector {
      onStreamFinished: {
        if (ctl.stateGeneration === ctl.generation && !ctl.busy) ctl.apply(ctl.widget.parseReply(text))
        else if (ctl.busy) ctl.stateStale = true
        else ctl.stateAgain = true
      }
    }
    onExited: if (ctl.stateAgain) {
      ctl.stateAgain = false
      againTimer.restart()
    }
  }

  Process {
    id: actionProc
    property var done: null
    property var owner: null
    stdout: StdioCollector {
      onStreamFinished: {
        var r = ctl.widget.parseReply(text)
        if (r.ok) ctl.apply(r)
        else ctl.flash(r.error || "cliamp error")
        var cb = actionProc.done
        actionProc.done = null
        actionProc.owner = null
        ctl.busy = false
        if (cb) cb(r)
        if (ctl.stateStale) {
          ctl.stateStale = false
          againTimer.restart()
        }
      }
    }
  }
}
