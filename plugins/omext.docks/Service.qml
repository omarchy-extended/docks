import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons as Commons

// Docks at the screen edges (omext docks, from omarchy-extended). Closed, a
// dock shows as its look has it (hidden, a line, a bar, or a bar of its apps'
// icons); it opens on the pointer resting there, or a click on the bar. Open:
// a column the full height below the top bar, with a bar on its edge holding
// its running apps' icons and Open an app, the open apps' windows sharing the
// column. Click an icon to show its app (one at a time, or any number: the
// dock's mode); right-click it for the app's menu. It closes once the pointer
// has left, unless kept open (then it takes its room from the screen). Drag
// its inner edge to resize it (never narrower than its apps' widest minimum).
// omext-dock places the windows and keeps the config; this file draws `omext-dock list`.
Item {
  id: root

  property var shell: null

  readonly property string tool: Quickshell.env("HOME") + "/.local/bin/omext-dock"
  property var docks: []
  property var dockIds: []
  property bool pickSettings: false  // the picker opens on the dock's settings
  property string picking: ""     // dock whose add-an-app list is open
  property double pickClosedAt: 0  // when the apps menu last closed
  onPickingChanged: if (!picking) pickClosedAt = Date.now()
  property var candidates: null   // omext-dock candidates
  property string iconStyle: "color"  // every dock's icons: color, mono, or mixed (mono until running)
  property string separatorLook: "line"  // the bars' separators: a line, or a space only
  property string moreFor: ""     // "dock/bar/app" whose menu (a bar icon's) is open
  property var leftAt: ({})       // open dock id -> when the pointer left it (ms)
  property var pointerBeen: ({})  // open dock id -> the pointer has been on it since it opened
  readonly property color accent: Commons.Color.accent

  function refresh() {
    listProc.running = false
    listProc.running = true
  }

  function run(args) {
    Quickshell.execDetached([tool].concat(args))
  }

  function load(text) {
    var got = null, all = null
    try { all = JSON.parse(text); got = all.docks } catch (e) { return }
    iconStyle = all.iconStyle || "color"
    separatorLook = all.separatorLook || "line"
    // A report sent before an open or close from here would undo it for a
    // moment: what was asked holds until omext-dock agrees (or 3 s have passed).
    var now = Date.now(), kept = {}, arrived = []
    for (var d of got) {
      var a = asked[d.id]
      if (!a) continue
      if (d.open === a.open) { if (a.open) arrived.push(d.id); continue }
      if (now - a.at > 3000) continue
      d.open = a.open
      kept[d.id] = a
    }
    asked = kept
    docks = got
    // omext-dock reports an opened dock once its apps are in place.
    for (var id of arrived)
      if (phase[id] === "opening") setPhase(id, "arrived")
    var ids = got.map(d => d.id)
    if (JSON.stringify(ids) !== JSON.stringify(dockIds)) dockIds = ids
  }

  function dockById(id) {
    return docks.find(d => d.id === id) || null
  }

  // Opening and closing from here animate (see the panel): "opening" until
  // omext-dock reports the apps in place, "arrived" while the cover fades off
  // them, "closing" while it fades over them before they go. Opened or closed
  // by omext-dock itself, a dock just changes.
  property var phase: ({})   // dock id -> "opening" | "arrived" | "closing"
  property var asked: ({})   // dock id -> { open, at }: see load()

  function setPhase(id, p) {
    var n = Object.assign({}, phase)
    if (p) n[id] = p
    else delete n[id]
    phase = n
  }

  function apply(id, on, later) {
    var n = Object.assign({}, asked)
    n[id] = { open: on, at: Date.now() }
    asked = n
    docks = docks.map(d => d.id === id ? Object.assign({}, d, { open: on }) : d)
    if (!later) run([on ? "open" : "close", id])
  }

  // Docks sharing a screen overlap: one is open at a time there. Opening one
  // closes the others first; it opens once they have (waiting: screen -> dock).
  property var waiting: ({})
  property var sliding: ({})  // docks still on screen (sliding back) though closed
  function rivals(d) {
    return docks.filter(o => o.id !== d.id && o.screen === d.screen && !o.keepOpen
                             && (o.open || phase[o.id] === "opening" || phase[o.id] === "closing" || sliding[o.id]))
  }

  function setOpen(id, on) {
    var d = dockById(id)
    if (!d) return
    if (on) {
      if (phase[id] === "closing") { setPhase(id, ""); return }  // still open: stays
      if (d.open || phase[id]) return
      if (!d.keepOpen) {
        var others = rivals(d)
        if (others.length) {
          var w = Object.assign({}, waiting)
          w[d.screen] = id
          waiting = w
          for (var o of others) setOpen(o.id, false)
          return
        }
      }
      unwait(id)  // opening now: no longer waiting for its screen
      setPhase(id, "opening")
      apply(id, true, true)  // the panel runs omext-dock once it has slid out
    } else {
      if (picking === id) picking = ""  // the apps list goes with it
      if (moreFor.startsWith(id + "/")) moreFor = ""
      if (!d.open || phase[id] === "closing") return
      if (d.keepOpen) { apply(id, false); return }
      setPhase(id, "closing")  // the panel calls finishClose once its cover is up
    }
  }

  function expand(id, app) { run(["expand", id, app]) }

  function finishClose(id) {
    if (phase[id] !== "closing") return
    apply(id, false)
    setPhase(id, "")
  }

  function unwait(id) {
    var w = Object.assign({}, waiting), changed = false
    for (var s in w) if (w[s] === id) { delete w[s]; changed = true }
    if (changed) waiting = w
  }

  // A dock has slid all the way back: one waiting for its screen opens now
  // (never the dock itself: that would open it again each time it closes).
  function closedOut(id) {
    unwait(id)
    var d = dockById(id)
    var next = d ? waiting[d.screen] : ""
    if (next) {
      var n = dockById(next)
      if (n && rivals(n).length) return
      var w = Object.assign({}, waiting)
      delete w[d.screen]
      waiting = w
      setOpen(next, true)
    }
  }

  function openPicker(id) {
    picking = id
    candidates = null
    candidatesProc.running = false
    candidatesProc.running = true
  }

  // An open dock closes once the pointer has been off it for a moment (leaveDelay):
  // coming back in time keeps it open. Its apps' windows are in the dock's
  // area, so the pointer is on the dock while it's on them. It stays open while
  // it animates, and while a menu is open; its apps list closes with it (and,
  // in a dock kept open, on its own once the pointer has left). Opened
  // without the pointer on it (omext-dock, a notification), the pointer gets a
  // while to come (openGrace).
  readonly property int leaveDelay: 500
  readonly property int openGrace: 2500

  function checkPointer(text) {
    var at = null
    try { at = JSON.parse(text) } catch (e) { return }
    if (!at || at.x === undefined) return
    var now = Date.now(), left = {}, been = {}
    for (var d of docks) {
      if (!d.open || !d.rect || (d.keepOpen && picking !== d.id)) continue
      var r = d.rect, grip = 10, onLeft = d.edge === "left", bar = d.barWidth || 0  // its bar counts as on it
      var on = at.x >= r[0] - (onLeft ? bar : grip) && at.x < r[0] + r[2] + (onLeft ? grip : bar)
               && at.y >= r[1] && at.y < r[1] + r[3]
      been[d.id] = on || !!pointerBeen[d.id]
      // Back on it while it fades out: it stays open (the close called off),
      // rather than closing and opening again.
      if (on && phase[d.id] === "closing") { setOpen(d.id, true); continue }
      var busy = phase[d.id] || moreFor.startsWith(d.id + "/")
      if (on || busy) continue
      // When it left; never there yet (opened elsewhere), as if it left a
      // while ago, so it closes after openGrace.
      var since = d.id in leftAt ? leftAt[d.id] : (been[d.id] ? now : now + openGrace - leaveDelay)
      if (now - since < leaveDelay) { left[d.id] = since; continue }
      if (picking === d.id) continue  // the apps menu up: it stays (the menu's beside it)
      if (!d.keepOpen) setOpen(d.id, false)
    }
    leftAt = left
    pointerBeen = been
  }

  // Escape (omext core's bind, wherever the keyboard is): an app's menu goes,
  // else the settings, else the open docks slide away (not one kept open, nor
  // the one whose terminal has the keyboard).
  // Adding an app: its search has the keyboard, and Escape there is its own.
  function escapePressed() {
    if (moreFor) { moreFor = ""; return }
    if (picking) { if (pickSettings) picking = ""; return }
    // Not the dock of a terminal you are in: Escape is a key you use there.
    var held = inTerminal()
    for (var d of docks) if (d.open && !d.keepOpen && d.id !== held) setOpen(d.id, false)
  }
  // The dock whose app has the keyboard, when that app is a terminal (or runs
  // in one: its desktop entry starts a terminal); else "".
  readonly property var terminalRe: /(^|[\/\s=])(foot|footclient|alacritty|kitty|ghostty|wezterm|konsole|xdg-terminal-exec|omarchy-launch-terminal|omarchy-launch-tui|omarchy-launch-or-focus-tui)(\s|$)/
  function inTerminal() {
    var t = Hyprland.activeToplevel
    if (!t) return ""
    var addr = "0x" + t.address
    for (var d of docks)
      for (var a of d.apps) {
        if (a.address !== addr) continue
        var c = t.lastIpcObject || {}
        var cls = String(c.class || c.initialClass || "").toLowerCase()
        if (/^(foot|footclient|alacritty|kitty|com\.mitchellh\.ghostty|ghostty|org\.wezfurlong\.wezterm)$/.test(cls)) return d.id
        var e = DesktopEntries.heuristicLookup(cls)
        if (e && (e.runInTerminal || terminalRe.test(String(e.execString || (e.command || []).join(" "))))) return d.id
        return ""
      }
    return ""
  }
  GlobalShortcut { appid: "omext"; name: "escape-docks"; description: "Close the docks' menus and open docks"; onPressed: root.escapePressed() }

  IpcHandler {
    target: "omext.docks"
    function refresh(): void { root.refresh() }
    function open(id: string): void { root.setOpen(id, true) }  // as resting on its edge does
    function shut(id: string): void { root.setOpen(id, false) }  // (its key, pressed again)
    function expand(id: string, app: string): void { root.expand(id, app) }  // as clicking its bar icon does
    function pick(id: string): void { root.pickSettings = false; root.openPicker(id) }
    function unpick(): void { root.picking = "" }  // the apps menu closed
    function settings(id: string): void { root.pickSettings = true; root.openPicker(id) }  // the gear in it  // as the footer's Open an app does
  }

  Process {
    id: listProc
    command: [root.tool, "list"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.load(text) }
  }

  Process {
    id: candidatesProc
    command: [root.tool, "candidates"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: { try { root.candidates = JSON.parse(text) } catch (e) {} }
    }
  }

  // The title bars on docked apps (titlebar on) look like the ones Omarchy
  // draws on floating windows (hyprbars, default/hypr/workspace-modes.lua): its
  // colour is the theme's lighter background (its selection where that is the
  // background itself), the title in monospace on the left, square buttons on
  // the right in the bar's own colour.
  property var themeColors: ({})
  FileView {
    path: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/colors.toml"
    watchChanges: true
    onFileChanged: reload()
    onLoaded: {
      var out = {}
      for (var line of text().split("\n")) {
        var m = line.match(/^\s*([A-Za-z0-9_]+)\s*=\s*"(#[0-9A-Fa-f]{6})"/)
        if (m) out[m[1]] = m[2]
      }
      root.themeColors = out
    }
  }
  readonly property color titlebarColor: {
    var bg = themeColors.background || Commons.Color.background
    var t = themeColors.lighter_background
    return !t || t === bg ? (themeColors.selection || bg) : t
  }
  readonly property color titlebarText: themeColors.foreground || Commons.Color.foreground
  // A window's title as it is now (omext-dock's list is a few seconds behind).
  function liveTitle(address, fallback) {
    var all = Hyprland.toplevels.values
    for (var i = 0; i < all.length; i++) {
      var t = all[i], ipc = t.lastIpcObject || {}
      if ((ipc.address || "0x" + t.address) === address) return t.title || ipc.title || fallback
    }
    return fallback
  }

  // After a dock has slid all the way back, the pointer coming back to its edge
  // often goes unnoticed: the edge was just under the pointer while it slid
  // back, and its hover is left stale, so a pointer pushed against the screen
  // edge gets no enter until it moves off that line. For a few seconds after,
  // ask Hyprland where the pointer is; resting on the strip opens it as the
  // edge does (edge: the screen edge's x, reach: the strip's width).
  readonly property int edgeWatchFor: 5000
  property var edgeWatch: null
  function checkEdge(id, edge, reach) {
    edgeWatch = { id: id, edge: edge, reach: reach, until: Date.now() + edgeWatchFor, hits: 0 }
  }
  function edgeAt(text) {
    var a = edgeWatch, at = null
    if (!a) return
    try { at = JSON.parse(text) } catch (e) { return }
    var d = dockById(a.id)
    if (!d || !d.rect || d.open || phase[d.id] || Date.now() > a.until) { edgeWatch = null; return }
    if (!at || at.x === undefined) return
    var r = d.rect
    var on = Math.abs(at.x - a.edge) <= a.reach && at.y >= r[1] && at.y < r[1] + r[3]
    a.hits = on ? a.hits + 1 : 0
    if (a.hits >= 2) { edgeWatch = null; setOpen(d.id, true) }  // resting there, not passing
  }
  Timer {
    interval: 100
    repeat: true
    running: root.edgeWatch !== null
    onTriggered: if (!edgeProc.running) edgeProc.running = true
  }
  Process {
    id: edgeProc
    command: ["hyprctl", "cursorpos", "-j"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.edgeAt(text) }
  }

  Process {
    id: pointerProc
    command: ["hyprctl", "cursorpos", "-j"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.checkPointer(text) }
  }

  // Unread counts and apps starting or closing, besides what omext-dock reports.
  Timer { interval: 5000; repeat: true; running: true; onTriggered: root.refresh() }
  Timer {
    interval: 100
    repeat: true
    running: root.docks.some(d => d.open && (!d.keepOpen || root.picking === d.id))
    onTriggered: if (!pointerProc.running) pointerProc.running = true
  }
  Component.onCompleted: refresh()

  // Sizes are the shell's own (Commons.Style), as the top bar uses: its text at
  // font.body, its icons at bar.iconFont and bar.iconCanvas.
  component Glyph: Text {
    color: Commons.Color.popups.text
    font.family: Commons.Style.font.family
    font.pixelSize: Commons.Style.bar.iconFont
    verticalAlignment: Text.AlignVCenter
    horizontalAlignment: Text.AlignHCenter
  }

  // The settings: a card (a title, maybe a line under it), its rows: a label,
  // then the choice (with a line on what the picked one does).
  component SettingsSection: Rectangle {
    id: sec
    property string title
    property string subtitle
    default property alias content: secBody.data
    width: parent ? parent.width : 0
    implicitHeight: secCol.implicitHeight + 24
    radius: 8
    color: Commons.Util.alpha(Commons.Color.foreground, 0.045)
    border.color: Commons.Util.alpha(Commons.Color.popups.text, 0.08)
    Column {
      id: secCol
      x: 12; y: 12
      width: sec.width - 24
      spacing: 10
      Column {
        width: parent.width
        spacing: 1
        Text {
          text: sec.title
          color: Commons.Color.popups.text
          font.family: Commons.Style.font.family
          font.pixelSize: Commons.Style.font.body
          font.bold: true
        }
        Text {
          visible: !!sec.subtitle
          width: parent.width - 40
          elide: Text.ElideRight
          text: sec.subtitle
          color: Commons.Util.alpha(Commons.Color.popups.text, 0.5)
          font.family: Commons.Style.font.family
          font.pixelSize: Commons.Style.font.caption
        }
      }
      Column { id: secBody; width: parent.width; spacing: 8 }
    }
  }
  component SetRow: Row {
    id: srow
    property string label
    default property alias content: srowBody.data
    width: parent ? parent.width : 0
    spacing: 8
    Text {
      width: 92
      height: 22
      verticalAlignment: Text.AlignVCenter
      text: srow.label
      color: Commons.Util.alpha(Commons.Color.popups.text, 0.8)
      font.family: Commons.Style.font.family
      font.pixelSize: Commons.Style.font.bodySmall
    }
    Column { id: srowBody; width: srow.width - 100; spacing: 3 }
  }
  // Pills, one of them picked; under them, what the picked one does.
  component SegPick: Column {
    id: seg
    property var options: []  // {id, label, hint}
    property string cur
    property bool danger: false
    signal picked(string id)
    readonly property var curOpt: options.find(o => o.id === cur) || null
    width: parent ? parent.width : 0
    spacing: 3
    Flow {
      width: parent.width
      spacing: 4
      Repeater {
        model: seg.options
        Rectangle {
          id: pill
          required property var modelData
          readonly property bool on: seg.cur === modelData.id
          readonly property color tint: seg.danger ? Commons.Color.urgent : root.accent
          width: pillText.implicitWidth + 18
          height: 22
          radius: 5
          color: on ? Commons.Util.alpha(tint, 0.28) : pillHit.containsMouse ? Commons.Util.alpha(tint, 0.12) : "transparent"
          border.color: Commons.Util.alpha(tint, on ? 0.75 : 0.3)
          Text {
            id: pillText
            anchors.centerIn: parent
            text: pill.modelData.label
            color: pill.on ? pill.tint : Commons.Util.alpha(Commons.Color.popups.text, 0.8)
            font.family: Commons.Style.font.family
            font.pixelSize: Commons.Style.font.bodySmall
            font.bold: pill.on
          }
          MouseArea {
            id: pillHit
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: if (!pill.on || seg.danger) seg.picked(pill.modelData.id)
          }
        }
      }
    }
    Text {
      visible: !!seg.curOpt && !!seg.curOpt.hint
      width: parent.width
      wrapMode: Text.WordWrap
      text: seg.curOpt && seg.curOpt.hint || ""
      color: Commons.Util.alpha(Commons.Color.popups.text, 0.5)
      font.family: Commons.Style.font.family
      font.pixelSize: Commons.Style.font.caption
    }
  }

  // A menu's grouping: a caption over a group, a rule between groups.
  component MenuCaption: Text {
    leftPadding: 8
    topPadding: 4
    height: 18
    verticalAlignment: Text.AlignBottom
    color: Commons.Util.alpha(Commons.Color.popups.text, 0.45)
    font.family: Commons.Style.font.family
    font.pixelSize: Commons.Style.font.caption
    font.capitalization: Font.AllUppercase
    font.letterSpacing: 0.6
  }
  component MenuRule: Item {
    width: parent ? parent.width : 0
    height: 9
    Rectangle {
      anchors.verticalCenter: parent.verticalCenter
      x: 6; width: parent.width - 12; height: 1
      color: Commons.Util.alpha(Commons.Color.popups.text, 0.12)
    }
  }

  // A small button (in the apps list, a menu).
  component Act: Rectangle {
    id: act
    property string glyph
    property string tip
    property string label  // a word beside the glyph, for buttons that need saying
    property bool on: false
    signal clicked()
    readonly property bool hovered: actHit.containsMouse
    width: label ? actRow.implicitWidth + 14 : 22
    height: 20
    radius: 5
    color: actHit.containsMouse ? Commons.Util.alpha(root.accent, 0.3) : on ? Commons.Util.alpha(root.accent, 0.18) : "transparent"
    Row {
      id: actRow
      // Centred, or from the left when the button is given a width (a menu row).
      anchors.verticalCenter: parent.verticalCenter
      x: act.width > implicitWidth + 14 && act.label ? 8 : (act.width - implicitWidth) / 2
      spacing: 5
      Glyph { anchors.verticalCenter: parent.verticalCenter; text: act.glyph; color: act.on ? root.accent : Commons.Color.popups.text }
      Text {
        visible: !!act.label
        anchors.verticalCenter: parent.verticalCenter
        text: act.label
        color: act.on ? root.accent : Commons.Color.popups.text
        font.family: Commons.Style.font.family
        font.pixelSize: Commons.Style.font.bodySmall
      }
    }
    MouseArea { id: actHit; anchors.fill: parent; hoverEnabled: true; onClicked: act.clicked() }
  }

  Component { id: regionComponent; Region {} }

  Variants {
    model: root.dockIds

    Scope {
    id: dockScope
    required property string modelData

    // The dock's backdrop: its background under the docked windows (a layer
    // below all windows), so where an app doesn't fill its room, or its window
    // is late, the dock shows and not the wallpaper. Never unmapped: closed it
    // is a pixel wide and clear.
    PanelWindow {
      screen: panel.screen
      visible: panel.visible
      anchors { top: true; bottom: true; left: panel.onLeft; right: !panel.onLeft }
      implicitWidth: panel.shown ? panel.fullWidth + panel.barW : 1
      color: "transparent"
      // Placed by the dock's own rect, not by the reserved zones: the dock's
      // bar (or kept-open room) reserves room that would push it inward again.
      exclusionMode: ExclusionMode.Ignore
      margins.top: panel.dock && panel.screen ? Math.max(0, panel.dock.rect[1] - panel.screen.y) : 0
      margins.bottom: panel.dock && panel.screen ? Math.max(0, panel.screen.y + panel.screen.height - panel.dock.rect[1] - panel.dock.rect[3]) : 0
      WlrLayershell.layer: WlrLayer.Bottom
      WlrLayershell.namespace: "omext-docks-backdrop"
      mask: Region {}
      Rectangle {
        visible: panel.shown
        x: (panel.onLeft ? panel.barW : 0) + (1 - panel.reveal) * (panel.onLeft ? -width : width)
        width: panel.fullWidth
        height: parent.height
        color: Commons.Color.popups.background
      }
    }

    PanelWindow {
      id: panel
      readonly property string modelData: dockScope.modelData
      readonly property var dock: root.dockById(modelData)
      readonly property bool isOpen: !!dock && dock.open
      readonly property bool onLeft: !dock || dock.edge === "left"
      // The dock slides out from its edge as one sheet (reveal) under a cover of
      // its own background (cover), which fades away once omext-dock reports its
      // apps' windows in place behind it. Closing from here it's the other way
      // round: the cover fades over the apps, they go, and the sheet slides back.
      readonly property string phase: root.phase[modelData] || ""
      property real reveal: isOpen ? 1 : 0
      Behavior on reveal {
        SequentialAnimation {
          // Closing: a moment for omext-dock to hide the windows under the cover.
          PauseAnimation { duration: panel.isOpen ? 0 : 200 }
          NumberAnimation { duration: 160; easing.type: panel.isOpen ? Easing.OutCubic : Easing.InCubic }
        }
      }
      readonly property bool shown: isOpen || reveal > 0
      onRevealChanged: if (reveal === 1 && phase === "opening") root.run(["open", modelData])
      onShownChanged: {
        var sl = Object.assign({}, root.sliding)
        if (shown) sl[modelData] = true
        else delete sl[modelData]
        root.sliding = sl
        if (!shown) {
          cover = 0
          root.closedOut(modelData)
          if (!closedIcons && screen)  // opened by resting on its edge: is the pointer there already?
            root.checkEdge(modelData, onLeft ? screen.x : screen.x + screen.width, closedW + 2)
        }
      }
      property real cover: 0
      onPhaseChanged: {
        coverOff.stop()
        coverOn.stop()
        arriveLate.stop()
        if (phase === "opening") {
          cover = 1
          arriveLate.start()
          if (reveal === 1) root.run(["open", modelData])  // already out (reopened as it closed)
        }
        else if (phase === "arrived") coverOff.start()
        else if (phase === "closing") coverOn.start()
        else if (isOpen && cover > 0) coverOff.start()  // a close called off
      }
      // Should omext-dock's report not come, the cover goes anyway.
      Timer { id: arriveLate; interval: 2500; onTriggered: if (panel.phase === "opening") root.setPhase(panel.modelData, "arrived") }
      SequentialAnimation {
        id: coverOff
        PauseAnimation { duration: panel.phase === "arrived" ? 120 : 0 }  // the windows' first frames
        NumberAnimation { target: panel; property: "cover"; to: 0; duration: 180; easing.type: Easing.InOutQuad }
        ScriptAction { script: if (panel.phase === "arrived") root.setPhase(panel.modelData, "") }
      }
      SequentialAnimation {
        id: coverOn
        NumberAnimation { target: panel; property: "cover"; to: 1; duration: 250; easing.type: Easing.InOutQuad }
        ScriptAction { script: root.finishClose(panel.modelData) }
      }
      // Resizing: while the inner edge is dragged the panel takes the widest a
      // dock can be, so the drag stays inside it; the width shows as a line and
      // is set when let go (then kept until omext-dock reports it).
      property bool dragging: false
      property int previewWidth: 0
      property int dragWidth: 0
      readonly property int maxWidth: dock ? Math.max(dock.maxWidth || 0, dock.minWidth || 0) : 600
      readonly property int fullWidth: dragging ? previewWidth : (dragWidth || (dock ? dock.width : 0))
      // A closed look that takes room (a bar): the dock opens beside it.
      readonly property int barW: dock ? dock.barWidth || 0 : 0
      readonly property int contentX: onLeft ? barW : width - fullWidth - barW
      // The resize grip reaches this far past the inner edge: Hyprland lets a
      // floating window be resized from just outside its edge (the border grab
      // area), and the docked windows' edges are at the dock's.
      readonly property int grip: 10
      readonly property int topY: dock ? dock.rect[1] : 0
      // Where the open apps end: below, the dock's own background (the apps'
      // windows are their own background).
      readonly property int usedTo: {
        var end = 0
        for (var a of (dock ? dock.apps.filter(a => a.window) : []))
          end = Math.max(end, a.window[1] + a.window[3] - topY)
        return end
      }

      screen: dock ? Quickshell.screens.find(s => s.name === dock.screen) || null : null
      visible: !!dock && !dock.off && Quickshell.screens.some(s => s.name === dock.screen)
      anchors { top: true; bottom: true; left: panel.onLeft; right: !panel.onLeft }
      // Closed, apps with unread messages show as tabs on the edge, halfway
      // down the screen: the app's name and count running along the edge, one
      // after another along it when there are more, each in the app's own colour.
      readonly property int noteW: 26
      readonly property int noteGap: 4
      // How it shows closed (the dock's look): hidden, a dimmed line, a bar that
      // takes its room, or a wider bar of its apps' icons (also taking room).
      readonly property string look: dock ? dock.look || "hidden" : "hidden"
      readonly property bool small: !dock || dock.iconSize !== "large"  // the bar's icons
      readonly property string iconStyle: root.iconStyle
      readonly property int closedW: look === "icons" ? barW : look === "slim" ? Math.round(2 + chip * 2 / 3) : look === "bar" ? 8 : look === "line" ? 3 : 2
      readonly property bool claims: look === "bar" || look === "slim" || look === "icons"
      // A bar with the apps' icons: large ones in it (icons), or small ones on
      // its inner edge, hanging half out of it (slim).
      // Open, every dock has the icon bar; closed, only these looks show icons.
      readonly property bool closedIcons: look === "icons" || look === "slim"
      // Round icons: small ones, or large ones on the half-icons bar (hanging
      // half out of it); large ones elsewhere sit square in the bar.
      readonly property bool slim: small || look === "slim"
      // Where a round icon's centre is, from the screen edge: on the slim bar's
      // inner edge (hanging half out while closed), else mid-bar.
      // Half icons: 2 px in from the edge, two thirds of it on the bar and a third out.
      readonly property real chipC: look === "slim" ? 2 + chip / 2 : barW / 2
      readonly property int chip: small ? 22 : 32  // a round icon's face
      readonly property int cellH: slim ? chip + 4 : 32
      readonly property int hang: look === "slim" ? 2 + chip - closedW : 0  // how far it reaches past the bar
      readonly property var barApps: dock ? dock.apps.filter(a => a.running || a.pinned) : []  // pinned: also not running
      // The icons' model: their ids, changed only when they do. Each report
      // brings a new apps list; were that the model, every icon would be built
      // anew every few seconds, and a click pressed on one before and let go
      // after would be lost.
      property var barIds: []
      onBarAppsChanged: {
        var ids = barApps.map(a => a.id)
        if (JSON.stringify(ids) !== JSON.stringify(barIds)) barIds = ids
      }
      onBarIdsChanged: if (dropShift) endDrag()
      // Dragging a bar icon up or down reorders the apps: the icon follows the
      // pointer, the others make room, and it lands where it's let go.
      property string dragId: ""
      property int dragFrom: -1
      property real dragDy: 0
      readonly property int dragStep: cellH + 2
      readonly property int dragTo: dragId ? Math.max(0, Math.min(barApps.length - 1, dragFrom + Math.round(dragDy / dragStep))) : -1
      property bool dropShift: false  // dropped: the icons hold their new places until the new order comes
      // The bin at the bar's foot while an icon is dragged: dropped on it, the
      // app (or separator) is removed from the dock.
      property bool overBin: false
      readonly property int binH: 68
      function endDrag() { dropShift = false; dragId = ""; dragDy = 0; dragFrom = -1; overBin = false }
      Timer { id: dropHold; interval: 1500; onTriggered: if (panel.dropShift) panel.endDrag() }
      // Where the hanging icons are (they take clicks there, over the dock or
      // the windows beside it).
      readonly property var hangRects: {
        if (!hang) return []
        var x = onLeft ? closedW : width - closedW - hang
        return [[x, 6, hang, barApps.length * (cellH + 2)], [x, height - 68, hang, 68]]
      }
      readonly property var notes: {
        if (!dock || closedIcons) return []  // the icons carry their counts
        var out = []
        dock.apps.forEach((a, i) => { if (a.unread > 0) out.push({ id: a.id, name: a.name, count: a.unread, hue: i }) })
        return out
      }
      // As wide as the open dock, also while closed (the closed dock's parts sit
      // at its edge, and the mask leaves the rest to what lies under it). Were
      // it to grow as the dock opens, Hyprland would draw the closed strip
      // stretched over the whole dock for a frame, until the new picture comes.
      implicitWidth: (dragging ? maxWidth : fullWidth + grip) + barW
      color: "transparent"
      exclusionMode: ExclusionMode.Normal
      exclusiveZone: dock && dock.keepOpen ? (dragWidth || dock.width) + barW : claims ? closedW : 0
      WlrLayershell.layer: WlrLayer.Top
      WlrLayershell.namespace: "omext-docks"
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None  // (adding an app and the settings have their own window)

      // Clicks reach the dock's own parts only; the apps' windows lie in between.
      readonly property var maskRects: {
        if (!dock) return []
        if (!isOpen && menuOpen) return [[0, 0, width, height]]  // an icon's menu, the dock closed: a click beside it closes it
        if (!isOpen)  // the edge strip, and the notification tabs on it
          return [[onLeft ? 0 : width - closedW, 0, closedW, height]].concat(hangRects).concat(notes.length ? [[noteRow.x, noteRow.y, noteRow.width, noteRow.height]] : [])
        if (dragging) return [[0, 0, width, height]]
        var bar = barW ? [[onLeft ? 0 : width - barW, 0, barW, height]] : []  // the bar, beside it
        if (menuOpen) return [[contentX, 0, fullWidth, height]].concat(bar)
        bar = bar.concat(hangRects)
        var out = [[contentX, usedTo, fullWidth, Math.max(0, height - usedTo)]]
        for (var a of dock.apps) if (a.bar) out.push([contentX, a.bar[1] - topY, fullWidth, a.bar[3]])  // title bars
        out.push([onLeft ? contentX + fullWidth - 6 : contentX - grip, 0, 6 + grip, height])
        out = out.concat(bar)  // the bar, beside it
        return out
      }
      // A menu open in this dock (a bar icon's): the whole dock takes clicks, so
      // one beside the menu closes it.
      readonly property bool menuOpen: root.moreFor.startsWith(modelData + "/")
      mask: Region { id: maskRegion }
      onMaskRectsChanged: {
        var old = maskRegion.regions
        maskRegion.regions = maskRects.map(r => regionComponent.createObject(maskRegion, { x: r[0], y: r[1], width: r[2], height: r[3] }))
        for (var i = 0; i < old.length; i++) old[i].destroy()
      }

      // An app's colour: the accent's hue turned by its place in the dock.
      function noteColor(i) {
        var c = Qt.color(root.accent)
        var h = c.hslHue < 0 ? 0.6 : c.hslHue
        return Qt.hsla((h + i * 0.17) % 1, 0.55, 0.62, 1)
      }

      Column {
        id: noteRow
        visible: !panel.shown && panel.notes.length > 0
        z: 3  // over the edge that opens on hover: a tab opens on a click
        x: panel.onLeft ? 0 : panel.width - width
        y: Math.round((panel.height - height) / 2)
        spacing: panel.noteGap
        Repeater {
          model: panel.notes
          Rectangle {
            id: note
            required property var modelData
            // Out from the edge: its edge side square, the other rounded.
            width: panel.noteW
            height: label.implicitWidth + count.height + 26
            radius: 6
            color: noteHit.containsMouse ? Qt.lighter(panel.noteColor(modelData.hue), 1.15) : panel.noteColor(modelData.hue)
            opacity: 0
            Component.onCompleted: opacity = 1
            Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.OutQuad } }
            Rectangle {  // squares the corners against the screen edge
              x: panel.onLeft ? 0 : parent.width - width
              width: parent.radius
              height: parent.height
              color: parent.color
            }
            Rectangle {
              id: count
              anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 5 }
              width: 18
              height: 18
              radius: 9
              color: Commons.Color.background
              Text {
                anchors.centerIn: parent
                text: note.modelData.count > 99 ? "99" : note.modelData.count
                color: note.color
                font.family: Commons.Style.font.family
                font.pixelSize: Commons.Style.font.caption
                font.bold: true
              }
            }
            Text {
              id: label
              // Read along the edge: up the left one, down the right one.
              anchors.centerIn: parent
              anchors.verticalCenterOffset: (count.height + 5) / 2
              rotation: panel.onLeft ? -90 : 90
              text: note.modelData.name
              color: Commons.Color.background
              font.family: Commons.Style.font.family
              font.pixelSize: Commons.Style.font.bodySmall
              font.bold: true
            }
            MouseArea {  // a click opens the dock on that app
              id: noteHit
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                openTimer.stop()
                root.run(["expand", panel.modelData, note.modelData.id, "on"])
                openAfter.start()
              }
            }
          }
        }
      }

      // Closed, as its look has it: a line, a bar, or a bar of its apps' icons
      // (a click on one opens the dock on that app). Under the sheet when open.
      Rectangle {
        visible: panel.look !== "hidden" || panel.shown
        z: 1  // over the sheet as it slides out from under it
        x: panel.onLeft ? 0 : panel.width - width
        // Open: a full bar, behind its icons.
        width: panel.shown ? panel.barW : panel.closedW
        height: parent.height
        color: panel.look === "line" && !panel.shown ? Commons.Util.alpha(root.accent, 0.35) : Commons.Color.popups.background
        Rectangle {  // the inner edge
          visible: panel.claims || panel.shown
          x: panel.onLeft ? parent.width - 1 : 0
          width: 1
          height: parent.height
          color: Commons.Util.alpha(root.accent, 0.4)
        }
        MouseArea {  // a click beside the icons opens it (or closes it)
          anchors.fill: parent
          visible: panel.closedIcons || panel.shown
          onClicked: root.setOpen(panel.modelData, !panel.isOpen)
        }
        // While an icon is dragged: the bin, where + and the gear are.
        Rectangle {
          visible: !!panel.dragId && !panel.dropShift
          z: 20
          anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
          height: panel.binH
          // (Solid: + and the gear are under it.)
          color: panel.overBin ? Qt.tint(Commons.Color.popups.background, Commons.Util.alpha(Commons.Color.urgent, 0.45)) : Commons.Color.popups.background
          border.width: 1
          border.color: Commons.Util.alpha(Commons.Color.urgent, panel.overBin ? 1 : 0.5)
          Glyph {
            x: panel.slim ? (panel.onLeft ? panel.chipC : parent.width - panel.chipC) - width / 2 : (parent.width - width) / 2
            anchors.verticalCenter: parent.verticalCenter
            text: "\u{F0A7A}"
            font.pixelSize: panel.small ? 14 : 18
            color: panel.overBin ? Commons.Color.popups.text : Commons.Color.urgent
          }
        }
        // At its foot: add an app (+), and under it the docks' settings.
        Column {
          visible: panel.closedIcons || panel.shown
          anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
          Repeater {
            model: [{ glyph: "\u{F0415}", settings: false }, { glyph: "\u{F0493}", settings: true }]
            Rectangle {
              id: foot
              required property var modelData
              readonly property bool up: root.picking === panel.modelData && root.pickSettings === modelData.settings
              width: parent.width
              height: 34
              color: !panel.slim && (footHit.containsMouse || up) ? Commons.Util.alpha(root.accent, 0.25) : "transparent"
              Rectangle {  // slim: a round face on the inner edge
                visible: panel.slim
                x: (panel.onLeft ? panel.chipC : parent.width - panel.chipC) - panel.chip / 2
                anchors.verticalCenter: parent.verticalCenter
                width: panel.chip; height: panel.chip; radius: panel.chip / 2
                color: footHit.containsMouse || foot.up ? Commons.Color.popups.background : Commons.Util.alpha(Commons.Color.popups.background, 0.5)
                border.width: footHit.containsMouse || foot.up ? 2 : 1
                border.color: footHit.containsMouse || foot.up ? root.accent : Commons.Util.alpha(Commons.Color.popups.text, 0.25)
              }
              Glyph {
                x: panel.slim ? (panel.onLeft ? panel.chipC : parent.width - panel.chipC) - width / 2 : (parent.width - width) / 2
                anchors.verticalCenter: parent.verticalCenter
                text: foot.modelData.glyph
                font.pixelSize: panel.small ? 12 : 16
                color: foot.up ? root.accent : Commons.Color.popups.text
              }
              MouseArea {
                id: footHit
                x: panel.slim && !panel.onLeft ? Math.min(0, parent.width - panel.chipC - panel.chip / 2) : 0
                width: panel.slim ? Math.max(parent.width, panel.chipC + panel.chip / 2) : parent.width
                height: parent.height
                hoverEnabled: true
                onClicked: {
                  if (foot.up) { root.picking = ""; return }
                  // It closed on this very click (the keyboard went from it): it stays shut.
                  if (root.picking !== panel.modelData && Date.now() - root.pickClosedAt < 400) return
                  root.pickSettings = foot.modelData.settings
                  if (root.picking !== panel.modelData) root.openPicker(panel.modelData)
                }
              }
            }
          }
        }
        Column {
          visible: panel.closedIcons || panel.shown
          y: 6
          width: parent.width
          spacing: 2
          Repeater {
            model: panel.barIds  // its running apps
            Rectangle {
              id: dockIcon
              required property var modelData  // the app's id
              required property int index
              readonly property var app: panel.barApps.find(a => a.id === modelData) || ({ id: modelData })
              readonly property bool isShown: !!app.window || (app.expanded && app.running)
              readonly property bool dragged: panel.dragId === modelData
              // Where it shows while one is dragged: the dragged one at the
              // pointer, those between its place and where it would land a
              // step over, to make room.
              readonly property real shift: {
                if (!panel.dragId || panel.dragFrom < 0) return 0
                if (dragged) return panel.dropShift ? (panel.dragTo - panel.dragFrom) * panel.dragStep : panel.dragDy
                var f = panel.dragFrom, t = panel.dragTo
                if (f < t && index > f && index <= t) return -panel.dragStep
                if (f > t && index >= t && index < f) return panel.dragStep
                return 0
              }
              transform: Translate {
                y: dockIcon.shift
                Behavior on y { enabled: !dockIcon.dragged; NumberAnimation { duration: 140; easing.type: Easing.OutQuad } }
              }
              z: dragged ? 10 : 0
              opacity: dragged && !panel.dropShift ? 0.85 : 1
              width: parent.width
              // A separator: a line between the icons, not an app.
              readonly property bool sep: !!app.separator
              height: sep ? 13 : panel.cellH
              color: !panel.slim && !sep && iconHit2.containsMouse ? Commons.Util.alpha(root.accent, 0.25) : "transparent"
              Rectangle {  // (a space only: the line shows under the pointer, to take hold of it)
                visible: dockIcon.sep && (root.separatorLook === "line" || iconHit2.containsMouse || dockIcon.dragged)
                x: panel.slim ? (panel.onLeft ? 2 : parent.width - 2 - width) : parent.width * 0.2
                anchors.verticalCenter: parent.verticalCenter
                width: panel.slim ? Math.max(6, panel.closedW - 4) : parent.width * 0.6
                height: iconHit2.containsMouse ? 2 : 1
                color: iconHit2.containsMouse ? root.accent : Commons.Util.alpha(Commons.Color.popups.text, 0.35)
              }
              Rectangle {  // slim: a round face on the inner edge, half out of the bar
                visible: panel.slim && !dockIcon.sep
                x: (panel.onLeft ? panel.chipC : parent.width - panel.chipC) - panel.chip / 2
                anchors.verticalCenter: parent.verticalCenter
                width: panel.chip; height: panel.chip; radius: panel.chip / 2
                color: iconHit2.containsMouse ? Commons.Color.popups.background : Commons.Util.alpha(Commons.Color.popups.background, 0.5)
                // The ring: the accent for the app shown, lighter on hover.
                border.width: dockIcon.isShown || iconHit2.containsMouse ? 2 : 1
                border.color: iconHit2.containsMouse ? Qt.lighter(root.accent, 1.35)
                              : dockIcon.isShown ? root.accent : Commons.Util.alpha(Commons.Color.popups.text, 0.25)
              }
              Image {
                x: panel.slim ? (panel.onLeft ? panel.chipC : parent.width - panel.chipC) - width / 2 : (parent.width - width) / 2
                anchors.verticalCenter: parent.verticalCenter
                width: panel.slim ? (panel.small ? 14 : 20) : 22; height: width
                sourceSize: Qt.size(44, 44)
                source: dockIcon.app.icon ? Quickshell.iconPath(dockIcon.app.icon, true) : ""
                opacity: dockIcon.app.running ? 1 : 0.45
                // Monochrome (the dock's icon style; mixed: only a pinned app not
                // running): no colour of its own, in the theme's text colour, its
                // shading kept.
                layer.enabled: panel.iconStyle === "mono" || (panel.iconStyle === "mixed" && !dockIcon.app.running)
                layer.effect: MultiEffect {
                  saturation: -1
                  colorization: 1
                  colorizationColor: Commons.Color.popups.text
                }
              }
              Rectangle {  // the one open: a mark on the inner side
                visible: !panel.slim && dockIcon.isShown
                x: panel.onLeft ? parent.width - 4 : 1
                anchors.verticalCenter: parent.verticalCenter
                width: 3; height: 16; radius: 1.5
                color: root.accent
              }
              Rectangle {  // unread
                visible: dockIcon.app.unread > 0
                anchors { right: parent.right; top: parent.top; rightMargin: panel.slim ? (panel.onLeft ? parent.width - panel.chipC - panel.chip / 2 : panel.chipC - panel.chip / 2) : 3; topMargin: panel.slim ? (panel.cellH - panel.chip) / 2 - 2 : 2 }  // within the round icon's corner: past it, the panel's edge cuts it off
                width: Math.max(12, unreadText.implicitWidth + 6)
                height: 12
                radius: 6
                color: root.accent
                Text {
                  id: unreadText
                  anchors.centerIn: parent
                  text: dockIcon.app.unread > 99 ? "99" : dockIcon.app.unread
                  color: Commons.Color.background
                  font.family: Commons.Style.font.family
                  font.pixelSize: 8
                  font.bold: true
                }
              }
              MouseArea {
                id: iconHit2
                x: panel.slim && !panel.onLeft ? Math.min(0, parent.width - panel.chipC - panel.chip / 2) : 0
                width: panel.slim ? Math.max(parent.width, panel.chipC + panel.chip / 2) : parent.width
                height: parent.height
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                preventStealing: true
                // Drag (left button, a few pixels): reorder. Else a click.
                property real pressY: 0
                property bool wasDrag: false
                function colY(mouse) { return mapToItem(dockIcon.parent, 0, mouse.y).y }
                onPressed: mouse => { pressY = colY(mouse); wasDrag = false }
                onPositionChanged: mouse => {
                  if (!(pressed && (mouse.buttons & Qt.LeftButton))) return
                  var dy = colY(mouse) - pressY
                  if (!panel.dragId && Math.abs(dy) > 6) {
                    root.moreFor = ""
                    panel.dragFrom = dockIcon.index
                    panel.dragId = dockIcon.app.id
                    wasDrag = true
                  }
                  if (panel.dragId === dockIcon.app.id && !panel.dropShift) {
                    panel.dragDy = dy
                    panel.overBin = mapToItem(panel.contentItem, 0, mouse.y).y > panel.height - panel.binH
                  }
                }
                onReleased: {
                  if (panel.dragId !== dockIcon.app.id || panel.dropShift) return
                  if (panel.overBin) {  // on the bin: out of the dock
                    var gone = dockIcon.app.id
                    panel.endDrag()
                    root.run(["remove", panel.modelData, gone])
                    return
                  }
                  var apps = panel.barApps, f = panel.dragFrom, t = panel.dragTo
                  if (t !== f) {
                    // Before the app now at its new place (moving down: the one after it).
                    var before = t > f ? (t + 1 < apps.length ? apps[t + 1].id : "") : apps[t].id
                    root.run(before ? ["move", panel.modelData, dockIcon.app.id, "before", before]
                                    : ["move", panel.modelData, dockIcon.app.id, "end"])
                    panel.dropShift = true  // held there until the new order comes
                    dropHold.restart()
                  } else panel.endDrag()
                }
                onCanceled: if (!panel.dropShift) panel.endDrag()
                onClicked: mouse => {
                  if (wasDrag) return
                  if (mouse.button === Qt.RightButton) {  // the app's menu (as the one on its title bar)
                    var key = panel.modelData + "/bar/" + dockIcon.app.id
                    if (root.moreFor === key) { root.moreFor = ""; return }
                    var at = mapToItem(panel.contentItem, 0, 0)
                    panel.barMenuX = panel.onLeft ? panel.barW + 6 + 210 : panel.width - panel.barW - 6
                    panel.barMenuY = at.y
                    root.moreFor = key
                    return
                  }
                  root.moreFor = ""
                  if (dockIcon.sep) return
                  // The apps list open: the click goes back to that app.
                  if (root.picking === panel.modelData) {
                    root.picking = ""
                    root.run(["expand", panel.modelData, dockIcon.app.id, "on"])
                    return
                  }
                  // The only app open: a second click closes the dock (the app
                  // stays the open one, for next time), default or not.
                  if (panel.isOpen && !!dockIcon.app.window
                      && panel.dock.apps.filter(a => a.window).length === 1) {
                    root.setOpen(panel.modelData, false)
                    return
                  }
                  // Free mode, the app open: a second click closes it.
                  var off = panel.isOpen && panel.dock.mode === "free" && !!dockIcon.app.window
                  root.run(["expand", panel.modelData, dockIcon.app.id, off ? "off" : "on"])
                  if (!panel.isOpen) openAfter.start()
                }
              }
            }
          }
        }
      }

      // An app's menu (its title bar's ⋯), under the button: the app's settings
      // (release, restart and quit are on the title bar itself).
      property real barMenuY: 0
      property real barMenuX: 0
      readonly property string barMenuId: root.moreFor.startsWith(modelData + "/bar/") ? root.moreFor.slice(modelData.length + 5) : ""
      readonly property var barMenuApp: barMenuId && dock ? dock.apps.find(a => a.id === barMenuId) || null : null
      Rectangle {
        id: barMenu
        z: 70
        visible: !!panel.barMenuApp  // (also while the dock is closed: from an icon on its bar)
        x: Math.max(4, Math.min(panel.barMenuX - width, panel.width - width - 4))
        y: Math.max(4, Math.min(panel.barMenuY, panel.height - height - 4))
        width: 210
        height: barMenuCol.implicitHeight + 8
        radius: 6
        color: Commons.Color.popups.background
        border.color: Commons.Util.alpha(Commons.Color.popups.border, 0.6)
        readonly property var app: panel.barMenuApp || ({})
        function act(args) { root.run(args.slice(0, 1).concat([panel.modelData, app.id]).concat(args.slice(1))) }
        MouseArea { anchors.fill: parent }  // not through to the catcher below
        Column {
          id: barMenuCol
          anchors { left: parent.left; right: parent.right; top: parent.top; margins: 4 }
          spacing: 1
          // The app: its icon and name.
          Row {
            leftPadding: 8
            topPadding: 4
            bottomPadding: 2
            spacing: 8
            Image {
              anchors.verticalCenter: parent.verticalCenter
              width: 18; height: 18
              sourceSize: Qt.size(36, 36)
              source: barMenu.app.icon ? Quickshell.iconPath(barMenu.app.icon, true) : ""
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              width: barMenuCol.width - 44
              elide: Text.ElideRight
              text: barMenu.app.name || ""
              color: Commons.Color.popups.text
              font.family: Commons.Style.font.family
              font.pixelSize: Commons.Style.font.bodySmall
              font.bold: true
            }
          }
          MenuRule {}
          Act {
            width: parent.width
            visible: !barMenu.app.separator
            readonly property bool isDefault: !!panel.dock && panel.dock.default === barMenu.app.id
            glyph: "\u{F02DC}"; on: isDefault
            label: isDefault ? "Default app" : "Make default app"
            onClicked: if (!isDefault) barMenu.act(["default"])
          }
          Act {
            width: parent.width
            visible: !barMenu.app.separator
            glyph: barMenu.app.startOnLoad ? "\u{F0132}" : "\u{F0131}"
            label: "Start on load"
            onClicked: barMenu.act(["start-on-load", barMenu.app.startOnLoad ? "off" : "on"])
          }
          Act {
            width: parent.width
            visible: !barMenu.app.separator
            glyph: barMenu.app.keepAlive ? "\u{F0132}" : "\u{F0131}"
            label: "Keep alive"
            onClicked: barMenu.act(["keep-alive", barMenu.app.keepAlive ? "off" : "on"])
          }
          MenuRule {}
          Act {
            width: parent.width
            glyph: "\u{F0377}"
            label: "Remove from dock"
            onClicked: { var a = barMenu.app.id; root.moreFor = ""; root.run(["remove", panel.modelData, a]) }
          }
        }
      }

      MouseArea {  // an icon's menu up while the dock is closed: a click beside it closes it
        anchors.fill: parent
        z: 60
        visible: panel.menuOpen && !panel.shown
        acceptedButtons: Qt.AllButtons
        onClicked: root.moreFor = ""
      }

      // Closed (not an icon bar): resting on its edge opens the dock.
      MouseArea {
        anchors.fill: parent
        id: edgeHit
        visible: !panel.isOpen && !panel.closedIcons
        hoverEnabled: true
        // Only on the edge strip itself, the dock all the way in: while it
        // slides back this covers the whole dock, and a pointer last seen there
        // (on an app, say) would open it again as soon as it closed. Not over
        // an app's tab either (that opens on a click, on its app).
        function onEdge() {
          var fromEdge = panel.onLeft ? mouseX : width - mouseX
          return containsMouse && !panel.shown && fromEdge >= 0 && fromEdge <= panel.closedW + 2
        }
        function check() {
          var p = mapToItem(noteRow, mouseX, mouseY)
          if (!onEdge() || (noteRow.visible && noteRow.childAt(p.x, p.y))) openTimer.stop()
          else if (!openTimer.running) openTimer.start()
        }
        onEntered: check()
        onPositionChanged: check()
        onExited: openTimer.stop()
        Timer {
          id: openTimer
          interval: 150
          onTriggered: if (edgeHit.onEdge()) root.setOpen(panel.modelData, true)
        }
        Timer { id: openAfter; interval: 250; onTriggered: root.setOpen(panel.modelData, true) }
      }

      Item {
        id: sheet
        x: panel.contentX + (1 - panel.reveal) * (panel.onLeft ? -width : width)
        width: panel.fullWidth
        height: parent.height
        visible: panel.shown

        // A click beside an open menu closes it (and the right-click bar).
        MouseArea {
          anchors.fill: parent
          z: 65
          visible: panel.menuOpen
          acceptedButtons: Qt.AllButtons
          onClicked: root.moreFor = ""
        }

        // A thin line between the open apps.
        Repeater {
          model: panel.dock
            ? panel.dock.apps.filter(a => a.window && (a.bar || a.window)[1] > panel.topY) : []
          Rectangle {
            required property var modelData
            z: 50
            y: (modelData.bar || modelData.window)[1] - panel.topY
            width: parent.width
            height: 1
            color: Commons.Util.alpha(Commons.Color.popups.border, 0.8)
          }
        }

        // Title bars (titlebar on): one above each app shown, as Omarchy draws them
        // on floating windows; release, restart and quit on it, the rest in its menu.
        Repeater {
          model: panel.dock ? panel.dock.apps.filter(a => a.bar) : []
          Rectangle {
            id: tbar
            required property var modelData
            readonly property string menuKey: panel.modelData + "/bar/" + modelData.id
            z: 40
            y: modelData.bar[1] - panel.topY
            width: parent.width
            height: modelData.bar[3]
            color: root.titlebarColor
            Text {
              anchors { left: parent.left; leftMargin: 10; right: tbarButtons.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
              elide: Text.ElideRight
              text: root.liveTitle(tbar.modelData.address, tbar.modelData.title || tbar.modelData.name)
              color: root.titlebarText
              font.family: "monospace"
              font.pixelSize: 12
            }
            Row {
              id: tbarButtons
              anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
              spacing: 8
              Repeater {
                // Kept alive, it can't be quit (it would only come back): no ×.
                model: [
                  { icon: "\u22EF", tip: "More", act: "menu" },
                  { icon: "\u2197", tip: "Release window", act: "release" },
                  { icon: "\u21BB", tip: "Restart", act: "restart" },
                ].concat(tbar.modelData.keepAlive ? [] : [{ icon: "\u00D7", tip: "Quit", act: "quit" }])
                Rectangle {
                  id: tbtn
                  required property var modelData
                  width: 20; height: 20
                  color: tbtnHit.containsMouse || (modelData.act === "menu" && root.moreFor === tbar.menuKey)
                    ? Qt.lighter(root.titlebarColor, 1.6) : root.titlebarColor
                  Text {
                    anchors.centerIn: parent
                    text: tbtn.modelData.icon
                    color: root.titlebarText
                    font.family: "monospace"
                    font.pixelSize: 14
                  }
                  MouseArea {
                    id: tbtnHit
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                      var a = tbtn.modelData.act
                      if (a !== "menu") { root.moreFor = ""; root.run([a, panel.modelData, tbar.modelData.id]); return }
                      if (root.moreFor === tbar.menuKey) { root.moreFor = ""; return }
                      var p = tbtn.mapToItem(null, tbtn.width, tbtn.height)
                      panel.barMenuX = p.x
                      panel.barMenuY = p.y + 2
                      root.moreFor = tbar.menuKey
                    }
                  }
                }
              }
            }
          }
        }

        // The cover: the dock's background over all of it.
        Rectangle {
          anchors.fill: parent
          z: 100
          visible: panel.cover > 0
          opacity: panel.cover
          color: Commons.Color.popups.background
        }

        Rectangle {
          y: panel.usedTo
          width: parent.width
          height: Math.max(0, parent.height - panel.usedTo)
          color: Commons.Util.alpha(Commons.Color.popups.background, 0.96)
        }

        // A line along the inner edge, the dock's outline over whatever is behind.
        Rectangle {
          z: 60
          x: panel.onLeft ? parent.width - 1 : 0
          width: 1
          height: parent.height
          color: Commons.Util.alpha(root.accent, 0.5)
        }

        // The inner edge: drag to resize.
        MouseArea {
          id: resizer
          x: panel.onLeft ? parent.width - 6 : -panel.grip
          width: 6 + panel.grip
          height: parent.height
          visible: root.picking !== panel.modelData
          cursorShape: Qt.SizeHorCursor
          hoverEnabled: true
          property real startX: 0
          property int startWidth: 0
          // Across the screen, so the panel growing under the pointer doesn't matter.
          function screenX(mouse) {
            var local = mapToItem(null, mouse.x, 0).x
            return panel.onLeft ? local : local - panel.width
          }
          onPressed: mouse => {
            startX = screenX(mouse)
            startWidth = panel.fullWidth
            panel.previewWidth = startWidth
            liveSent = startWidth
            panel.dragging = true
          }
          onPositionChanged: mouse => {
            if (!pressed) return
            var dx = screenX(mouse) - startX
            panel.previewWidth = Math.max(200, panel.dock.minWidth || 0, Math.min(panel.maxWidth, Math.round(startWidth + (panel.onLeft ? dx : -dx))))
          }
          onReleased: {
            var w = panel.previewWidth
            panel.dragWidth = w
            panel.dragging = false
            if (w !== startWidth) root.run(["width", panel.modelData, String(w)])
            resizeDone.restart()
          }
          onCanceled: panel.dragging = false
          Timer { id: resizeDone; interval: 1500; onTriggered: panel.dragWidth = 0 }
          // The windows follow the drag: one quick resize at a time, the latest width.
          property int liveSent: 0
          Process { id: liveProc }
          Timer {
            interval: 40
            repeat: true
            running: panel.dragging
            onTriggered: {
              if (liveProc.running || panel.previewWidth === resizer.liveSent) return
              resizer.liveSent = panel.previewWidth
              liveProc.command = [root.tool, "width", panel.modelData, String(panel.previewWidth), "--live"]
              liveProc.running = true
            }
          }
          Rectangle {  // shown on the dock's side of the edge
            x: panel.onLeft ? 0 : panel.grip
            width: 6
            height: parent.height
            visible: parent.containsMouse || parent.pressed
            color: Commons.Util.alpha(root.accent, 0.35)
          }
        }

      }
    }

    // The apps menu: a popout by the dock's bar, at the bottom (as a start
    // menu), over everything, the dock open or not.
    PanelWindow {
      id: pickWin
      screen: panel.screen
      visible: panel.visible && root.picking === panel.modelData
      anchors { bottom: true; left: panel.onLeft; right: !panel.onLeft }
      // Out to the screen's edge and bottom: the bar beside it (the apps
      // button with it) and the gap are the menu's too, invisibly, so the
      // pointer going from the button to the menu never leaves it.
      readonly property int edgeW: Math.max(panel.barW, panel.closedW + panel.hang)
      readonly property int gap: 8
      // Small: to add an app, a search and what it finds; the settings, this
      // dock's and what goes for every dock.
      implicitWidth: Math.min(root.pickSettings ? 440 : 380, (screen ? screen.width : 1600) - panel.barW - 40) + gap + edgeW
      // (The settings: as tall as they are.)
      implicitHeight: Math.min(root.pickSettings ? setCol.implicitHeight + 20 + 28 + 8 : 460, (screen ? screen.height : 1000) - 60) + gap
      // It closes once the pointer has been off it a moment (after being on it).
      property bool hadPointer: false
      onVisibleChanged: hadPointer = false
      HoverHandler {
        id: pickHover
        onHoveredChanged: {
          if (hovered) { pickWin.hadPointer = true; pickLeave.stop() }
          else if (pickWin.hadPointer) pickLeave.restart()
        }
      }
      Timer { id: pickLeave; interval: 300; onTriggered: if (!pickHover.hovered) root.picking = "" }
      MouseArea {  // on the bar's part (the apps button's too): a click closes it
        x: panel.onLeft ? 0 : parent.width - pickWin.edgeW
        width: pickWin.edgeW
        height: parent.height
        onClicked: root.picking = ""
      }
      color: "transparent"
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.namespace: "omext-docks-apps"
      // The keyboard's from when it opens.
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
      // Add an app: installed apps and open windows. What is added stays in the
      // dock until it is removed (from its title bar's menu, or its icon's).
      Rectangle {
        id: picker
        anchors {
          fill: parent
          leftMargin: panel.onLeft ? pickWin.edgeW + pickWin.gap : 0
          rightMargin: panel.onLeft ? 0 : pickWin.edgeW + pickWin.gap
          bottomMargin: pickWin.gap
        }
        visible: pickWin.visible
        radius: 10
        color: Commons.Color.popups.background
        border.color: Commons.Util.alpha(root.accent, 0.45)
        readonly property bool settings: root.pickSettings  // the docks' settings (the gear), not adding an app (+)
        // What's typed in the search, and the parts of a name it matches.
        readonly property string needle: search.text.toLowerCase().trim()
        function esc(t) { return String(t).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;") }
        function mark(t) {  // the match in a name, in bold accent
          t = String(t || "")
          var i = needle ? t.toLowerCase().indexOf(needle) : -1
          if (i < 0) return esc(t)
          return esc(t.slice(0, i)) + "<b><font color=\"" + root.accent + "\">" + esc(t.slice(i, i + needle.length))
                 + "</font></b>" + esc(t.slice(i + needle.length))
        }
        // What can be added: open windows (not in a dock), then the installed apps.
        readonly property var others: {
          var out = []
          if (!needle || "separator".includes(needle))
            out.push({ kind: "bar", key: "separator", label: "Separator", sub: "A line between the icons", icon: "", id: "" })
          if (!root.candidates) return out
          for (var w of root.candidates.windows)
            if (!needle || (w.title + " " + w.class).toLowerCase().includes(needle))
              out.push({ kind: "window", key: "window:" + w.address, label: w.title || w.class,
                         sub: w.workspace ? "Workspace " + w.workspace : "", icon: w.icon, id: w.address })
          for (var a of root.candidates.apps)
            if (!a.docked && (!needle || a.name.toLowerCase().includes(needle)))
              out.push({ kind: "app", key: "app:" + a.desktop, label: a.name, sub: "", icon: a.icon, id: a.desktop })
          return out
        }
        // Everything shown, in order, for the keyboard: the arrow keys move the
        // cursor; Enter adds.
        readonly property var results: others
        property int cursor: -1
        onNeedleChanged: cursor = needle ? 0 : -1  // typing: the best match is ready for Enter
        readonly property string curKey: cursor >= 0 && cursor < results.length ? results[cursor].key : ""
        function moveCursor(d) {
          if (!results.length) return
          cursor = Math.max(0, Math.min(results.length - 1, cursor < 0 ? (d > 0 ? 0 : results.length - 1) : cursor + d))
          var i = cursor - (results.length - others.length)
          if (i >= 0) list.positionViewAtIndex(i, ListView.Contain)
        }
        // Opens what a row is; with Shift, outside the dock as a floating
        // window instead (a favorite that runs: its window let go).
        function activate(item, floating) {
          if (!item) return
          if (item.kind === "bar") { root.run(["add-separator", panel.modelData]); root.picking = ""; return }
          if (item.kind === "window") root.run(["add", panel.modelData, "--window", item.id])
          else root.run(floating ? ["float", item.id] : ["add", panel.modelData, item.id])
          if (item.kind === "window" || !floating) root.setOpen(panel.modelData, true)  // where it went
          root.picking = ""
        }
        onVisibleChanged: {
          cursor = -1
          if (visible) { search.text = ""; search.forceActiveFocus() }
        }



        Column {
          anchors { fill: parent; margins: 10 }
          spacing: 8
          Row {
            width: parent.width
            spacing: 6
            Text {  // in the settings: what they are
              visible: picker.settings
              width: parent.width
              height: 28
              verticalAlignment: Text.AlignVCenter
              elide: Text.ElideRight
              text: "Dock settings"
              color: Commons.Color.popups.text
              font.family: Commons.Style.font.family
              font.pixelSize: Commons.Style.font.body
              font.bold: true
            }
            Rectangle {
              visible: !picker.settings
              width: parent.width
              height: 28
              radius: 6
              color: Commons.Util.alpha(Commons.Color.foreground, 0.08)
              border.color: Commons.Util.alpha(root.accent, search.activeFocus ? 1 : 0.4)
              TextInput {
                id: search
                anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                verticalAlignment: TextInput.AlignVCenter
                color: Commons.Color.popups.text
                font.family: Commons.Style.font.family
                font.pixelSize: Commons.Style.font.body
                clip: true
                // Escape clears the search, then closes. The arrows (and Tab)
                // move through what's shown; Enter opens it.
                Keys.onEscapePressed: { if (text) text = ""; else root.picking = "" }
                Keys.onDownPressed: picker.moveCursor(1)
                Keys.onUpPressed: picker.moveCursor(-1)
                Keys.onTabPressed: picker.moveCursor(1)
                Keys.onBacktabPressed: picker.moveCursor(-1)
                Keys.onReturnPressed: e => picker.activate(picker.results[picker.cursor < 0 ? 0 : picker.cursor],
                                                           e.modifiers & Qt.ShiftModifier)
                Keys.onEnterPressed: e => picker.activate(picker.results[picker.cursor < 0 ? 0 : picker.cursor],
                                                          e.modifiers & Qt.ShiftModifier)
                Text {
                  visible: !parent.text
                  anchors.verticalCenter: parent.verticalCenter
                  text: "Add an app or an open window"
                  color: Commons.Util.alpha(Commons.Color.popups.text, 0.4)
                  font: parent.font
                }
              }
            }
          }

          // The settings: this dock's (the other's are behind its own gear; one
          // that is off has no bar, so its card is here, to switch it on), then
          // what goes for every dock.
          Flickable {
            id: setFlick
            visible: picker.settings
            width: parent.width
            height: picker.height - 20 - 28 - 8
            contentHeight: setCol.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Column {
              id: setCol
              width: parent.width
              spacing: 10

              Flow {
                width: parent.width
                spacing: 10
                Repeater {
                  model: root.docks.filter(x => x.id === panel.modelData || x.off).sort((x, y) => (x.id === panel.modelData ? 0 : 1) - (y.id === panel.modelData ? 0 : 1))
                  SettingsSection {
                    id: dcard
                    required property var modelData
                    readonly property var d: modelData
                    readonly property bool last: !d.off && root.docks.filter(x => !x.off).length < 2
                    width: setCol.width
                    title: (d.edge === "left" ? "Left" : "Right") + " dock"
                    subtitle: d.monitor || d.screen || ""
                    // On or off, top right (the last one on stays on).
                    Item {
                      width: parent.width
                      height: 1
                      Rectangle {
                        id: cardSwitch
                        readonly property bool on: !dcard.d.off
                        x: parent.width - width
                        y: -42
                        width: 30; height: 16; radius: 8
                        opacity: dcard.last ? 0.4 : 1
                        color: on ? root.accent : Commons.Util.alpha(Commons.Color.popups.text, 0.2)
                        Rectangle {
                          width: 12; height: 12; radius: 6; y: 2
                          x: cardSwitch.on ? parent.width - width - 2 : 2
                          color: cardSwitch.on ? Commons.Color.popups.background : Commons.Util.alpha(Commons.Color.popups.text, 0.6)
                        }
                        MouseArea {
                          anchors.fill: parent
                          cursorShape: dcard.last ? Qt.ArrowCursor : Qt.PointingHandCursor
                          onClicked: if (!dcard.last) root.run(["dock", dcard.d.id, cardSwitch.on ? "off" : "on"])
                        }
                      }
                    }
                    Text {
                      visible: dcard.d.off
                      width: parent.width
                      wrapMode: Text.WordWrap
                      text: "Off: no bar, and its apps open in the other dock. Switch it on to change its settings."
                      color: Commons.Util.alpha(Commons.Color.popups.text, 0.6)
                      font.family: Commons.Style.font.family
                      font.pixelSize: Commons.Style.font.bodySmall
                    }
                    Column {
                      visible: !dcard.d.off
                      width: parent.width
                      spacing: 8
                      SetRow {
                        label: "Opening apps"
                        SegPick {
                          cur: dcard.d.mode === "free" ? "free" : "single"
                          options: [{ id: "single", label: "One at a time", hint: "Opening an app puts the shown one away; it fills the dock." },
                                    { id: "free", label: "Any number", hint: "Open apps share the dock's height. Click an open app's icon to put it away." }]
                          onPicked: id => root.run(["mode", dcard.d.id, id])
                        }
                      }
                      SetRow {
                        label: "When closed"
                        SegPick {
                          cur: dcard.d.look || "hidden"
                          options: [{ id: "hidden", label: "Hidden", hint: "Nothing shows. Rest the pointer on the edge to open it." },
                                    { id: "line", label: "Line", hint: "A thin line marks the edge. Rest the pointer on it to open." },
                                    { id: "bar", label: "Bar", hint: "A slim bar that keeps its room. Rest the pointer on it to open." },
                                    { id: "slim", label: "Half icons", hint: "A slim bar, the apps' icons half out of it. Click one to open it." },
                                    { id: "icons", label: "Icons", hint: "A bar with the apps' icons. Click one to open it." }]
                          onPicked: id => root.run(["look", dcard.d.id, id])
                        }
                      }
                      SetRow {
                        label: "Icon size"
                        SegPick {
                          cur: dcard.d.iconSize === "large" ? "large" : "small"
                          options: [{ id: "small", label: "Small" }, { id: "large", label: "Large" }]
                          onPicked: id => root.run(["icon-size", dcard.d.id, id])
                        }
                      }
                      SetRow {
                        label: "Keep open"
                        SegPick {
                          cur: dcard.d.keepOpen ? "on" : "off"
                          options: [{ id: "off", label: "No", hint: "It slides away when the pointer leaves." },
                                    { id: "on", label: "Yes", hint: "It stays open; other windows make room beside it." }]
                          onPicked: id => root.run(["keep-open", dcard.d.id, id])
                        }
                      }
                      SetRow {
                        label: "Key"
                        Row {
                          spacing: 6
                          Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 150; height: 22; radius: 4
                            color: Commons.Util.alpha(Commons.Color.foreground, 0.08)
                            border.color: Commons.Util.alpha(root.accent, keyIn.activeFocus ? 1 : 0.4)
                            TextInput {
                              id: keyIn
                              anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                              verticalAlignment: TextInput.AlignVCenter
                              color: Commons.Color.popups.text
                              font.family: Commons.Style.font.family
                              font.pixelSize: Commons.Style.font.bodySmall
                              clip: true
                              text: dcard.d.key || ""
                              function apply() {
                                if (text.trim() !== (dcard.d.key || "")) root.run(["key", dcard.d.id, text.trim() || "none"])
                              }
                              Keys.onReturnPressed: { apply(); focus = false }
                              Keys.onEnterPressed: { apply(); focus = false }
                              Keys.onEscapePressed: root.picking = ""
                              onEditingFinished: apply()
                              Text {
                                visible: !parent.text
                                anchors.verticalCenter: parent.verticalCenter
                                text: "none"
                                color: Commons.Util.alpha(Commons.Color.popups.text, 0.4)
                                font: parent.font
                              }
                            }
                          }
                          Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "as SUPER + ALT + D"
                            color: Commons.Util.alpha(Commons.Color.popups.text, 0.6)
                            font.family: Commons.Style.font.family
                            font.pixelSize: Commons.Style.font.caption
                          }
                        }
                      }
                      SetRow {
                        label: "Widest"
                        Row {
                          spacing: 6
                          Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 44; height: 22; radius: 4
                            color: Commons.Util.alpha(Commons.Color.foreground, 0.08)
                            border.color: Commons.Util.alpha(root.accent, maxIn.activeFocus ? 1 : 0.4)
                            TextInput {
                              id: maxIn
                              anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                              verticalAlignment: TextInput.AlignVCenter
                              horizontalAlignment: TextInput.AlignRight
                              color: Commons.Color.popups.text
                              font.family: Commons.Style.font.family
                              font.pixelSize: Commons.Style.font.bodySmall
                              clip: true
                              validator: IntValidator { bottom: 0; top: 100 }
                              text: dcard.d.maxWidthPct ? String(dcard.d.maxWidthPct) : ""
                              function apply() {
                                var v = parseInt(text)
                                if ((v > 0 ? v : 0) !== (dcard.d.maxWidthPct || 0))
                                  root.run(["max-width", dcard.d.id, v > 0 ? String(v) : "default"])
                              }
                              Keys.onReturnPressed: { apply(); focus = false }
                              Keys.onEnterPressed: { apply(); focus = false }
                              Keys.onEscapePressed: root.picking = ""
                              onEditingFinished: apply()
                              Connections {
                                target: picker
                                function onVisibleChanged() { if (!picker.visible) maxIn.apply() }
                                function onSettingsChanged() { if (!picker.settings) maxIn.apply() }
                              }
                              Text {
                                visible: !parent.text
                                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                text: "90"
                                color: Commons.Util.alpha(Commons.Color.popups.text, 0.4)
                                font: parent.font
                              }
                            }
                          }
                          Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "% of the screen"
                            color: Commons.Util.alpha(Commons.Color.popups.text, 0.6)
                            font.family: Commons.Style.font.family
                            font.pixelSize: Commons.Style.font.caption
                          }
                        }
                      }
                    }
                  }
                }
              }

              SettingsSection {
                id: allSec
                title: "All docks"
                property bool sure: false
                Connections { target: picker; function onSettingsChanged() { allSec.sure = false } }
                SetRow {
                  label: "Icon colour"
                  SegPick {
                    cur: root.iconStyle
                    options: [{ id: "color", label: "Colour", hint: "The apps' own icons." },
                              { id: "mono", label: "Monochrome", hint: "In the theme's text colour." },
                              { id: "mixed", label: "Mixed", hint: "Monochrome until the app runs." }]
                    onPicked: id => root.run(["icon-style", id])
                  }
                }
                SetRow {
                  label: "Separators"
                  SegPick {
                    cur: root.separatorLook
                    options: [{ id: "line", label: "Line", hint: "A line between the icons." },
                              { id: "space", label: "Space", hint: "A gap between the icons, no line." }]
                    onPicked: id => root.run(["separator-look", id])
                  }
                }
                SetRow {
                  label: "Docks addon"
                  SegPick {
                    danger: true
                    cur: allSec.sure ? "off" : ""
                    options: [{ id: "off", label: allSec.sure ? "Click again to turn off" : "Turn off…",
                                hint: "Lets every docked window go, then turns the docks off. Back on: Omarchy menu › Docks, or omext-dock enable." }]
                    onPicked: {
                      if (!allSec.sure) { allSec.sure = true; return }
                      root.picking = ""
                      Quickshell.execDetached([root.tool, "disable"])
                    }
                  }
                }
              }
            }
          }
          // What can be added: open windows, then the installed apps.
          Row {
            visible: !picker.settings
            width: parent.width
            height: parent.height - y
            spacing: 10
            ListView {
              id: list
              width: parent.width
              height: parent.height
              clip: true
              spacing: 1
              model: picker.others
              section.property: "kind"
              section.delegate: Text {
                required property string section
                width: list.width
                topPadding: 6
                bottomPadding: 2
                text: section === "bar" ? "On the bar" : section === "window" ? "Open windows" : "Installed apps"
                color: Commons.Util.alpha(Commons.Color.popups.text, 0.55)
                font.family: Commons.Style.font.family
                font.pixelSize: Commons.Style.font.bodySmall
              }
              Text {  // nothing matches
                visible: !picker.results.length && !!picker.needle
                anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 12 }
                text: "Nothing matches \u201c" + search.text + "\u201d"
                color: Commons.Util.alpha(Commons.Color.popups.text, 0.5)
                font.family: Commons.Style.font.family
                font.pixelSize: Commons.Style.font.body
              }
              delegate: Rectangle {
                required property var modelData
                width: list.width
                height: 30
                radius: 5
                readonly property bool current: picker.curKey === modelData.key
                color: rowHit.containsMouse || current ? Commons.Util.alpha(root.accent, 0.25) : "transparent"
                border.color: current ? Commons.Util.alpha(root.accent, 0.7) : "transparent"
                Row {
                  anchors { left: parent.left; leftMargin: 6; verticalCenter: parent.verticalCenter }
                  spacing: 8
                  Image {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 18; height: 18
                    sourceSize: Qt.size(36, 36)
                    source: modelData.icon ? Quickshell.iconPath(modelData.icon, true) : ""
                  }
                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: list.width - 110
                    elide: Text.ElideRight
                    textFormat: Text.StyledText
                    text: picker.mark(modelData.label)
                    color: Commons.Color.popups.text
                    font.family: Commons.Style.font.family
                    font.pixelSize: Commons.Style.font.body
                  }
                }
                Text {
                  anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                  text: modelData.sub
                  color: Commons.Util.alpha(Commons.Color.popups.text, 0.45)
                  font.family: Commons.Style.font.family
                  font.pixelSize: Commons.Style.font.caption
                }
                MouseArea {
                  id: rowHit
                  anchors.fill: parent
                  hoverEnabled: true
                  onClicked: mouse => picker.activate(modelData, mouse.modifiers & Qt.ShiftModifier)
                }
              }
            }
          }
        }
      }
    }
    }
  }
}
