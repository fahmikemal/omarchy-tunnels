import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model
import "Demo.js" as Demo

// Every VPN on the machine behind one bar icon. A VPN gets a tab only when its
// CLI is installed; with none installed the icon leaves the bar entirely.
Panel {
  id: vpn
  moduleName: "io.github.fahmikemal.tunnels"
  ipcTarget: "io.github.fahmikemal.tunnels"
  manageIpc: false

  // ------------------------------------------------------------------ theme
  //
  // The popup draws with the theme's popup tokens, and every secondary shade
  // is an alpha of the text color rather than a darker or lighter hue, so the
  // contrast holds on light, dark, and translucent themes alike. Sizes come
  // from Style, so font and spacing scales carry through too.

  readonly property color fg: Commons.Color.popups.text
  readonly property color dim: tint(fg, 0.68)
  readonly property color faint: tint(fg, 0.4)
  readonly property color accent: Commons.Color.accent
  readonly property color urgent: Commons.Color.urgent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  function tint(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

  // -------------------------------------------------------------- providers

  readonly property var all: [tailscale, netbird, zerotier]
  // Sample data in place of the real CLIs; used for screenshots.
  readonly property bool demo: setting("demo", false) === true
  readonly property var providers: all.filter(function(p) { return p.installed && vpn.enabledFor(p.providerId) })

  // The selection follows the VPN, not its slot, so a VPN appearing or
  // vanishing never swaps out the tab you are reading.
  property string selectedId: String(setting("defaultTab", ""))
  readonly property int providerIndex: {
    for (var i = 0; i < providers.length; i++)
      if (providers[i].providerId === selectedId) return i
    return 0
  }
  readonly property var provider: providers.length > 0 ? providers[providerIndex] : null
  readonly property int connectedCount: providers.filter(function(p) { return p.connected }).length

  function providerSettings(id) {
    var value = setting(id, {})
    return value && typeof value === "object" ? value : {}
  }

  function enabledFor(id) { return providerSettings(id).enabled !== false }

  function select(index) {
    if (providers.length === 0) return
    var wrapped = ((index % providers.length) + providers.length) % providers.length
    selectedId = providers[wrapped].providerId
    cursor = -1
    query = ""
    armedKey = ""
    serversOpen = false
    closeServerForm()
    pointerGate.reset()
    flick.contentY = 0
  }

  // ------------------------------------------------------------------- list
  //
  // The tab body is one flat list the keyboard cursor walks top to bottom:
  // the server switcher (and, opened, its servers) above the filter, then
  // this device's addresses and each section's rows below it.

  property string query: ""
  property int cursor: -1
  property string armedKey: ""
  property bool serversOpen: false
  property bool formOpen: false
  property int presetIndex: 0

  readonly property int rowTotal: {
    if (!provider) return 0
    var n = 0
    var sections = provider.snapshot.sections
    for (var i = 0; i < sections.length; i++) n += sections[i].rows.length
    return n
  }
  readonly property bool searchable: rowTotal > 8
  readonly property var topItems: buildTop(provider, serversOpen)
  readonly property var listItems: buildItems(provider, searchable ? query : "", countSelectable(topItems))
  readonly property var items: topItems.concat(listItems)
  readonly property int selectableCount: countSelectable(items)

  function countSelectable(list) {
    var n = 0
    for (var i = 0; i < list.length; i++) if (list[i].sel >= 0) n++
    return n
  }

  function matches(row, needle) {
    if (needle === "") return true
    return (row.name + " " + row.detail + " " + row.address).toLowerCase().indexOf(needle) >= 0
  }

  // The active server, then — when opened — every server and the add row.
  function buildTop(p, open) {
    var out = []
    if (!p || (p.servers.length === 0 && !p.serverForm)) return out
    var sel = 0
    var active = null
    for (var i = 0; i < p.servers.length; i++) if (p.servers[i].online && !active) active = p.servers[i]
    out.push({
      kind: "serverToggle",
      key: "server-toggle",
      label: p.serversLabel,
      title: active ? active.name : "None",
      detail: active ? active.detail : "Add one below",
      count: p.servers.length,
      sel: sel++
    })
    if (!open) return out
    // Roots that are all in use at once (ZeroTier) are not something to switch.
    var switchable = p.servers.length > 1 && p.providerId !== "zerotier"
    for (var s = 0; s < p.servers.length; s++) {
      var server = p.servers[s]
      var switchTo = switchable && !server.online
      out.push({
        kind: "row",
        server: true,
        key: "s-" + server.key,
        row: server,
        glyph: switchTo ? "󰁔" : (server.address !== "" ? "󰆏" : ""),
        tip: switchTo ? "Switch to " + server.name : (server.address !== "" ? "Copy " + server.address : ""),
        sel: sel++
      })
    }
    if (p.serverForm) out.push({ kind: "addServer", key: "add-server", title: p.serverForm.title, sel: sel++ })
    return out
  }

  function buildItems(p, filter, first) {
    var out = []
    if (!p) return out
    var snap = p.snapshot
    var needle = String(filter || "").trim().toLowerCase()
    var sel = first || 0

    if (snap.addresses.length > 0 && needle === "") {
      out.push({ kind: "header", key: "h-self", title: "This device", meta: "", sel: -1 })
      for (var a = 0; a < snap.addresses.length; a++) {
        var address = snap.addresses[a]
        out.push({ kind: "address", key: "a-" + a, label: address.label, value: address.value, sel: sel++ })
      }
    }

    for (var s = 0; s < snap.sections.length; s++) {
      var section = snap.sections[s]
      var online = 0
      for (var c = 0; c < section.rows.length; c++) if (section.rows[c].online) online++
      out.push({
        kind: "header",
        key: "h-" + section.title,
        title: section.title,
        meta: section.rows.length > 0 ? online + " of " + section.rows.length + " online" : "",
        sel: -1
      })
      var shown = 0
      for (var r = 0; r < section.rows.length; r++) {
        var row = section.rows[r]
        if (!matches(row, needle)) continue
        out.push({
          kind: "row",
          server: false,
          key: "r-" + section.title + "-" + row.key,
          row: row,
          glyph: row.address !== "" ? "󰆏" : "",
          tip: row.address !== "" ? "Copy " + row.address : "",
          sel: sel++
        })
        shown++
      }
      if (shown === 0)
        out.push({ kind: "empty", key: "e-" + section.title, text: needle !== "" ? "No match" : "Nothing here yet", sel: -1 })
    }
    return out
  }

  function itemAt(sel) {
    for (var i = 0; i < items.length; i++) if (items[i].sel === sel) return items[i]
    return null
  }

  function moveCursor(dy) {
    if (selectableCount === 0) return
    pointerGate.reset()
    cursor = cursor < 0 ? (dy > 0 ? 0 : selectableCount - 1)
      : Math.max(0, Math.min(selectableCount - 1, cursor + dy))
    Qt.callLater(ensureCursorVisible)
  }

  // Only the list scrolls; the server rows above it are always in view.
  function ensureCursorVisible() {
    for (var i = 0; i < listRepeater.count; i++) {
      var holder = listRepeater.itemAt(i)
      if (!holder || holder.entry.sel !== cursor) continue
      var y = holder.mapToItem(list, 0, 0).y
      if (y < flick.contentY) flick.contentY = Math.max(0, y - Style.spacing.lg)
      else if (y + holder.height > flick.contentY + flick.height)
        flick.contentY = Math.min(flick.contentHeight - flick.height, y + holder.height - flick.height + Style.spacing.lg)
      return
    }
  }

  function activate(entry) {
    if (!entry || !provider) return
    if (entry.kind === "address") copy(entry.value)
    else if (entry.kind === "serverToggle") {
      pointerGate.reset()
      serversOpen = !serversOpen
      if (!serversOpen) closeServerForm()
    } else if (entry.kind === "addServer") openServerForm()
    else if (entry.kind === "row" && entry.server && entry.glyph === "󰁔") switchServer(entry)
    else if (entry.kind === "row") copy(entry.row.address)
  }

  function copy(text) {
    var value = String(text || "")
    if (value === "" || !provider) return
    Quickshell.execDetached(["wl-copy", "--", value])
    provider.flash("Copied " + value, false)
  }

  // Anything that drops a connection or deletes something takes two presses.
  function confirmed(key, prompt) {
    if (armedKey === key) {
      armedKey = ""
      return true
    }
    armedKey = key
    armTimer.restart()
    provider.flash(prompt, false)
    return false
  }

  function switchServer(entry) {
    var current = topItems.length > 0 ? topItems[0].title : ""
    var prompt = "Press again to switch to " + entry.row.name + (provider.connected ? " (drops " + current + ")" : "")
    if (confirmed(entry.key + "#switch", prompt)) provider.switchServer(entry.row)
  }

  function rowAction(entry) {
    if (!entry || entry.kind !== "row" || !entry.row.action || !provider) return
    if (!confirmed(entry.key, "Press again to " + entry.row.action.label.toLowerCase())) return
    if (entry.server) provider.removeServer(entry.row)
    else provider.rowAction(entry.row, entry.row.action.id)
  }

  // ------------------------------------------------------------ server form

  readonly property var form: provider ? provider.serverForm : null
  readonly property var preset: form && form.presets.length > 0 ? form.presets[Math.min(presetIndex, form.presets.length - 1)] : null
  // A preset with its own URL needs no URL typed in.
  readonly property bool needsSecond: !preset || preset.url === ""
  readonly property bool formValid: !!form
    && (!form.firstRequired || firstField.text.trim() !== "")
    && (!needsSecond || !form.secondRequired || secondField.text.trim() !== "")

  function openServerForm() {
    if (!form) return
    serversOpen = true
    formOpen = true
    presetIndex = form.presets.length > 1 ? form.presets.length - 1 : 0
    Qt.callLater(function() { firstField.forceActiveFocus() })
  }

  function closeServerForm() {
    formOpen = false
    firstField.text = ""
    secondField.text = ""
    keyCatcher.forceActiveFocus()
  }

  function submitServerForm() {
    if (!formValid || !provider) return
    var error = provider.addServer(firstField.text, needsSecond ? secondField.text : preset.url)
    if (error !== "") {
      provider.flash(error, true)
      return
    }
    closeServerForm()
  }

  // Rows slide when a list opens or a poll lands; a pointer resting on the
  // panel must not take the keyboard cursor with them. Hover moves the
  // cursor only once the pointer itself moves.
  PointerMoveGate {
    id: pointerGate
    referenceItem: keyCatcher
  }

  Timer {
    id: armTimer
    interval: 3500
    onTriggered: vpn.armedKey = ""
  }

  // ----------------------------------------------------------------- notice

  readonly property var notice: noticeFor(provider)

  function noticeFor(p) {
    if (!p) return null
    var error = p.snapshot.error
    if (p.setupText !== "") return { text: p.setupText, label: p.setupLabel, act: "setup", alarm: true }
    switch (p.vpnState) {
    case "daemon-down":
      return { text: p.name + "'s service isn't running.", label: "Start service", act: "service", alarm: false }
    case "needs-login":
      if (p.loginActive)
        return { text: "Finish signing in to " + p.name + " in your browser.", label: p.loginUrl !== "" ? "Open again" : "Cancel",
                 act: p.loginUrl !== "" ? "reopen" : "cancel", alarm: false }
      return { text: (error !== "" ? error.charAt(0).toUpperCase() + error.slice(1) + ". " : "") + "Sign in to connect this device.",
               label: "Sign in", act: "login", alarm: true }
    case "needs-approval":
      return { text: "This device is waiting for approval in the admin console.", label: p.adminUrl !== "" ? "Open console" : "",
               act: "admin", alarm: true }
    case "error":
      return { text: error !== "" ? error : p.name + " did not answer.", label: "Retry", act: "refresh", alarm: true }
    }
    return null
  }

  function runNotice(act) {
    var p = provider
    if (!p) return
    if (act === "setup") p.setup()
    else if (act === "service") p.startService()
    else if (act === "login") p.login()
    else if (act === "reopen") p.openUrl(p.loginUrl)
    else if (act === "cancel") p.cancelLogin()
    else if (act === "admin") p.openUrl(p.adminUrl)
    else if (act === "refresh") p.refresh()
  }

  // -------------------------------------------------------------- bar icon

  function tooltip() {
    var lines = []
    for (var i = 0; i < providers.length; i++) {
      var p = providers[i]
      lines.push(p.name + ": " + p.statusLine())
    }
    return lines.join("\n")
  }

  visible: providers.length > 0
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: vpn.bar
    iconComponent: Component {
      Item {
        TunnelsMark {
          anchors.centerIn: parent
          size: Style.bar.iconCanvas
          color: button.foreground
        }
      }
    }
    // Dims by alpha, not by darkening, so the cue survives light bars.
    foreground: vpn.connectedCount > 0 ? vpn.barForeground : vpn.tint(vpn.barForeground, 0.45)
    tooltipText: vpn.tooltip()
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.MiddleButton) vpn.select(vpn.providerIndex + 1)
      else if (buttonCode === Qt.RightButton) vpn.refreshAll()
      else vpn.toggle()
    }
  }

  function refreshAll() {
    for (var i = 0; i < providers.length; i++) providers[i].refresh()
  }

  // ------------------------------------------------------------------- IPC

  IpcHandler {
    target: vpn.ipcTarget
    function open(): void { vpn.open() }
    function close(): void { vpn.close() }
    function show(): void { vpn.open() }
    function hide(): void { vpn.close() }
    function toggle(): void { vpn.toggle() }
    function refresh(): string { vpn.refreshAll(); return "ok" }
    function next(): string { vpn.select(vpn.providerIndex + 1); return "ok" }
    function previous(): string { vpn.select(vpn.providerIndex - 1); return "ok" }
    function select(id: string): string {
      for (var i = 0; i < vpn.providers.length; i++) {
        if (vpn.providers[i].providerId === id) {
          vpn.select(i)
          return "ok"
        }
      }
      return "not installed: " + id
    }
    function status(): string { return vpn.tooltip() }
  }

  // ------------------------------------------------------------- providers

  TailscaleProvider {
    id: tailscale
    settings: vpn.providerSettings("tailscale")
    fixture: vpn.demo ? Demo.tailscale : null
    watching: vpn.opened && vpn.provider === tailscale
  }

  NetbirdProvider {
    id: netbird
    settings: vpn.providerSettings("netbird")
    fixture: vpn.demo ? Demo.netbird : null
    watching: vpn.opened && vpn.provider === netbird
  }

  ZerotierProvider {
    id: zerotier
    settings: vpn.providerSettings("zerotier")
    fixture: vpn.demo ? Demo.zerotier : null
    watching: vpn.opened && vpn.provider === zerotier
  }

  onOpenedChanged: if (opened) {
    pointerGate.reset()
    cursor = -1
    armedKey = ""
    serversOpen = false
    closeServerForm()
    flick.contentY = 0
  }

  // ----------------------------------------------------------------- popup

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: vpn
    bar: vpn.bar
    open: vpn.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(Number(vpn.setting("panelWidth", 400)) || 400))
    contentHeight: panel.fittedContentHeight(
      topArea.implicitHeight
        + (vpn.listItems.length > 0 ? Style.spacing.xxl + list.implicitHeight : 0)
        + (joinRow.visible ? joinRow.height + Style.spacing.lg : 0)
        + Style.spacing.lg + footer.height,
      // Room for the list even with the server form open.
      Math.max(Style.space(640), topArea.implicitHeight + footer.height + Style.space(180)))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: searchField.activeFocus || joinField.activeFocus || firstField.activeFocus || secondField.activeFocus

      onMoveRequested: function(dx, dy) {
        if (dx !== 0) vpn.select(vpn.providerIndex + dx)
        if (dy !== 0) vpn.moveCursor(dy)
      }
      onActivateRequested: vpn.activate(vpn.itemAt(vpn.cursor))
      onDeleteRequested: vpn.rowAction(vpn.itemAt(vpn.cursor))
      onCloseRequested: vpn.close()
      onTabRequested: function(direction) { vpn.switchPanel(direction) }
      onTextKey: function(t) {
        var key = t.toLowerCase()
        if (!vpn.provider) return
        if (key === "t") vpn.provider.toggle()
        else if (key === "r") vpn.provider.refresh()
        else if (key === "o" && vpn.provider.adminUrl !== "") vpn.provider.openUrl(vpn.provider.adminUrl)
        else if (key === "/" && vpn.searchable) searchField.forceActiveFocus()
        else if (/^[1-9]$/.test(key) && Number(key) <= vpn.providers.length) vpn.select(Number(key) - 1)
      }

      // Everything above the list stays put; only the list scrolls.
      Column {
        id: topArea
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Style.spacing.xxl

        // ---------- Tabs: one per installed VPN ----------
        Row {
          id: tabRow
          visible: vpn.providers.length > 1
          width: parent.width
          spacing: Style.spacing.md

          readonly property real cell: vpn.providers.length > 0
            ? (width - spacing * (vpn.providers.length - 1)) / vpn.providers.length
            : 0

          Repeater {
            model: vpn.providers

            CursorSurface {
              id: chip
              required property var modelData
              required property int index

              readonly property bool selected: index === vpn.providerIndex
              readonly property real pip: Style.space(6)
              // Narrow panels keep the mark and status, and drop the name.
              readonly property bool roomy: tabRow.cell >= chipMark.width + chipLabel.implicitWidth + pip
                + chipContent.spacing * 2 + Style.spacing.controlPaddingX * 2

              width: tabRow.cell
              height: Math.max(Style.spacing.controlHeight, chipContent.implicitHeight + Style.spacing.controlPaddingY * 2)
              current: selected
              hasCursor: chipMouse.containsMouse
              bordered: true
              foreground: vpn.fg

              Row {
                id: chipContent
                anchors.centerIn: parent
                spacing: Style.spacing.md

                VpnMark {
                  id: chipMark
                  anchors.verticalCenter: parent.verticalCenter
                  providerId: chip.modelData.providerId
                  size: Style.font.icon
                  color: vpn.fg
                  fontFamily: vpn.fontFamily
                  opacity: chip.modelData.connected || chip.selected ? 1 : 0.55
                }

                Text {
                  id: chipLabel
                  visible: chip.roomy
                  anchors.verticalCenter: parent.verticalCenter
                  text: chip.modelData.name
                  color: chip.selected ? vpn.fg : vpn.dim
                  font.family: vpn.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.bold: chip.selected
                  textFormat: Text.PlainText
                }

                // Filled = connected, ringed = off, urgent = needs you.
                Rectangle {
                  anchors.verticalCenter: parent.verticalCenter
                  width: chip.pip
                  height: chip.pip
                  radius: width / 2
                  color: chip.modelData.attention ? vpn.urgent : (chip.modelData.connected ? vpn.accent : "transparent")
                  border.width: Math.max(1, Style.spacing.hairline)
                  border.color: chip.modelData.attention ? vpn.urgent : (chip.modelData.connected ? vpn.accent : vpn.faint)
                }
              }

              MouseArea {
                id: chipMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: vpn.select(chip.index)
              }

              PanelToolTip {
                visible: chipMouse.containsMouse
                text: chip.modelData.name + " — " + chip.modelData.statusLine()
                fontFamily: vpn.fontFamily
              }
            }
          }
        }

        // ---------- Hero: mark · device · state · switch ----------
        PanelHero {
          id: hero
          visible: !!vpn.provider
          width: parent.width
          title: vpn.provider ? (vpn.provider.snapshot.selfName || vpn.provider.name) : ""
          meta: vpn.provider ? vpn.provider.statusLine() : ""
          foreground: vpn.fg
          fontFamily: vpn.fontFamily
          iconOpacity: vpn.provider && vpn.provider.connected ? 1 : 0.5

          iconComponent: Component {
            VpnMark {
              providerId: vpn.provider ? vpn.provider.providerId : ""
              size: Style.font.display
              color: vpn.fg
              fontFamily: vpn.fontFamily
            }
          }

          trailingControl: Component {
            ToggleSwitch {
              visible: !!vpn.provider && vpn.provider.vpnState !== "checking"
              checked: !!vpn.provider && vpn.provider.switchOn
              busy: !!vpn.provider && vpn.provider.busy
              foreground: vpn.fg
              onToggled: if (vpn.provider) vpn.provider.toggle()
            }
          }
        }

        // ---------- Notice: whatever needs the user ----------
        BorderSurface {
          id: noticeCard
          visible: !!vpn.notice
          width: parent.width
          implicitHeight: noticeContent.implicitHeight + Style.spacing.xl * 2
          radius: Style.cornerRadius
          color: vpn.notice && vpn.notice.alarm ? vpn.tint(vpn.urgent, 0.1) : Style.normalFillFor(vpn.fg, vpn.accent)
          borderSpec: Border.flat(vpn.notice && vpn.notice.alarm ? vpn.tint(vpn.urgent, 0.4) : vpn.tint(vpn.fg, 0.18),
                                  Math.max(1, Style.normalBorderWidth))

          Column {
            id: noticeContent
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Style.spacing.xxl
            anchors.rightMargin: Style.spacing.xxl
            spacing: Style.spacing.lg

            Text {
              width: parent.width
              text: vpn.notice ? vpn.notice.text : ""
              color: vpn.fg
              font.family: vpn.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.Wrap
              textFormat: Text.PlainText
            }

            Button {
              visible: !!vpn.notice && vpn.notice.label !== ""
              text: vpn.notice ? vpn.notice.label : ""
              bordered: true
              foreground: vpn.fg
              fontFamily: vpn.fontFamily
              fontSize: Style.font.bodySmall
              enabled: !!vpn.provider && !vpn.provider.busy || (vpn.notice && (vpn.notice.act === "cancel" || vpn.notice.act === "reopen"))
              onClicked: vpn.runNotice(vpn.notice.act)
            }
          }
        }

        // ---------- Server: which control plane this VPN uses ----------
        Column {
          id: serverBlock
          visible: vpn.topItems.length > 0
          width: parent.width
          spacing: Style.spacing.xs

          Repeater {
            id: topRepeater
            model: vpn.topItems
            delegate: listDelegate
          }

          // Outside the repeater on purpose: a poll that rebuilds the rows
          // must not wipe what is being typed.
          BorderSurface {
            id: serverFormCard
            visible: vpn.formOpen && !!vpn.form
            width: parent.width
            implicitHeight: formColumn.implicitHeight + Style.spacing.xl * 2
            radius: Style.cornerRadius
            color: Style.normalFillFor(vpn.fg, vpn.accent)
            borderSpec: Border.flat(vpn.tint(vpn.fg, 0.18), Math.max(1, Style.normalBorderWidth))

            Column {
              id: formColumn
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.spacing.xl
              anchors.rightMargin: Style.spacing.xl
              spacing: Style.spacing.lg

              Text {
                width: parent.width
                text: vpn.form ? vpn.form.title.toUpperCase() : ""
                color: vpn.dim
                font.family: vpn.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: Style.font.caption * 0.06
                elide: Text.ElideRight
                textFormat: Text.PlainText
              }

              // Official or self-hosted: the official preset fills the URL in.
              Row {
                id: presetRow
                visible: !!vpn.form && vpn.form.presets.length > 0
                width: parent.width
                spacing: Style.spacing.md

                readonly property int count: vpn.form ? vpn.form.presets.length : 0
                readonly property real cell: count > 0 ? (width - spacing * (count - 1)) / count : 0

                Repeater {
                  model: vpn.form ? vpn.form.presets : []

                  CursorSurface {
                    id: presetChip
                    required property var modelData
                    required property int index

                    width: presetRow.cell
                    height: Math.max(Style.spacing.controlHeight, presetLabel.implicitHeight + Style.spacing.controlPaddingY * 2)
                    current: index === vpn.presetIndex
                    hasCursor: presetMouse.containsMouse
                    bordered: true
                    foreground: vpn.fg

                    Text {
                      id: presetLabel
                      anchors.centerIn: parent
                      width: Math.min(implicitWidth, parent.width - Style.spacing.md * 2)
                      text: presetChip.modelData.label
                      color: presetChip.current ? vpn.fg : vpn.dim
                      font.family: vpn.fontFamily
                      font.pixelSize: Style.font.bodySmall
                      font.bold: presetChip.current
                      elide: Text.ElideRight
                      textFormat: Text.PlainText
                    }

                    MouseArea {
                      id: presetMouse
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: vpn.presetIndex = presetChip.index
                    }
                  }
                }
              }

              TextField {
                id: firstField
                width: parent.width
                placeholderText: vpn.form ? vpn.form.firstLabel : ""
                placeholderTextColor: vpn.faint
                foreground: vpn.fg
                font.family: vpn.fontFamily
                Keys.onReturnPressed: secondField.visible ? secondField.forceActiveFocus() : vpn.submitServerForm()
                Keys.onEscapePressed: vpn.closeServerForm()
              }

              TextField {
                id: secondField
                visible: vpn.needsSecond
                width: parent.width
                placeholderText: vpn.form ? vpn.form.secondLabel : ""
                placeholderTextColor: vpn.faint
                foreground: vpn.fg
                font.family: vpn.fontFamily
                inputMethodHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoAutoUppercase
                Keys.onReturnPressed: vpn.submitServerForm()
                Keys.onEscapePressed: vpn.closeServerForm()
              }

              Text {
                visible: !vpn.needsSecond
                width: parent.width
                text: vpn.preset ? "Signs in at " + vpn.preset.url : ""
                color: vpn.dim
                font.family: vpn.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideMiddle
                textFormat: Text.PlainText
              }

              Row {
                anchors.right: parent.right
                spacing: Style.spacing.md

                Button {
                  text: "Cancel"
                  bordered: true
                  foreground: vpn.fg
                  fontFamily: vpn.fontFamily
                  fontSize: Style.font.bodySmall
                  onClicked: vpn.closeServerForm()
                }

                Button {
                  text: vpn.form ? vpn.form.submitLabel : ""
                  bordered: true
                  foreground: vpn.fg
                  fontFamily: vpn.fontFamily
                  fontSize: Style.font.bodySmall
                  enabled: vpn.formValid && !!vpn.provider && !vpn.provider.busy
                  // Disabled reads as disabled on every theme.
                  opacity: enabled ? 1 : 0.45
                  onClicked: vpn.submitServerForm()
                }
              }
            }
          }
        }

        // ---------- Search: only once the list is long ----------
        TextField {
          id: searchField
          visible: vpn.searchable
          width: parent.width
          placeholderText: "Filter by name or address  ( / )"
          placeholderTextColor: vpn.faint
          foreground: vpn.fg
          font.family: vpn.fontFamily
          text: vpn.query
          onTextEdited: { vpn.query = text; vpn.cursor = -1 }
          Keys.onEscapePressed: { vpn.query = ""; keyCatcher.forceActiveFocus() }
          Keys.onDownPressed: { keyCatcher.forceActiveFocus(); vpn.moveCursor(1) }
          Keys.onReturnPressed: { keyCatcher.forceActiveFocus(); vpn.moveCursor(1) }
        }
      }

      Flickable {
        id: flick
        anchors.top: topArea.bottom
        anchors.topMargin: vpn.listItems.length > 0 && topArea.implicitHeight > 0 ? Style.spacing.xxl : 0
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: joinRow.visible ? joinRow.top : footer.top
        anchors.bottomMargin: Style.spacing.lg
        contentWidth: width
        contentHeight: list.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { id: scrollBar; policy: ScrollBar.AsNeeded }

        // ---------- This device · sections ----------
        Column {
          id: list
          // The scrollbar rides the flickable's right edge; once the list
          // scrolls, keep a gutter for it so it never sits on a row's copy
          // glyph, action button, or the section counts.
          width: flick.width - (flick.interactive ? scrollBar.width + Style.spacing.md : 0)
          spacing: Style.spacing.xs

          Repeater {
            id: listRepeater
            model: vpn.listItems
            delegate: listDelegate
          }
        }
      }

      // ---------- ZeroTier: join a network ----------
      Row {
        id: joinRow
        visible: !!vpn.provider && vpn.provider.joinable
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: footer.top
        anchors.bottomMargin: Style.spacing.lg
        spacing: Style.spacing.md

        TextField {
          id: joinField
          width: parent.width - joinButton.width - parent.spacing
          placeholderText: "Network ID to join"
          placeholderTextColor: vpn.faint
          foreground: vpn.fg
          font.family: vpn.fontFamily
          maximumLength: 16
          Keys.onReturnPressed: joinButton.clicked()
          Keys.onEscapePressed: { text = ""; keyCatcher.forceActiveFocus() }
        }

        Button {
          id: joinButton
          anchors.verticalCenter: parent.verticalCenter
          text: "Join"
          bordered: true
          foreground: vpn.fg
          fontFamily: vpn.fontFamily
          fontSize: Style.font.bodySmall
          enabled: Model.isNetworkId(joinField.text) && !!vpn.provider && !vpn.provider.busy
          // Disabled reads as disabled on every theme.
          opacity: enabled ? 1 : 0.45
          onClicked: {
            if (!enabled) return
            vpn.provider.join(joinField.text)
            joinField.text = ""
            keyCatcher.forceActiveFocus()
          }
        }
      }

      // ---------- Footer: status line · console · refresh ----------
      Item {
        id: footer
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: Math.max(footerText.implicitHeight, footerActions.implicitHeight)

        PanelSeparator {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.top
          anchors.bottomMargin: Style.spacing.sm
          foreground: vpn.fg
        }

        Text {
          id: footerText
          anchors.left: parent.left
          anchors.right: footerActions.left
          anchors.rightMargin: Style.spacing.md
          anchors.verticalCenter: parent.verticalCenter
          readonly property bool hasMessage: !!vpn.provider && vpn.provider.message !== ""
          text: hasMessage ? vpn.provider.message
            : (vpn.cursor >= 0 ? "Enter copy · x action · t toggle" : "h/l tab · j/k move · t toggle · r refresh")
          color: hasMessage && vpn.provider.messageIsError ? vpn.urgent : vpn.dim
          font.family: vpn.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
          textFormat: Text.PlainText
        }

        Row {
          id: footerActions
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.spacing.xs

          PanelActionButton {
            visible: !!vpn.provider && vpn.provider.adminUrl !== ""
            iconText: "󰖟"
            tooltipText: "Open admin console (o)"
            foreground: vpn.fg
            fontFamily: vpn.fontFamily
            onClicked: vpn.provider.openUrl(vpn.provider.adminUrl)
          }

          PanelActionButton {
            visible: !!vpn.provider
            iconText: "󰑐"
            tooltipText: "Refresh (r)"
            foreground: vpn.fg
            fontFamily: vpn.fontFamily
            onClicked: vpn.provider.refresh()
          }
        }
      }
    }
  }

  // ------------------------------------------------------------- delegates

  // One list entry; the kind picks how it draws.
  Component {
    id: listDelegate

    Item {
      id: holder
      required property var modelData
      readonly property var entry: modelData

      width: parent ? parent.width : 0
      height: loader.item ? loader.item.implicitHeight : 0

      Loader {
        id: loader
        width: parent.width
        sourceComponent: holder.entry.kind === "header" ? headerComponent
          : holder.entry.kind === "address" ? addressComponent
          : holder.entry.kind === "row" ? rowComponent
          : holder.entry.kind === "serverToggle" ? serverToggleComponent
          : holder.entry.kind === "addServer" ? addServerComponent
          : emptyComponent
        property var entry: holder.entry
      }
    }
  }

  Component {
    id: serverToggleComponent

    CursorSurface {
      id: toggleRow
      readonly property var entry: parent ? parent.entry : null
      readonly property bool focused: !!entry && vpn.cursor === entry.sel

      implicitHeight: Math.max(Style.spacing.controlHeight, toggleText.implicitHeight) + Style.spacing.md * 2
      hasCursor: focused
      current: vpn.serversOpen
      bordered: true
      foreground: vpn.fg

      Text {
        id: toggleGlyph
        anchors.left: parent.left
        anchors.leftMargin: Style.spacing.lg
        anchors.verticalCenter: parent.verticalCenter
        text: "󰒋"
        color: vpn.dim
        font.family: vpn.fontFamily
        font.pixelSize: Style.font.icon
        textFormat: Text.PlainText
      }

      Column {
        id: toggleText
        anchors.left: toggleGlyph.right
        anchors.leftMargin: Style.spacing.lg
        anchors.right: toggleTrail.left
        anchors.rightMargin: Style.spacing.md
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.spacing.xxs

        Text {
          width: parent.width
          text: toggleRow.entry ? toggleRow.entry.label.toUpperCase() : ""
          color: vpn.dim
          font.family: vpn.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
          font.letterSpacing: Style.font.caption * 0.06
          elide: Text.ElideRight
          textFormat: Text.PlainText
        }

        Text {
          width: parent.width
          text: toggleRow.entry
            ? toggleRow.entry.title + (toggleRow.entry.detail !== "" ? " · " + toggleRow.entry.detail : "")
            : ""
          color: vpn.fg
          font.family: vpn.fontFamily
          font.pixelSize: Style.font.bodySmall
          elide: Text.ElideRight
          textFormat: Text.PlainText
        }
      }

      Row {
        id: toggleTrail
        anchors.right: parent.right
        anchors.rightMargin: Style.spacing.lg
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.spacing.md

        Text {
          anchors.verticalCenter: parent.verticalCenter
          visible: !!toggleRow.entry && toggleRow.entry.count > 1
          text: toggleRow.entry ? String(toggleRow.entry.count) : ""
          color: vpn.faint
          font.family: vpn.fontFamily
          font.pixelSize: Style.font.caption
          textFormat: Text.PlainText
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: vpn.serversOpen ? "󰅃" : "󰅀"
          color: vpn.dim
          font.family: vpn.fontFamily
          font.pixelSize: Style.font.iconSmall
          textFormat: Text.PlainText
        }
      }

      MouseArea {
        id: toggleMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onPositionChanged: function(mouse) {
          if (toggleRow.entry && pointerGate.moved(toggleMouse, mouse)) vpn.cursor = toggleRow.entry.sel
        }
        onClicked: vpn.activate(toggleRow.entry)
      }
    }
  }

  Component {
    id: addServerComponent

    CursorSurface {
      id: addRow
      readonly property var entry: parent ? parent.entry : null
      readonly property bool focused: !!entry && vpn.cursor === entry.sel

      implicitHeight: Math.max(Style.spacing.popupRowHeight, addLabel.implicitHeight + Style.spacing.md * 2)
      hasCursor: focused
      current: vpn.formOpen
      foreground: vpn.fg

      Text {
        id: addGlyph
        anchors.left: parent.left
        anchors.leftMargin: Style.spacing.md
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(7) + Style.spacing.lg
        text: "󰐕"
        color: vpn.dim
        font.family: vpn.fontFamily
        font.pixelSize: Style.font.iconSmall
        textFormat: Text.PlainText
      }

      Text {
        id: addLabel
        anchors.left: addGlyph.right
        anchors.right: parent.right
        anchors.rightMargin: Style.spacing.md
        anchors.verticalCenter: parent.verticalCenter
        text: addRow.entry ? addRow.entry.title : ""
        color: vpn.fg
        font.family: vpn.fontFamily
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideRight
        textFormat: Text.PlainText
      }

      MouseArea {
        id: addMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onPositionChanged: function(mouse) {
          if (addRow.entry && pointerGate.moved(addMouse, mouse)) vpn.cursor = addRow.entry.sel
        }
        onClicked: vpn.activate(addRow.entry)
      }
    }
  }

  Component {
    id: headerComponent

    Item {
      readonly property var entry: parent ? parent.entry : null
      implicitHeight: headerTitle.implicitHeight + Style.spacing.lg + Style.spacing.xs

      Text {
        id: headerTitle
        anchors.left: parent.left
        anchors.right: headerMeta.left
        anchors.rightMargin: Style.spacing.md
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Style.spacing.xs
        text: entry ? entry.title.toUpperCase() : ""
        color: vpn.dim
        font.family: vpn.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        font.letterSpacing: Style.font.caption * 0.06
        elide: Text.ElideRight
        textFormat: Text.PlainText
      }

      Text {
        id: headerMeta
        anchors.right: parent.right
        anchors.baseline: headerTitle.baseline
        text: entry ? entry.meta : ""
        color: vpn.faint
        font.family: vpn.fontFamily
        font.pixelSize: Style.font.caption
        textFormat: Text.PlainText
      }
    }
  }

  Component {
    id: emptyComponent

    Text {
      readonly property var entry: parent ? parent.entry : null
      leftPadding: Style.spacing.md
      topPadding: Style.spacing.xs
      bottomPadding: Style.spacing.xs
      text: entry ? entry.text : ""
      color: vpn.faint
      font.family: vpn.fontFamily
      font.pixelSize: Style.font.bodySmall
      textFormat: Text.PlainText
    }
  }

  Component {
    id: addressComponent

    CursorSurface {
      id: addressRow
      readonly property var entry: parent ? parent.entry : null
      readonly property bool focused: !!entry && vpn.cursor === entry.sel

      implicitHeight: Math.max(Style.spacing.popupRowHeight, addressValue.implicitHeight + Style.spacing.md * 2)
      hasCursor: focused
      foreground: vpn.fg

      Text {
        id: addressLabel
        anchors.left: parent.left
        anchors.leftMargin: Style.spacing.md
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(Style.space(84), parent.width * 0.3)
        text: addressRow.entry ? addressRow.entry.label : ""
        color: vpn.dim
        font.family: vpn.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
        textFormat: Text.PlainText
      }

      Text {
        id: addressValue
        anchors.left: addressLabel.right
        anchors.leftMargin: Style.spacing.md
        anchors.right: addressCopy.left
        anchors.rightMargin: Style.spacing.md
        anchors.verticalCenter: parent.verticalCenter
        text: addressRow.entry ? addressRow.entry.value : ""
        color: vpn.fg
        font.family: vpn.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideMiddle
        textFormat: Text.PlainText
      }

      Text {
        id: addressCopy
        anchors.right: parent.right
        anchors.rightMargin: Style.spacing.md
        anchors.verticalCenter: parent.verticalCenter
        text: "󰆏"
        opacity: addressRow.hasCursor ? 1 : 0
        color: vpn.dim
        font.family: vpn.fontFamily
        font.pixelSize: Style.font.iconSmall
        textFormat: Text.PlainText
      }

      MouseArea {
        id: addressMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onPositionChanged: function(mouse) {
          if (addressRow.entry && pointerGate.moved(addressMouse, mouse)) vpn.cursor = addressRow.entry.sel
        }
        onClicked: vpn.activate(addressRow.entry)
      }
    }
  }

  Component {
    id: rowComponent

    CursorSurface {
      id: peerRow
      readonly property var entry: parent ? parent.entry : null
      readonly property var row: entry ? entry.row : null
      readonly property bool focused: !!entry && vpn.cursor === entry.sel
      readonly property bool armed: !!entry && vpn.armedKey === entry.key
      readonly property bool switchArmed: !!entry && vpn.armedKey === entry.key + "#switch"

      implicitHeight: Math.max(Style.spacing.controlHeight, peerText.implicitHeight) + Style.spacing.md * 2
      hasCursor: focused
      foreground: vpn.fg

      // Online is told twice — filled dot and full-strength name — so it
      // never rests on telling two theme colors apart.
      Rectangle {
        id: peerDot
        anchors.left: parent.left
        anchors.leftMargin: Style.spacing.md
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(7)
        height: width
        radius: width / 2
        color: peerRow.row && peerRow.row.online ? vpn.accent : "transparent"
        border.width: Math.max(1, Style.spacing.hairline)
        border.color: peerRow.row && peerRow.row.online ? vpn.accent : vpn.faint
      }

      MouseArea {
        id: peerMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onPositionChanged: function(mouse) {
          if (peerRow.entry && pointerGate.moved(peerMouse, mouse)) vpn.cursor = peerRow.entry.sel
        }
        onClicked: vpn.activate(peerRow.entry)
      }

      PanelToolTip {
        visible: peerMouse.containsMouse && !!peerRow.entry && peerRow.entry.tip !== ""
        text: peerRow.entry ? peerRow.entry.tip : ""
        fontFamily: vpn.fontFamily
      }

      Column {
        id: peerText
        anchors.left: peerDot.right
        anchors.leftMargin: Style.spacing.lg
        anchors.right: peerTrail.left
        anchors.rightMargin: Style.spacing.md
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.spacing.xxs

        Text {
          width: parent.width
          text: peerRow.row ? peerRow.row.name : ""
          color: peerRow.row && peerRow.row.online ? vpn.fg : vpn.dim
          font.family: vpn.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
          textFormat: Text.PlainText
        }

        Text {
          width: parent.width
          visible: text !== ""
          text: peerRow.row ? peerRow.row.detail : ""
          color: vpn.dim
          font.family: vpn.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
          textFormat: Text.PlainText
        }
      }

      Row {
        id: peerTrail
        anchors.right: parent.right
        anchors.rightMargin: Style.spacing.sm
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.spacing.xs

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: peerRow.entry ? peerRow.entry.glyph : ""
          visible: text !== ""
          opacity: peerRow.hasCursor || peerRow.switchArmed ? 1 : 0
          color: peerRow.switchArmed ? vpn.urgent : vpn.dim
          font.family: vpn.fontFamily
          font.pixelSize: Style.font.iconSmall
          textFormat: Text.PlainText
        }

        PanelActionButton {
          visible: !!peerRow.row && !!peerRow.row.action
          iconText: peerRow.armed ? "󰄬" : (peerRow.row && peerRow.row.action ? peerRow.row.action.glyph : "")
          tooltipText: peerRow.row && peerRow.row.action
            ? (peerRow.armed ? "Click again to " + peerRow.row.action.label.toLowerCase() : peerRow.row.action.label + " (x)")
            : ""
          foreground: peerRow.armed ? vpn.urgent : vpn.fg
          fontFamily: vpn.fontFamily
          onClicked: vpn.rowAction(peerRow.entry)
        }
      }
    }
  }
}
