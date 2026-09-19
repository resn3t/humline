import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.Ui
import qs.Commons

BarWidget {
  id: root
  moduleName: "humline"

  // Player choice and the single cava live in Service.qml, shared by every
  // bar (one per monitor).
  readonly property var service: bar && bar.shell ? bar.shell.serviceFor("humline") : null
  readonly property var sourcePlayers: service ? service.sourcePlayers : []
  readonly property var activePlayer: service ? service.activePlayer : null
  readonly property bool cavaMissing: service ? service.cavaMissing : false

  // Tunable from the manifest schema (shell.json entry).
  readonly property bool hideWhenPaused: setting("hideWhenPaused", false) === true
  readonly property int dotCount: Math.max(4, Math.min(10, Math.round(Number(setting("dotCount", 10)) || 10)))

  function playerKey(player) { return player ? String(player.dbusName || "") : "" }
  function selectPlayer(player) { if (service) service.selectPlayer(player) }
  function localPath(name) { return decodeURIComponent(String(Qt.resolvedUrl(name)).replace(/^file:\/\//, "")) }

  readonly property bool hasMedia: activePlayer !== null && (activePlayer.trackTitle || activePlayer.trackArtist)
  readonly property string title: activePlayer ? (activePlayer.trackTitle || "") : ""
  readonly property string artist: activePlayer ? (activePlayer.trackArtist || "") : ""
  // Ads and some streams send no title; show the player instead of a blank.
  readonly property string displayTitle: title || (activePlayer ? (activePlayer.identity || "") : "")

  readonly property bool playing: hasMedia && activePlayer.isPlaying
  readonly property bool canSetVolume: !!activePlayer && activePlayer.volumeSupported === true
  readonly property var bands: service ? service.bands : []
  // The bar face shows dotCount bands sampled evenly from cava's ten.
  readonly property var barBands: {
    if (dotCount >= bands.length) return bands
    var out = []
    for (var i = 0; i < dotCount; i++) out.push(bands[Math.floor(i * bands.length / dotCount)])
    return out
  }

  readonly property string trackUrl: activePlayer && activePlayer.metadata ? String(activePlayer.metadata["xesam:url"] || "") : ""
  readonly property string spotifyTrackId: {
    var m = trackUrl.match(/^spotify:track:([A-Za-z0-9]+)$/) || trackUrl.match(/open\.spotify\.com\/track\/([A-Za-z0-9]+)/)
    return m ? m[1] : ""
  }
  property var fetchedArt: ({})
  // cliamp streams have no cover, and cliamp keeps reporting the previous
  // file's cover file for them; show cliamp's own logo instead of that.
  readonly property bool cliampLogo: isCliamp && (!activePlayer.trackArtUrl
    || (trackUrl.indexOf("file://") !== 0 && String(activePlayer.trackArtUrl).indexOf("file://") === 0))
  readonly property string spotifyArt: spotifyTrackId && fetchedArt[spotifyTrackId] ? fetchedArt[spotifyTrackId] : ""
  readonly property string artUrl: cliampLogo ? (spotifyArt || Qt.resolvedUrl("assets/cliamp-logo.png"))
    : (activePlayer && activePlayer.trackArtUrl ? activePlayer.trackArtUrl : spotifyArt)

  // A cliamp radio stream (http url) that shows the logo also reports a stale
  // album and length from the previous file. Spotify and files keep theirs.
  readonly property bool cliampStream: cliampLogo && /^https?:\/\//.test(trackUrl)

  readonly property bool hasLength: !cliampStream && !!activePlayer && activePlayer.lengthSupported && activePlayer.length > 0
  readonly property bool canSeek: hasLength && activePlayer.canSeek && activePlayer.positionSupported

  property bool popupOpen: false

  // cliamp extras. Everything cliamp-specific lives in Loaders that only
  // exist while the card is open on a cliamp track; nothing runs otherwise.
  readonly property bool isCliamp: !!activePlayer
    && (playerKey(activePlayer) === "org.mpris.MediaPlayer2.cliamp" || activePlayer.identity === "Cliamp")
  // Stays true during the card's fade-out so it doesn't reflow while closing.
  readonly property bool cliampOpen: (popupOpen || popup.visible) && isCliamp
  // "main", "browse" (provider browser) or "lists" (add to playlist).
  property string view: "main"
  property string browseProvider: ""
  readonly property var cliamp: cliampLoader.item
  // Set by the controller; keeps it loaded until a running action finishes.
  property bool cliampBusy: false
  readonly property string cliampHelper: localPath("bin/humline-cliamp")

  onIsCliampChanged: if (!isCliamp) view = "main"

  // Generic MPRIS shuffle/loop for players that support them; cliamp does
  // not expose these over MPRIS, so it goes through its own IPC instead.
  readonly property bool canShuffle: isCliamp ? !!cliamp : (!!activePlayer && activePlayer.shuffleSupported === true)
  readonly property bool canLoop: isCliamp ? !!cliamp : (!!activePlayer && activePlayer.loopSupported === true)
  readonly property bool shuffleOn: isCliamp ? (!!cliamp && cliamp.shuffle) : (!!activePlayer && activePlayer.shuffle === true)
  // "Off", "All" or "One".
  readonly property string loopMode: isCliamp ? (cliamp ? cliamp.repeat : "Off")
    : (!activePlayer ? "Off" : activePlayer.loopState === MprisLoopState.Track ? "One"
      : activePlayer.loopState === MprisLoopState.Playlist ? "All" : "Off")

  function toggleShuffle() {
    if (isCliamp) { if (cliamp) cliamp.run(["shuffle"]) }
    else if (canShuffle) activePlayer.shuffle = !activePlayer.shuffle
  }

  function cycleLoop() {
    if (isCliamp) { if (cliamp) cliamp.run(["repeat"]) }
    else if (canLoop) activePlayer.loopState = loopMode === "Off" ? MprisLoopState.Playlist
      : (loopMode === "All" ? MprisLoopState.Track : MprisLoopState.None)
  }

  function openView(name) {
    if (!isCliamp) return
    view = name
    popupOpen = true
  }

  // Some players publish a Spotify track URI but no cover; ask Spotify's
  // public oEmbed endpoint for the track thumbnail instead.
  onSpotifyTrackIdChanged: fetchSpotifyArt()
  onCliampLogoChanged: fetchSpotifyArt()
  Component.onCompleted: fetchSpotifyArt()

  function fetchSpotifyArt() {
    var id = spotifyTrackId
    if (!id || fetchedArt[id] || (activePlayer && activePlayer.trackArtUrl && !cliampLogo)) return
    var xhr = new XMLHttpRequest()
    xhr.onreadystatechange = function() {
      if (xhr.readyState !== XMLHttpRequest.DONE || xhr.status !== 200) return
      try {
        var thumb = JSON.parse(xhr.responseText).thumbnail_url
        if (thumb) {
          var cache = Object.assign({}, root.fetchedArt)
          cache[id] = thumb
          root.fetchedArt = cache
        }
      } catch (error) {
      }
    }
    xhr.open("GET", "https://open.spotify.com/oembed?url=spotify:track:" + id)
    xhr.send()
  }

  function formatTime(seconds) {
    var s = Math.max(0, Math.floor(seconds || 0))
    var h = Math.floor(s / 3600)
    var m = Math.floor((s % 3600) / 60)
    var sec = s % 60
    var ss = (sec < 10 ? "0" : "") + sec
    return h > 0 ? h + ":" + (m < 10 ? "0" : "") + m + ":" + ss : m + ":" + ss
  }

  function seekTo(seconds) {
    if (!canSeek) return
    activePlayer.position = Math.max(0, Math.min(activePlayer.length - 1, seconds))
    activePlayer.positionChanged()
  }

  // MPRIS position is not pushed; re-read it while the card is visible.
  Timer {
    interval: 1000
    repeat: true
    running: root.popupOpen && root.hasLength
    triggeredOnStart: true
    onTriggered: if (root.activePlayer) root.activePlayer.positionChanged()
  }

  function close() { popupOpen = false }

  // Card keys (KeyboardPanel): arrows/hjkl, Space, Tab and letters.
  function cycleSource(direction) {
    var players = sourcePlayers
    if (players.length < 2) return
    var at = 0
    for (var i = 0; i < players.length; i++) if (playerKey(players[i]) === playerKey(activePlayer)) at = i
    selectPlayer(players[(at + direction + players.length) % players.length])
  }

  function cardMove(dx, dy) {
    if (view !== "main") { if (pageLoader.item && dx !== 0) pageLoader.item.step(dx); return }
    if (!activePlayer) return
    if (dx > 0 && activePlayer.canGoNext) activePlayer.next()
    else if (dx < 0 && activePlayer.canGoPrevious) activePlayer.previous()
    else if (dy !== 0 && canSetVolume) setVolume(activePlayer.volume - dy * 0.05)
  }

  function cardKey(text) {
    if (view !== "main" || !activePlayer) return
    var k = text.toLowerCase()
    if (k === "s") toggleShuffle()
    else if (k === "r") cycleLoop()
    else if (k === "g") focusPlayer(activePlayer)
    else if (k === ",") { activePlayer.positionChanged(); seekTo(activePlayer.position - 10) }
    else if (k === ".") { activePlayer.positionChanged(); seekTo(activePlayer.position + 10) }
    else if (isCliamp && k === "f") { if (cliamp) cliamp.toggleFavorite() }
    else if (isCliamp && k === "a") view = "lists"
    else if (isCliamp && k === "b") view = "browse"
  }

  function focusPlayer(player) {
    if (!player || !player.dbusName) return
    popupOpen = false
    focusProc.command = ["bash", localPath("bin/humline-focus"), String(player.dbusName), String(player.trackTitle || ""),
                       String((player.metadata && player.metadata["xesam:url"]) || "")]
    focusProc.running = true
  }

  function setVolume(v) {
    if (canSetVolume) activePlayer.volume = Math.max(0, Math.min(1, v))
  }

  readonly property bool shown: hasMedia && (playing || popupOpen || !hideWhenPaused)
  visible: shown
  implicitWidth: shown ? (playing ? barSpectrum.implicitWidth : glyph.implicitWidth) + Style.space(12) : 0
  implicitHeight: barSize

  Process { id: focusProc }
  // Fire-and-forget cliamp action from IPC while the card is closed.
  Process {
    id: cliampIpcProc
    stdout: StdioCollector {
      onStreamFinished: {
        var r = root.parseReply(text)
        notifyProc.command = ["notify-send", "-a", "Humline", "-t", "2000", r.ok ? (r.fav ? "Added to favorites" : "Removed from favorites") : "Could not change favorites"]
        notifyProc.running = true
      }
    }
  }
  Process { id: notifyProc }

  // The cliamp files are only compiled and instantiated on demand;
  // clearing `source` destroys them again.
  function loadOnDemand(loader, wanted, file) {
    if (wanted) loader.setSource(Qt.resolvedUrl(file), { widget: root })
    else loader.source = ""
  }

  Loader {
    id: cliampLoader
    // Stays loaded until a running action finishes, so closing the card
    // never drops a like/add/load halfway.
    readonly property bool wanted: root.cliampOpen || root.cliampBusy
    onWantedChanged: root.loadOnDemand(cliampLoader, wanted, "CliampController.qml")
  }

  IpcHandler {
    target: "humline"

    function togglePopup(): void { root.popupOpen = root.hasMedia && !root.popupOpen }
    function focusPlayer(): void { root.focusPlayer(root.activePlayer) }
    // cliamp only: like/unlike the current track (cliamp favorites).
    function toggleFavorite(): void {
      if (!root.isCliamp) return
      if (root.cliamp) root.cliamp.toggleFavorite()
      else if (!cliampIpcProc.running) {
        cliampIpcProc.command = ["python3", root.cliampHelper, "fav", ""]
        cliampIpcProc.running = true
      }
    }
    // cliamp only: open the card on the source browser / playlist picker.
    function browse(): void { root.openView("browse") }
    // cliamp only: open the browser on a provider key (radio, local, spotify…).
    function browseSource(provider: string): void {
      root.browseProvider = provider
      root.openView("browse")
    }
    function addToPlaylist(): void { root.openView("lists") }
    // Change the active player's volume by `delta` (0..1 scale, e.g. 0.05).
    function volume(delta: real): void { if (root.canSetVolume) root.setVolume(root.activePlayer.volume + delta) }
    function seek(offsetSeconds: real): void {
      if (!root.activePlayer) return
      root.activePlayer.positionChanged()
      root.seekTo(root.activePlayer.position + offsetSeconds)
    }
  }

  DotSpectrum {
    id: barSpectrum
    anchors.centerIn: parent
    visible: root.playing && !root.cavaMissing
    bands: root.barBands
    bandCount: root.dotCount
    rows: 5
    dotWidth: 3
    dotHeight: 2
    gap: 1
    litColor: root.bar.barForeground
    peakColor: Color.accent
    dimColor: "transparent"
  }

  Text {
    id: glyph
    visible: !root.playing || root.cavaMissing
    textFormat: Text.PlainText
    anchors.centerIn: parent
    text: activePlayer && activePlayer.isPlaying ? "󰝚" : "󰏤"
    color: activePlayer && activePlayer.isPlaying ? root.bar.barForeground : Qt.darker(root.bar.barForeground, 1.5)
    font.family: root.bar.fontFamily
    font.pixelSize: Style.font.body
    Behavior on color {
      enabled: !root.bar || root.bar.foregroundAnimationEnabled
      ColorAnimation { duration: 160 }
    }
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: root.activePlayer ? Qt.PointingHandCursor : Qt.ArrowCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

    onClicked: function(mouse) {
      if (!root.activePlayer) return
      if (root.bar) root.bar.hideTooltip(root)
      if (mouse.button === Qt.MiddleButton) {
        root.activePlayer.togglePlaying()
      } else if (mouse.button === Qt.RightButton) {
        root.focusPlayer(root.activePlayer)
      } else {
        root.popupOpen = !root.popupOpen
      }
    }
    onWheel: function(wheel) {
      if (!root.activePlayer) return
      if (wheel.angleDelta.y > 0 && root.activePlayer.canGoPrevious) root.activePlayer.previous()
      else if (wheel.angleDelta.y < 0 && root.activePlayer.canGoNext) root.activePlayer.next()
    }
    onEntered: if (root.bar && !root.popupOpen) root.bar.showTooltip(root, root.hasMedia ? (root.displayTitle + (root.artist ? " — " + root.artist : "") + "\nRight-click: go to player") : "")
    onExited: if (root.bar) root.bar.hideTooltip(root)
  }

  KeyboardPanel {
    id: popup
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.popupOpen
    focusTarget: keyCatcher
    onVisibleChanged: if (!visible) root.view = "main"
    contentWidth: popup.fittedContentWidth(Style.space(320))
    contentHeight: popup.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) { root.cardMove(dx, dy) }
      onActivateRequested: if (root.view === "main" && root.activePlayer) root.activePlayer.togglePlaying()
      onCloseRequested: {
        if (root.view !== "main") { if (!(pageLoader.item && pageLoader.item.leaveFolder())) root.view = "main" }
        else root.popupOpen = false
      }
      onTabRequested: function(direction) { if (root.view === "main") root.cycleSource(direction) }
      onTextKey: function(text) { root.cardKey(text) }

    Column {
      id: column
      anchors.fill: parent

      // cliamp browser / playlist picker replaces the card body while shown.
      Loader {
        id: pageLoader
        readonly property bool wanted: root.cliampOpen && root.view !== "main"
        width: parent.width
        visible: item !== null
        onWantedChanged: root.loadOnDemand(pageLoader, wanted, "CliampPage.qml")
      }

      Column {
        id: mainView
        width: parent.width
        visible: pageLoader.item === null
        spacing: Style.space(10)

        Row {
          spacing: Style.space(10)
          width: parent.width

          BorderSurface {
            width: Style.space(64)
            height: Style.space(64)
            radius: Style.spacing.labelGap
            color: Style.normalFillFor(root.bar.foreground, Color.accent)
            borderSpec: Border.controlSpec("normal", root.bar.foreground, Color.accent)

            Image {
              anchors.fill: parent
              anchors.margins: Style.space(2)
              fillMode: Image.PreserveAspectCrop
              asynchronous: true
              source: root.artUrl
              visible: source !== ""
            }

            Text {
              anchors.centerIn: parent
              visible: root.artUrl === ""
              text: "󰝚"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.displayLarge
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.focusPlayer(root.activePlayer)
            }
          }

          Column {
            spacing: Style.space(4)
            width: parent.width - Style.space(64) - headerFocusButton.width - parent.spacing * 2

            Text {
              textFormat: Text.PlainText
              text: root.displayTitle || "Nothing playing"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.subtitle
              font.bold: true
              elide: Text.ElideRight
              width: parent.width
            }

            Text {
              textFormat: Text.PlainText
              text: root.artist
              color: Color.muted
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
              width: parent.width
              visible: text !== ""
            }

            Text {
              textFormat: Text.PlainText
              text: root.activePlayer && !root.cliampStream && root.activePlayer.trackAlbum ? root.activePlayer.trackAlbum : ""
              color: Color.muted
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
              width: parent.width
              visible: text !== ""
            }
          }

          Button {
            id: headerFocusButton
            iconText: "󰁔"
            foreground: root.bar.foreground
            horizontalPadding: Style.spacing.controlPaddingY
            verticalPadding: Style.spacing.controlPaddingY
            tooltipText: "Go to " + (root.activePlayer && root.activePlayer.identity ? root.activePlayer.identity : "player")
            onClicked: root.focusPlayer(root.activePlayer)
          }
        }

        DotSpectrum {
          visible: root.playing
          anchors.horizontalCenter: parent.horizontalCenter
          bands: root.bands
          rows: 10
          gap: Style.space(2)
          dotWidth: Math.floor((parent.width - gap * 9) / 10)
          dotHeight: Style.space(3)
          litColor: Color.accent
          peakColor: root.bar.foreground
          dimColor: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.08)
        }

        Row {
          id: progressRow
          visible: root.hasLength
          width: parent.width
          spacing: Style.space(8)

          readonly property real position: root.activePlayer ? root.activePlayer.position : 0
          readonly property real length: root.activePlayer ? root.activePlayer.length : 0

          Text {
            id: elapsedLabel
            textFormat: Text.PlainText
            anchors.verticalCenter: parent.verticalCenter
            text: root.formatTime(progressSlider.dragging ? progressSlider.liveValue : progressRow.position)
            color: Color.muted
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            width: Style.space(40)
          }

          PanelSlider {
            id: progressSlider
            bar: root.bar
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - elapsedLabel.width - totalLabel.width - parent.spacing * 2
            minimum: 0
            maximum: Math.max(1, progressRow.length)
            step: 10
            value: progressRow.position
            enabled: root.canSeek
            onReleased: function(v) { root.seekTo(v) }
          }

          Text {
            id: totalLabel
            textFormat: Text.PlainText
            anchors.verticalCenter: parent.verticalCenter
            text: root.formatTime(progressRow.length)
            color: Color.muted
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            width: Style.space(40)
            horizontalAlignment: Text.AlignRight
          }
        }

        Row {
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Style.space(6)

          Button {
            visible: root.canShuffle
            anchors.verticalCenter: parent.verticalCenter
            iconText: root.shuffleOn ? "󰒝" : "󰒞"
            foreground: root.bar.foreground
            active: root.shuffleOn
            opacity: root.shuffleOn ? 1.0 : 0.55
            horizontalPadding: Style.spacing.controlPaddingY
            verticalPadding: Style.spacing.controlPaddingY
            tooltipText: root.shuffleOn ? "Shuffle on" : "Shuffle off"
            onClicked: root.toggleShuffle()
          }

          Button {
            iconText: "󰒮"
            foreground: root.bar.foreground
            horizontalPadding: Style.spacing.controlPaddingX
            verticalPadding: Style.spacing.controlPaddingY
            enabled: root.activePlayer && root.activePlayer.canGoPrevious
            opacity: enabled ? 1.0 : 0.4
            onClicked: if (root.activePlayer) root.activePlayer.previous()
          }

          Button {
            iconText: root.activePlayer && root.activePlayer.isPlaying ? "󰏤" : "󰐊"
            foreground: root.bar.foreground
            horizontalPadding: Style.spacing.panelGap
            verticalPadding: Style.spacing.controlPaddingY
            iconSize: Style.font.iconLarge
            enabled: root.activePlayer && (root.activePlayer.canTogglePlaying || root.activePlayer.canPlay || root.activePlayer.canPause)
            opacity: enabled ? 1.0 : 0.4
            onClicked: if (root.activePlayer) root.activePlayer.togglePlaying()
          }

          Button {
            iconText: "󰒭"
            foreground: root.bar.foreground
            horizontalPadding: Style.spacing.controlPaddingX
            verticalPadding: Style.spacing.controlPaddingY
            enabled: root.activePlayer && root.activePlayer.canGoNext
            opacity: enabled ? 1.0 : 0.4
            onClicked: if (root.activePlayer) root.activePlayer.next()
          }

          Button {
            visible: root.canLoop
            anchors.verticalCenter: parent.verticalCenter
            iconText: root.loopMode === "One" ? "󰑘" : (root.loopMode === "All" ? "󰑖" : "󰑗")
            foreground: root.bar.foreground
            active: root.loopMode !== "Off"
            opacity: root.loopMode !== "Off" ? 1.0 : 0.55
            horizontalPadding: Style.spacing.controlPaddingY
            verticalPadding: Style.spacing.controlPaddingY
            tooltipText: "Repeat: " + root.loopMode.toLowerCase()
            onClicked: root.cycleLoop()
          }
        }

        // cliamp: like, add to playlist, browse sources.
        Row {
          visible: !!root.cliamp
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Style.space(6)

          Button {
            iconText: root.cliamp && root.cliamp.fav ? "󰋑" : "󰋕"
            foreground: root.cliamp && root.cliamp.fav ? Color.accent : root.bar.foreground
            horizontalPadding: Style.spacing.controlPaddingX
            verticalPadding: Style.spacing.controlPaddingY
            enabled: !!root.cliamp && root.cliamp.path !== "" && !root.cliamp.busy
            opacity: enabled ? 1.0 : 0.4
            tooltipText: root.cliamp && root.cliamp.fav ? "Remove from cliamp favorites" : "Add to cliamp favorites"
            onClicked: root.cliamp.toggleFavorite()
          }

          Button {
            iconText: "󰐒"
            foreground: root.bar.foreground
            horizontalPadding: Style.spacing.controlPaddingX
            verticalPadding: Style.spacing.controlPaddingY
            enabled: !!root.cliamp && root.cliamp.path !== ""
            opacity: enabled ? 1.0 : 0.4
            tooltipText: "Add to playlist"
            onClicked: root.view = "lists"
          }

          Button {
            iconText: "󰌱"
            foreground: root.bar.foreground
            horizontalPadding: Style.spacing.controlPaddingX
            verticalPadding: Style.spacing.controlPaddingY
            tooltipText: "Browse cliamp sources"
            onClicked: root.view = "browse"
          }
        }

        Text {
          visible: !!root.cliamp && root.cliamp.message !== ""
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          textFormat: Text.PlainText
          text: root.cliamp ? root.cliamp.message : ""
          color: Color.muted
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }

        Row {
          id: volumeRow
          visible: root.canSetVolume
          width: parent.width
          spacing: Style.space(8)

          readonly property real volume: root.activePlayer ? root.activePlayer.volume : 0

          Text {
            id: volumeIcon
            textFormat: Text.PlainText
            anchors.verticalCenter: parent.verticalCenter
            text: volumeRow.volume <= 0.001 ? "󰝟" : (volumeRow.volume < 0.34 ? "󰕿" : (volumeRow.volume < 0.67 ? "󰖀" : "󰕾"))
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.body
            width: Style.space(18)
            horizontalAlignment: Text.AlignHCenter
          }

          PanelSlider {
            bar: root.bar
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - volumeIcon.width - volumeLabel.width - parent.spacing * 2
            minimum: 0
            maximum: 1
            step: 0.05
            value: volumeRow.volume
            onMoved: function(v) { root.setVolume(v) }
          }

          Text {
            id: volumeLabel
            textFormat: Text.PlainText
            anchors.verticalCenter: parent.verticalCenter
            text: Math.round(volumeRow.volume * 100) + "%"
            color: Color.muted
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            width: Style.space(34)
            horizontalAlignment: Text.AlignRight
          }
        }

        PanelSeparator {
          visible: root.sourcePlayers.length > 1
          foreground: root.bar.foreground
        }

        Column {
          id: sourceList
          visible: root.sourcePlayers.length > 1
          width: parent.width
          spacing: Style.space(4)

          Repeater {
            model: root.sourcePlayers

            BorderSurface {
              id: sourceRow
              required property var modelData

              readonly property var player: modelData
              readonly property bool selected: root.activePlayer && player
                && root.playerKey(root.activePlayer) === root.playerKey(player)
              readonly property string sourceTitle: player ? (player.trackTitle || player.identity || player.desktopEntry || "Media source") : "Media source"
              readonly property string sourceDetail: player && player.trackArtist ? player.trackArtist : (player && player.identity ? player.identity : "")

              width: sourceList.width
              height: sourceInner.implicitHeight + Style.space(10)
              radius: Style.spacing.labelGap
              color: selected ? Style.selectedFillFor(root.bar.foreground, Color.accent) : "transparent"
              borderSpec: selected ? Border.controlSpec("normal", root.bar.foreground, Color.accent) : Border.none()

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.selectPlayer(sourceRow.player)
              }

              Row {
                id: sourceInner
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: sourceRow.borderLeft + Style.space(4)
                anchors.rightMargin: sourceRow.borderRight + Style.space(4)
                spacing: Style.space(6)

                Button {
                  id: sourcePlayButton
                  anchors.verticalCenter: parent.verticalCenter
                  iconText: sourceRow.player && sourceRow.player.isPlaying ? "󰏤" : "󰐊"
                  foreground: root.bar.foreground
                  horizontalPadding: Style.spacing.controlPaddingY
                  verticalPadding: Style.spacing.controlPaddingY
                  tooltipText: sourceRow.player && sourceRow.player.isPlaying ? "Pause" : "Play"
                  onClicked: if (sourceRow.player) sourceRow.player.togglePlaying()
                }

                Column {
                  width: parent.width - sourcePlayButton.width - sourceFocusButton.width - parent.spacing * 2
                  spacing: Style.space(1)
                  anchors.verticalCenter: parent.verticalCenter

                  Text {
                    textFormat: Text.PlainText
                    text: sourceRow.sourceTitle
                    color: root.bar.foreground
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.bold: sourceRow.selected
                    elide: Text.ElideRight
                    width: parent.width
                  }

                  Text {
                    textFormat: Text.PlainText
                    text: sourceRow.sourceDetail
                    color: Color.muted
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                    width: parent.width
                    visible: text !== ""
                  }
                }

                Button {
                  id: sourceFocusButton
                  anchors.verticalCenter: parent.verticalCenter
                  iconText: "󰁔"
                  foreground: root.bar.foreground
                  horizontalPadding: Style.spacing.controlPaddingY
                  verticalPadding: Style.spacing.controlPaddingY
                  tooltipText: "Go to player"
                  onClicked: root.focusPlayer(sourceRow.player)
                }
              }
            }
          }
        }
      }
    }
    }
  }

  function parseReply(text) {
    var lines = String(text || "").trim().split("\n")
    try {
      return JSON.parse(lines[lines.length - 1])
    } catch (error) {
      return { ok: false, error: "no reply from cliamp" }
    }
  }

  // Stacked-segment spectrum bars.
  component DotSpectrum: Row {
    id: spectrum

    property var bands: []
    property int bandCount: 10
    property int rows: 5
    property real dotWidth: 3
    property real dotHeight: 2
    property real gap: 1
    property color litColor: "white"
    property color peakColor: "white"
    property color dimColor: "transparent"

    spacing: gap

    Repeater {
      model: spectrum.bandCount

      Column {
        id: band
        required property int index
        readonly property real level: Math.max(0, Math.min(1, Number(spectrum.bands[index]) || 0))
        readonly property int lit: Math.max(1, Math.ceil(level * spectrum.rows))
        spacing: spectrum.gap

        Repeater {
          model: spectrum.rows

          Rectangle {
            required property int index
            readonly property int fromBottom: spectrum.rows - 1 - index
            width: spectrum.dotWidth
            height: spectrum.dotHeight
            radius: Math.min(width, height) / 3
            color: fromBottom >= band.lit ? spectrum.dimColor
              : (fromBottom === band.lit - 1 && band.lit > 1 ? spectrum.peakColor : spectrum.litColor)
          }
        }
      }
    }
  }
}
