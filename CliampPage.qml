// cliamp source browser ("browse") and playlist picker ("lists"); loaded
// only while shown.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

Column {
  id: page

  // The Humline BarWidget, passed in by the Loader before bindings run.
  required property var widget

  readonly property bool browsing: page.widget.view === "browse"
  readonly property int pageSize: 8
  property var providers: []
  // browse: one server page; lists: every target, paged here.
  property var items: []
  property int total: 0
  property int offset: 0
  property bool loading: false
  property string error: ""
  property string pendingKey: ""
  property int requestId: 0
  // The track the picker acts on, fixed when it opens.
  property string trackPath: ""
  property string trackTitle: ""
  property bool spotifyLoaded: false

  readonly property var shown: browsing ? items : items.slice(offset, offset + pageSize)
  readonly property int count: browsing ? total : items.length
  readonly property bool spotifyTrack: trackPath.indexOf("spotify:") === 0
  readonly property string itemFont: page.widget.bar.fontFamily

  spacing: Style.space(8)

  function helper(args) { return ["python3", page.widget.cliampHelper].concat(args) }

  // Newest request wins; one that arrives while another runs waits for it.
  property var queuedArgs: null

  function request(args) {
    requestId++
    error = ""
    loading = true
    if (listProc.running) {
      queuedArgs = args
      return
    }
    start(args)
  }

  function start(args) {
    listProc.requestId = requestId
    listProc.kind = args[0]
    listProc.command = helper(args)
    listProc.running = true
  }

  function fetch() {
    if (browsing) {
      if (!page.widget.browseProvider) request(["providers"])
      else request(["playlists", page.widget.browseProvider, String(offset), String(pageSize)])
    } else if (trackPath) {
      request(["targets", trackPath])
    }
  }

  function received(r, kind) {
    loading = false
    if (!r.ok) {
      error = r.error || "cliamp error"
      return
    }
    if (r.providers) {
      providers = r.providers
      if (!page.widget.browseProvider && providers.length) page.widget.browseProvider = providers[0].key
      return
    }
    if (browsing) {
      items = r.items || []
      total = r.total || 0
    } else {
      var provider = kind === "sptargets" ? "spotify" : "local"
      var others = items.filter(function(i) { return i.provider !== provider })
      items = provider === "local" ? (r.items || []).concat(others) : others.concat(r.items || [])
      if (provider === "spotify") spotifyLoaded = true
    }
    if (!count) error = browsing ? "Nothing here" : (spotifyTrack && !spotifyLoaded ? "No local playlists yet" : "No playlists yet")
  }

  function showPage(newOffset) {
    offset = Math.max(0, newOffset)
    if (browsing) {
      items = []
      fetch()
    }
  }

  function loadSpotify() {
    if (listProc.running) return
    request(["sptargets"])
  }

  function activate(item) {
    var ctl = page.widget.cliamp
    if (!ctl || ctl.busy || loading) return
    var key = item.provider + "|" + item.id
    if (browsing) {
      pendingKey = key
      ctl.run(["load", page.widget.browseProvider, item.id], function(r) {
        page.pendingKey = ""
        if (!r.ok) return
        ctl.flash("Loading " + item.name + "…")
        page.widget.view = "main"
      })
      return
    }
    var removing = item.has === true
    if (removing && item.provider !== "local") return
    pendingKey = key
    var args = removing ? ["remove", item.id, trackPath] : ["add", item.provider, item.id, trackPath]
    ctl.run(args, function(r) {
      page.pendingKey = ""
      if (!r.ok) return
      page.items = page.items.map(function(i) {
        return i.provider === item.provider && i.id === item.id
          ? Object.assign({}, i, { has: item.provider === "local" ? !removing : true }) : i
      })
      ctl.flash((removing ? "Removed from " : "Added to ") + item.name)
    })
  }

  function snapshotTrack() {
    if (trackPath || !page.widget.cliamp || !page.widget.cliamp.path) return
    trackPath = page.widget.cliamp.path
    trackTitle = page.widget.title
    fetch()
  }

  onBrowsingChanged: {
    items = []
    total = 0
    offset = 0
    if (browsing) {
      if (!providers.length) providersProc.running = true
      fetch()
    } else {
      snapshotTrack()
    }
  }

  Component.onCompleted: {
    if (browsing) {
      if (page.widget.browseProvider) providersProc.running = true
      fetch()
    } else {
      snapshotTrack()
    }
    keyCatcher.forceActiveFocus()
  }
  Component.onDestruction: if (page.widget.cliamp) page.widget.cliamp.detach()

  Connections {
    target: page.widget
    function onBrowseProviderChanged() {
      if (!page.browsing) return
      page.total = 0
      page.showPage(0)
    }
  }
  // Opened via IPC before the first state reply: wait for cliamp's path.
  Connections {
    target: page.widget.cliamp
    ignoreUnknownSignals: true
    function onPathChanged() { if (!page.browsing) page.snapshotTrack() }
  }

  Process {
    id: listProc
    property int requestId: 0
    property string kind: ""
    stdout: StdioCollector {
      onStreamFinished: if (listProc.requestId === page.requestId && !page.queuedArgs)
        page.received(page.widget.parseReply(text), listProc.kind)
    }
    onExited: if (page.queuedArgs) {
      var args = page.queuedArgs
      page.queuedArgs = null
      Qt.callLater(function() { page.start(args) })
    }
  }

  // Tabs need the provider list even when a provider is remembered.
  Process {
    id: providersProc
    command: page.helper(["providers"])
    stdout: StdioCollector {
      onStreamFinished: {
        var r = page.widget.parseReply(text)
        if (r.ok) page.providers = r.providers || []
      }
    }
  }

  // Esc goes back to the card; arrows page through the list.
  Item {
    id: keyCatcher
    width: 0
    height: 0
    focus: true
    Keys.onEscapePressed: page.widget.view = "main"
    Keys.onLeftPressed: if (page.offset > 0) page.showPage(page.offset - page.pageSize)
    Keys.onRightPressed: if (page.offset + page.pageSize < page.count) page.showPage(page.offset + page.pageSize)
  }

  Row {
    width: parent.width
    spacing: Style.space(6)

    Button {
      id: backButton
      anchors.verticalCenter: parent.verticalCenter
      iconText: "󰁍"
      foreground: page.widget.bar.foreground
      horizontalPadding: Style.spacing.controlPaddingY
      verticalPadding: Style.spacing.controlPaddingY
      tooltipText: "Back (Esc)"
      onClicked: page.widget.view = "main"
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width - backButton.width - parent.spacing
      textFormat: Text.PlainText
      text: page.browsing ? "Browse cliamp" : "Add “" + (page.trackTitle || page.widget.title) + "” to…"
      color: page.widget.bar.foreground
      font.family: page.itemFont
      font.pixelSize: Style.font.body
      font.bold: true
      elide: Text.ElideRight
    }
  }

  Flow {
    visible: page.browsing && page.providers.length > 1
    width: parent.width
    spacing: Style.space(4)

    Repeater {
      model: page.providers

      Button {
        required property var modelData
        text: modelData.name
        fontSize: Style.font.bodySmall
        foreground: page.widget.bar.foreground
        selected: page.widget.browseProvider === modelData.key
        opacity: selected ? 1.0 : 0.7
        horizontalPadding: Style.spacing.controlPaddingX
        verticalPadding: Style.spacing.controlPaddingY
        onClicked: page.widget.browseProvider = modelData.key
      }
    }
  }

  Column {
    id: rows
    width: parent.width
    spacing: Style.space(1)

    Repeater {
      model: page.shown

      BorderSurface {
        id: row
        required property var modelData
        readonly property bool pending: page.pendingKey === modelData.provider + "|" + modelData.id
        readonly property bool locked: !page.browsing && modelData.has === true && modelData.provider !== "local"

        width: rows.width
        height: rowText.implicitHeight + Style.space(8)
        radius: Style.spacing.labelGap
        color: rowMouse.containsMouse && !locked ? Style.hoverFillFor(page.widget.bar.foreground, Color.accent) : "transparent"
        borderSpec: Border.none()

        MouseArea {
          id: rowMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: row.locked ? Qt.ArrowCursor : Qt.PointingHandCursor
          onClicked: page.activate(row.modelData)
        }

        Text {
          id: rowText
          anchors.left: parent.left
          anchors.right: rowDetail.left
          anchors.leftMargin: Style.space(6)
          anchors.rightMargin: Style.space(6)
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: row.modelData.name || row.modelData.id
          color: page.widget.bar.foreground
          font.family: page.itemFont
          font.pixelSize: Style.font.bodySmall
          elide: Text.ElideRight
        }

        Text {
          id: rowDetail
          anchors.right: parent.right
          anchors.rightMargin: Style.space(6)
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: row.pending ? "…"
            : page.browsing ? (row.modelData.count > 0 ? String(row.modelData.count) : "")
            : (row.modelData.has === true ? "󰄬" : (row.modelData.provider === "spotify" ? "Spotify" : "Local"))
          color: !page.browsing && row.modelData.has === true ? Color.accent : Qt.darker(page.widget.bar.foreground, 1.5)
          font.family: page.itemFont
          font.pixelSize: !page.browsing && row.modelData.has === true ? Style.font.body : Style.font.caption
        }
      }
    }
  }

  Button {
    visible: !page.browsing && page.spotifyTrack && !page.spotifyLoaded && !page.loading
    anchors.horizontalCenter: parent.horizontalCenter
    iconText: "󰓇"
    text: "Your Spotify playlists"
    fontSize: Style.font.bodySmall
    foreground: page.widget.bar.foreground
    horizontalPadding: Style.spacing.controlPaddingX
    verticalPadding: Style.spacing.controlPaddingY
    onClicked: page.loadSpotify()
  }

  Text {
    visible: text !== ""
    width: parent.width
    horizontalAlignment: Text.AlignHCenter
    wrapMode: Text.WordWrap
    textFormat: Text.PlainText
    text: page.loading
      ? ((page.browsing && page.widget.browseProvider === "spotify") || (!page.browsing && page.spotifyTrack && !page.spotifyLoaded && page.items.length)
          ? "Loading from Spotify… the first time can take a few seconds and cliamp pauses meanwhile."
          : "Loading…")
      : (page.widget.cliamp && page.widget.cliamp.message ? page.widget.cliamp.message : page.error)
    color: Qt.darker(page.widget.bar.foreground, 1.4)
    font.family: page.itemFont
    font.pixelSize: Style.font.caption
  }

  Row {
    visible: page.count > page.pageSize
    anchors.horizontalCenter: parent.horizontalCenter
    spacing: Style.space(6)

    Button {
      anchors.verticalCenter: parent.verticalCenter
      iconText: "󰅁"
      foreground: page.widget.bar.foreground
      horizontalPadding: Style.spacing.controlPaddingY
      verticalPadding: Style.spacing.controlPaddingY
      enabled: page.offset > 0 && !page.loading
      opacity: enabled ? 1.0 : 0.4
      onClicked: page.showPage(page.offset - page.pageSize)
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: (page.offset + 1) + "–" + Math.min(page.count, page.offset + page.pageSize) + " of " + page.count
      color: Qt.darker(page.widget.bar.foreground, 1.3)
      font.family: page.itemFont
      font.pixelSize: Style.font.caption
    }

    Button {
      anchors.verticalCenter: parent.verticalCenter
      iconText: "󰅂"
      foreground: page.widget.bar.foreground
      horizontalPadding: Style.spacing.controlPaddingY
      verticalPadding: Style.spacing.controlPaddingY
      enabled: page.offset + page.pageSize < page.count && !page.loading
      opacity: enabled ? 1.0 : 0.4
      onClicked: page.showPage(page.offset + page.pageSize)
    }
  }
}
