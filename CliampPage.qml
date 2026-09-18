// cliamp source browser ("browse") and playlist picker ("lists"); loaded
// only while shown.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

Column {
  id: page

  // The nowpip BarWidget, passed in by the Loader before bindings run.
  required property var widget

  readonly property bool browsing: widget.view === "browse"
  readonly property int pageSize: 20
  property var providers: []
  property var items: []
  property int total: 0
  property int offset: 0
  property bool loading: false
  property bool refetch: false
  property string error: ""
  property string pendingId: ""

  spacing: Style.space(8)

  function fetch() {
    if (listProc.running) {
      refetch = true
      return
    }
    error = ""
    loading = true
    if (browsing && !widget.browseProvider) {
      listProc.command = ["bash", widget.cliampHelper, "providers"]
    } else if (browsing) {
      listProc.command = ["bash", widget.cliampHelper, "playlists", widget.browseProvider, String(offset), String(pageSize)]
    } else {
      if (!widget.cliampPath) {
        loading = false
        error = "No track to add"
        return
      }
      listProc.command = ["bash", widget.cliampHelper, "targets", widget.cliampPath, String(offset), String(pageSize)]
    }
    listProc.running = true
  }

  function received(r) {
    loading = false
    if (!r.ok) {
      error = r.error || "cliamp error"
      return
    }
    if (r.providers) {
      providers = r.providers
      if (!widget.browseProvider && providers.length) widget.browseProvider = providers[0].key
      return
    }
    items = r.items || []
    total = r.total || 0
    if (!items.length) error = browsing ? "Nothing here" : "No playlists yet"
  }

  function showPage(newOffset) {
    offset = Math.max(0, newOffset)
    items = []
    fetch()
  }

  function activate(item) {
    if (!widget.cliamp || widget.cliamp.busy) return
    pendingId = item.provider + ":" + item.id
    if (browsing) {
      widget.cliamp.run(["load", widget.browseProvider, item.id], function(r) {
        page.pendingId = ""
        if (r.ok) widget.view = "main"
      })
      return
    }
    var removing = item.has === true && item.provider === "local"
    if (item.has === true && !removing) {
      pendingId = ""
      return
    }
    var args = removing ? ["remove", item.id, widget.cliampPath] : ["add", item.provider, item.id, widget.cliampPath]
    widget.cliamp.run(args, function(r) {
      page.pendingId = ""
      if (!r.ok) return
      var copy = page.items.slice()
      for (var i = 0; i < copy.length; i++) {
        if (copy[i].provider === item.provider && copy[i].id === item.id)
          copy[i] = Object.assign({}, copy[i], { has: !removing })
      }
      page.items = copy
      widget.cliamp.flash((removing ? "Removed from " : "Added to ") + item.name)
    })
  }

  onBrowsingChanged: {
    if (browsing && widget.browseProvider && !providers.length) providersProc.running = true
    total = 0
    showPage(0)
  }
  Component.onCompleted: {
    if (browsing && widget.browseProvider) providersProc.running = true
    fetch()
  }

  Connections {
    target: widget
    function onBrowseProviderChanged() {
      if (!page.browsing) return
      page.total = 0
      page.showPage(0)
    }
  }

  Process {
    id: listProc
    stdout: StdioCollector {
      onStreamFinished: page.received(widget.parseReply(text))
    }
    onExited: if (page.refetch) {
      page.refetch = false
      Qt.callLater(page.fetch)
    }
  }

  // Tabs need the provider list even when a provider is remembered.
  Process {
    id: providersProc
    command: ["bash", widget.cliampHelper, "providers"]
    stdout: StdioCollector {
      onStreamFinished: {
        var r = widget.parseReply(text)
        if (r.ok) page.providers = r.providers || []
      }
    }
  }

  Row {
    width: parent.width
    spacing: Style.space(6)

    Button {
      id: backButton
      anchors.verticalCenter: parent.verticalCenter
      iconText: "󰁍"
      foreground: widget.bar.foreground
      horizontalPadding: Style.spacing.controlPaddingY
      verticalPadding: Style.spacing.controlPaddingY
      tooltipText: "Back"
      onClicked: widget.view = "main"
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width - backButton.width - parent.spacing
      textFormat: Text.PlainText
      text: page.browsing ? "Browse cliamp" : "Add “" + widget.title + "” to…"
      color: widget.bar.foreground
      font.family: widget.bar.fontFamily
      font.pixelSize: Style.font.body
      font.bold: true
      elide: Text.ElideRight
    }
  }

  ButtonGroup {
    visible: page.browsing && page.providers.length > 1
    focusable: false
    spacing: Style.space(6)
    options: page.providers.map(function(p) { return { value: p.key, label: p.name } })
    value: widget.browseProvider
    foreground: widget.bar.foreground
    background: "transparent"
    fontFamily: widget.bar.fontFamily
    fontSize: Style.font.bodySmall
    onChanged: function(v) { widget.browseProvider = v }
  }

  Column {
    id: rows
    width: parent.width
    spacing: Style.space(1)

    Repeater {
      model: page.items

      BorderSurface {
        id: row
        required property var modelData
        readonly property bool pending: page.pendingId === modelData.provider + ":" + modelData.id
        readonly property bool locked: !page.browsing && modelData.has === true && modelData.provider !== "local"

        width: rows.width
        height: rowText.implicitHeight + Style.space(8)
        radius: Style.spacing.labelGap
        color: rowMouse.containsMouse && !locked ? Style.hoverFillFor(widget.bar.foreground, Color.accent) : "transparent"
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
          color: widget.bar.foreground
          font.family: widget.bar.fontFamily
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
          color: !page.browsing && row.modelData.has === true ? Color.accent : Qt.darker(widget.bar.foreground, 1.5)
          font.family: widget.bar.fontFamily
          font.pixelSize: !page.browsing && row.modelData.has === true ? Style.font.body : Style.font.caption
        }
      }
    }
  }

  Text {
    visible: text !== ""
    width: parent.width
    horizontalAlignment: Text.AlignHCenter
    textFormat: Text.PlainText
    text: page.loading ? "Loading…" : (widget.cliamp && widget.cliamp.message ? widget.cliamp.message : page.error)
    color: Qt.darker(widget.bar.foreground, 1.4)
    font.family: widget.bar.fontFamily
    font.pixelSize: Style.font.caption
    elide: Text.ElideRight
  }

  Row {
    visible: page.total > page.pageSize
    anchors.horizontalCenter: parent.horizontalCenter
    spacing: Style.space(6)

    Button {
      anchors.verticalCenter: parent.verticalCenter
      iconText: "󰅁"
      foreground: widget.bar.foreground
      horizontalPadding: Style.spacing.controlPaddingY
      verticalPadding: Style.spacing.controlPaddingY
      enabled: page.offset > 0 && !page.loading
      opacity: enabled ? 1.0 : 0.4
      onClicked: page.showPage(page.offset - page.pageSize)
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: (page.offset + 1) + "–" + Math.min(page.total, page.offset + page.pageSize) + " of " + page.total
      color: Qt.darker(widget.bar.foreground, 1.3)
      font.family: widget.bar.fontFamily
      font.pixelSize: Style.font.caption
    }

    Button {
      anchors.verticalCenter: parent.verticalCenter
      iconText: "󰅂"
      foreground: widget.bar.foreground
      horizontalPadding: Style.spacing.controlPaddingY
      verticalPadding: Style.spacing.controlPaddingY
      enabled: page.offset + page.pageSize < page.total && !page.loading
      opacity: enabled ? 1.0 : 0.4
      onClicked: page.showPage(page.offset + page.pageSize)
    }
  }
}
