import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris

// Shared state for every Humline bar widget (one per monitor): which player
// is active and the one cava process that feeds the spectrum. Sharing it here
// keeps a multi-monitor setup at a single cava.
Item {
  id: root

  // Players with something to show; playerctld only mirrors other players.
  readonly property var sourcePlayers: {
    var all = Mpris.players ? Mpris.players.values : []
    var result = []
    for (var i = 0; i < all.length; i++) {
      var p = all[i]
      if (!p || String(p.dbusName || "").indexOf("playerctld") !== -1) continue
      if (p.trackTitle || p.trackArtist) result.push(p)
    }
    return result
  }

  // The player picked in the card; only wins while it is playing.
  property string selectedKey: ""
  readonly property var activePlayer: {
    var players = sourcePlayers
    var selected = null
    var firstPlaying = null
    for (var i = 0; i < players.length; i++) {
      if (playerKey(players[i]) === selectedKey) selected = players[i]
      if (!firstPlaying && players[i].isPlaying) firstPlaying = players[i]
    }
    if (selected && selected.isPlaying) return selected
    return firstPlaying || selected || (players.length ? players[0] : null)
  }

  readonly property bool playing: activePlayer !== null && activePlayer.isPlaying
    && !!(activePlayer.trackTitle || activePlayer.trackArtist)
  property var bands: []
  property bool cavaMissing: false

  function playerKey(player) { return player ? String(player.dbusName || "") : "" }
  function selectPlayer(player) { selectedKey = playerKey(player) }
  function localPath(name) { return decodeURIComponent(String(Qt.resolvedUrl(name)).replace(/^file:\/\//, "")) }

  onPlayingChanged: if (!playing) bands = []

  // cava analyses the actual PipeWire output, so the spectrum works for any player.
  Process {
    id: visStream
    command: ["sh", "-c", "command -v cava >/dev/null || exit 127; exec cava -p \"$1\"", "sh", root.localPath("cava.conf")]
    running: root.playing && !root.cavaMissing
    stdout: SplitParser {
      onRead: function(line) {
        var parts = line.split(";")
        var values = []
        for (var i = 0; i < parts.length; i++) {
          if (parts[i] !== "") values.push(Number(parts[i]) / 100)
        }
        if (values.length) root.bands = values
      }
    }
    onExited: function(exitCode) {
      if (exitCode === 127) root.cavaMissing = true
      else if (root.playing) visRestart.restart()
    }
  }

  Timer {
    id: visRestart
    interval: 1500
    onTriggered: if (root.playing && !root.cavaMissing && !visStream.running) visStream.running = true
  }
}
