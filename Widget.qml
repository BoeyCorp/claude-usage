import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "boeycorp.claude-usage"

  property bool popupOpen: false
  property bool settingsMode: false
  property var draftSettings: ({})
  property string settingsStatusText: ""
  property bool refreshFlash: false
  property double nowMs: Date.now()

  readonly property color foreground: (bar && bar.foreground) ? bar.foreground : (Color.foreground || "#D8DEE9")
  readonly property color background: (Color.popups && Color.popups.background) ? Color.popups.background : "#1E1E2E"
  readonly property color border: (Color.popups && Color.popups.border) ? Color.popups.border : "#313244"
  readonly property color urgent: (bar && bar.urgent) ? bar.urgent : (Color.urgent || "#F38BA8")
  readonly property color accent: (bar && bar.accent) ? bar.accent : (Color.accent || "#89B4FA")
  readonly property color dim: Qt.darker(foreground, 1.45)
  readonly property color card: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.055)
  readonly property color cardHover: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.085)
  readonly property color outline: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.18)
  readonly property color track: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.24)
  readonly property string fontFamily: bar ? bar.fontFamily : "JetBrainsMono Nerd Font"

  readonly property var provider: usageMain.provider
  readonly property bool hasActiveSession: provider ? provider.hasActiveSession : false
  readonly property string activeStatus: provider ? provider.activeStatus : "Idle"
  readonly property bool isWorking: provider && provider.activeStatus === "Working"
  readonly property bool isWaiting: provider && (provider.activeStatus === "Waiting" || (provider.hasActiveSession && !isWorking))

  function close() {
    popupOpen = false
    settingsMode = false
  }

  function triggerPress(button) {
    if (button === Qt.RightButton) {
      openSettings()
      return
    }
    if (button === Qt.MiddleButton) {
      triggerRefresh(true)
      return
    }

    if (popupOpen) {
      popupOpen = false
    } else {
      popupOpen = true
      triggerRefresh(false)
    }
  }

  function triggerRefresh(force) {
    refreshFlash = true
    refreshFlashTimer.restart()
    usageMain.refreshAll(force === true)
  }

  function getTerminalArgs(cmdArgs, workspacePath) {
    var termSetting = (root.settings && root.settings.terminalCommand) ? String(root.settings.terminalCommand).trim() : ""
    var ws = workspacePath || ""
    if (ws.indexOf("file://") === 0) ws = decodeURIComponent(ws.substring(7))

    if (!termSetting) {
      var args = ["xdg-terminal-exec"]
      if (ws) args.push("--dir=" + ws)
      args.push("--")
      return args.concat(cmdArgs)
    }

    var parts = termSetting.split(/\s+/).filter(function(p) { return p.length > 0 })
    if (parts.length === 0) {
      var args = ["xdg-terminal-exec"]
      if (ws) args.push("--dir=" + ws)
      args.push("--")
      return args.concat(cmdArgs)
    }

    var bin = parts[0].split("/").pop()
    if (bin === "xdg-terminal-exec") {
      if (ws) parts.push("--dir=" + ws)
      parts.push("--")
      return parts.concat(cmdArgs)
    } else if (bin === "foot") {
      if (ws) parts.push("-D", ws)
      return parts.concat(cmdArgs)
    } else if (bin === "kitty") {
      if (ws) parts.push("-d", ws)
      return parts.concat(cmdArgs)
    } else if (bin === "ghostty") {
      if (ws) parts.push("--working-directory=" + ws)
      if (parts.indexOf("-e") === -1) parts.push("-e")
      return parts.concat(cmdArgs)
    } else if (bin === "alacritty") {
      if (ws) parts.push("--working-directory", ws)
      if (parts.indexOf("-e") === -1) parts.push("-e")
      return parts.concat(cmdArgs)
    } else {
      if (parts.indexOf("-e") !== -1 || parts.indexOf("--") !== -1) {
        return parts.concat(cmdArgs)
      }
      return parts.concat(["-e"]).concat(cmdArgs)
    }
  }

  function pathFromUrl(url) {
    var value = String(url || "")
    if (value.indexOf("file://") === 0)
      return decodeURIComponent(value.substring(7))
    return value
  }

  readonly property string focusScriptPath: pathFromUrl(Qt.resolvedUrl("scripts/claude_focus_or_resume.py"))

  function resumeSession(conversationId, workspacePath, title, pid) {
    if (!conversationId) return
    var termArgs = getTerminalArgs(["claude", "--resume", conversationId], workspacePath)
    var cmd = ["python3", root.focusScriptPath, "--cid", conversationId]
    if (title) cmd = cmd.concat(["--title", title])
    if (pid) cmd = cmd.concat(["--pid", String(pid)])
    cmd = cmd.concat(["--"]).concat(termArgs)
    try {
      Quickshell.execDetached(cmd)
    } catch (e) {
      console.warn("resumeSession focus fallback", e)
      try {
        Quickshell.execDetached(["uwsm-app", "--"].concat(termArgs))
      } catch (e2) {
        Quickshell.execDetached(termArgs)
      }
    }
    root.close()
  }

  function newSession() {
    var args = getTerminalArgs(["claude"], "")
    try {
      Quickshell.execDetached(["uwsm-app", "--"].concat(args))
    } catch (e) {
      Quickshell.execDetached(args)
    }
    root.close()
  }

  function killSession(conversationId) {
    if (!conversationId) return
    var scannerPath = root.provider ? root.provider.scannerScriptPath : ""
    if (scannerPath) {
      try {
        Quickshell.execDetached(["python3", scannerPath, "--kill", conversationId])
        root.triggerRefresh(false)
        killRefreshTimer.restart()
      } catch (e) {
        console.warn("claude-usage/kill", e)
      }
    }
  }

  function formatExactResetTime(resetsAt) {
    if (!resetsAt) return ""
    try {
      var d = new Date(resetsAt)
      if (isNaN(d.getTime())) return ""
      return d.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })
    } catch (e) { return "" }
  }

  function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }
  function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

  function modelColor(name) {
    var n = String(name || "").toLowerCase()
    if (n.indexOf("opus") !== -1) return "#A855F7"
    if (n.indexOf("haiku") !== -1) return "#38BDF8"
    return "#D97757"
  }

  function cloneObject(value, fallback) {
    if (value === undefined || value === null) return fallback
    try { return JSON.parse(JSON.stringify(value)) }
    catch (e) { return fallback }
  }

  function defaultSettings() {
    return {
      refreshIntervalSec: 60,
      badgeMode: "active",
      showBadge: true,
      enableQuotaAlerts: true,
      quotaAlertThreshold: 15,
      terminalCommand: "",
      recentSessionsLimit: 5
    }
  }

  function normalizedSettings(source) {
    var next = cloneObject(source, {}) || {}
    var refresh = Number(next.refreshIntervalSec === undefined || next.refreshIntervalSec === null ? 60 : next.refreshIntervalSec)
    next.refreshIntervalSec = Math.round(clamp(isFinite(refresh) ? refresh : 60, 10, 1800))

    if (next.badgeMode !== undefined && next.badgeMode !== null) {
      var bm = String(next.badgeMode).toLowerCase().trim()
      if (bm !== "active" && bm !== "prompts" && bm !== "quota" && bm !== "off") bm = "active"
      next.badgeMode = bm
      next.showBadge = bm !== "off"
    } else {
      next.showBadge = next.showBadge !== false
      next.badgeMode = next.showBadge ? "active" : "off"
    }

    next.enableQuotaAlerts = next.enableQuotaAlerts !== false
    var thresh = Number(next.quotaAlertThreshold === undefined || next.quotaAlertThreshold === null ? 15 : next.quotaAlertThreshold)
    next.quotaAlertThreshold = Math.round(clamp(isFinite(thresh) ? thresh : 15, 5, 50))

    next.terminalCommand = next.terminalCommand ? String(next.terminalCommand).trim() : ""

    var limit = Number(next.recentSessionsLimit === undefined || next.recentSessionsLimit === null ? 5 : next.recentSessionsLimit)
    next.recentSessionsLimit = Math.round(clamp(isFinite(limit) ? limit : 5, 3, 10))

    return next
  }

  function openSettings() {
    draftSettings = normalizedSettings(settings)
    settingsStatusText = ""
    settingsMode = true
    popupOpen = true
    if (root.provider) root.provider.checkHooks()
    if (flick) flick.contentY = 0
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }

  function showUsage() {
    settingsMode = false
    settingsStatusText = ""
    if (flick) flick.contentY = 0
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }

  function canPersistSettings() {
    return !!(bar && bar.shell && typeof bar.shell.updateEntryInline === "function")
  }

  function applySettings(next) {
    var n = normalizedSettings(next)
    root.settings = n
    root.draftSettings = n
  }

  function broadcastSettings(next) {
    var items = bar && typeof bar.moduleWidgets === "function"
      ? bar.moduleWidgets(moduleName) : [root]
    for (var i = 0; i < items.length; i++) {
      if (items[i] && items[i] !== root && typeof items[i].applySettings === "function") {
        items[i].applySettings(next)
      }
    }
  }

  function persistSettings(values) {
    var current = normalizedSettings(root.settings)
    var merged = cloneObject(current, {}) || {}
    if (values) {
      for (var k in values) {
        merged[k] = values[k]
      }
    }
    var next = normalizedSettings(merged)
    applySettings(next)
    broadcastSettings(next)
    if (canPersistSettings()) {
      bar.shell.updateEntryInline(root.moduleName, next)
      settingsStatusText = "Saved to shell.json"
    } else {
      settingsStatusText = "Saved for this session"
    }
  }

  function saveSettings() {
    persistSettings(draftSettings)
    usageMain.refreshAll(true)
  }

  function draftValue(name, fallback) {
    var value = draftSettings ? draftSettings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function setDraftOnly(name, value) {
    var next = normalizedSettings(draftSettings)
    next[name] = value
    draftSettings = next
  }

  function setDraftValue(name, value) {
    updateSetting(name, value)
  }

  function updateSetting(name, value) {
    var next = normalizedSettings(draftSettings)
    next[name] = value
    if (name === "badgeMode") {
      var bm = String(value).toLowerCase().trim()
      if (bm !== "active" && bm !== "prompts" && bm !== "quota" && bm !== "off") bm = "active"
      next.badgeMode = bm
      next.showBadge = bm !== "off"
    } else if (name === "showBadge") {
      var sb = Boolean(value)
      next.showBadge = sb
      next.badgeMode = sb ? (next.badgeMode === "off" ? "active" : next.badgeMode) : "off"
    }
    next = normalizedSettings(next)
    draftSettings = next
    persistSettings(next)
  }

  readonly property bool isLightTheme: {
    var fg = root.foreground
    var bg = (bar && bar.background) ? bar.background : Color.background
    var fgLum = 0.299 * fg.r + 0.587 * fg.g + 0.114 * fg.b
    var bgLum = 0.299 * bg.r + 0.587 * bg.g + 0.114 * bg.b
    return bgLum > 0.5 || fgLum < 0.5
  }

  readonly property url iconSource: Qt.resolvedUrl(isLightTheme ? "assets/claude-light.svg" : "assets/claude.svg")

  function getIconSource() {
    return root.iconSource
  }

  function formatCountdown(resetsAt) {
    if (!resetsAt) return ""
    var ms = new Date(resetsAt).getTime()
    if (!isFinite(ms)) return ""
    var diff = ms - root.nowMs
    if (diff <= 0) return "now"
    var minutes = Math.floor(diff / 60000)
    var hours = Math.floor(minutes / 60)
    var days = Math.floor(hours / 24)
    if (days > 0) return "Resets in " + days + "d " + (hours % 24) + "h"
    if (hours > 0) return "Resets in " + hours + "h " + (minutes % 60) + "m"
    return "Resets in " + Math.max(1, minutes) + "m"
  }

  function tooltipText() {
    if (!provider) return "Claude Usage"
    var count = provider.activeSessions ? provider.activeSessions.length : (provider.hasActiveSession ? 1 : 0)
    var status = provider.hasActiveSession ? " (" + count + " " + (count === 1 ? "session" : "sessions") + " " + provider.activeStatus.toLowerCase() + ")" : " (Idle)"
    var refMs = (provider && provider.lastFullRefreshMs > 0) ? provider.lastFullRefreshMs : (provider ? provider.lastUpdatedMs : 0)
    var ageSec = refMs > 0 ? Math.max(0, Math.floor((root.nowMs - refMs) / 1000)) : -1
    var refText = ""
    if (ageSec >= 0) {
      if (ageSec < 10) refText = " • Refreshed just now"
      else if (ageSec < 60) refText = " • Refreshed " + ageSec + "s ago"
      else if (ageSec < 3600) refText = " • Refreshed " + Math.floor(ageSec / 60) + "m ago"
      else refText = " • Refreshed " + Math.floor(ageSec / 3600) + "h ago"
    }
    return "Claude Code" + status + "\n" + (provider.todayPrompts || 0) + " prompts today" + refText
  }

  width: button.implicitWidth
  height: button.implicitHeight
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onPopupOpenChanged: {
    if (popupOpen) {
      root.nowMs = Date.now()
      Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
    }
  }

  Timer {
    id: liveClockTimer
    interval: 1000
    running: root.popupOpen
    repeat: true
    onTriggered: root.nowMs = Date.now()
  }

  Main {
    id: usageMain
    settings: root.settings
  }

  Timer {
    id: refreshFlashTimer
    interval: 800
    repeat: false
    onTriggered: root.refreshFlash = false
  }

  Timer {
    id: killRefreshTimer
    interval: 350
    repeat: false
    onTriggered: root.triggerRefresh(false)
  }

  IpcHandler {
    target: "boeycorp.claude-usage"
    function open(): string { root.showUsage(); root.popupOpen = true; return "ok" }
    function close(): string { root.close(); return "ok" }
    function toggle(): string {
      if (root.popupOpen) root.close()
      else { root.showUsage(); root.popupOpen = true }
      return "ok"
    }
    function refresh(): string { root.triggerRefresh(); return "ok" }
    function settings(): string { root.openSettings(); return "ok" }
    function openSettings(): string { root.openSettings(); return "ok" }
    function setBadgeMode(mode: string): string { root.updateSetting("badgeMode", mode); return "ok" }
  }

  component UsageChip: Item {
    id: chip

    readonly property bool tooltipHovered: mouseArea.containsMouse
    readonly property string badgeMode: {
      if (root.settings && root.settings.badgeMode !== undefined && root.settings.badgeMode !== null)
        return String(root.settings.badgeMode).toLowerCase()
      if (root.settings && root.settings.showBadge === false)
        return "off"
      return "active"
    }
    readonly property int activeCount: {
      if (!provider) return 0
      if (provider.activeSessions && Array.isArray(provider.activeSessions))
        return provider.activeSessions.length
      return provider.hasActiveSession ? 1 : 0
    }
    readonly property int lowestQuotaPercent: {
      if (!provider || !provider.quotaGroups) return 100
      var lowest = 100
      var found = false
      for (var i = 0; i < provider.quotaGroups.length; i++) {
        var g = provider.quotaGroups[i]
        var buckets = g.buckets || []
        for (var j = 0; j < buckets.length; j++) {
          var rem = buckets[j].remainingPercent
          if (rem !== undefined && rem !== null) {
            found = true
            if (rem < lowest) lowest = rem
          }
        }
      }
      return found ? lowest : 100
    }
    readonly property int promptCount: provider ? (provider.todayPrompts || 0) : 0
    readonly property int badgeCount: badgeMode === "prompts" ? promptCount : (badgeMode === "active" ? activeCount : 0)
    readonly property bool hasBadge: {
      if (badgeMode === "off") return false
      if (badgeMode === "prompts") return true
      if (badgeMode === "active") return activeCount > 0
      if (badgeMode === "quota") return true
      return false
    }

    width: hasBadge ? (13 + badgeText.implicitWidth + 10) : root.barSize
    height: root.barSize

    RowLayout {
      anchors.centerIn: parent
      spacing: 4

      Item {
        id: iconBox
        width: 13
        height: 13

        Image {
          id: barIconImage
          source: root.iconSource
          width: 12
          height: 12
          sourceSize.width: Math.round(12 * (Screen.devicePixelRatio || 1))
          sourceSize.height: Math.round(12 * (Screen.devicePixelRatio || 1))
          fillMode: Image.PreserveAspectFit
          anchors.centerIn: parent
          visible: false
          layer.enabled: true
        }

        MultiEffect {
          anchors.fill: barIconImage
          source: barIconImage
          colorization: 1.0
          colorizationColor: root.foreground
        }

        // Active pulse glow
        Rectangle {
          width: 4
          height: 4
          radius: 2
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          anchors.margins: -1
          color: root.isWorking ? "#10B981" : (root.isWaiting ? "#3B82F6" : "transparent")
          visible: root.hasActiveSession

          SequentialAnimation on opacity {
            running: root.isWorking
            loops: Animation.Infinite
            NumberAnimation { from: 0.3; to: 1.0; duration: 600; easing.type: Easing.InOutQuad }
            NumberAnimation { from: 1.0; to: 0.3; duration: 600; easing.type: Easing.InOutQuad }
          }
        }
      }

      Text {
        id: badgeText
        visible: chip.hasBadge
        textFormat: Text.PlainText
        text: chip.badgeMode === "quota" ? (chip.lowestQuotaPercent + "%") : String(chip.badgeCount)
        color: chip.badgeMode === "quota" ? (chip.lowestQuotaPercent <= 15 ? root.urgent : (chip.lowestQuotaPercent <= 30 ? "#F59E0B" : root.accent)) : (root.isWorking ? "#10B981" : (root.isWaiting ? "#3B82F6" : root.dim))
        font.family: root.fontFamily
        font.pixelSize: 9
        font.bold: true
        Layout.alignment: Qt.AlignVCenter
      }
    }

    property var registeredBar: null

    function triggerPress(button) { root.triggerPress(button) }

    function syncClickRegistration() {
      if (registeredBar && registeredBar.unregisterClickTarget) registeredBar.unregisterClickTarget(chip)
      registeredBar = root.bar
      if (registeredBar && registeredBar.registerClickTarget) registeredBar.registerClickTarget(chip)
    }

    Component.onCompleted: syncClickRegistration()
    Component.onDestruction: if (registeredBar && registeredBar.unregisterClickTarget) registeredBar.unregisterClickTarget(chip)

    Connections {
      target: root
      function onBarChanged() { chip.syncClickRegistration() }
    }

    MouseArea {
      id: mouseArea
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: if (root.bar) root.bar.showTooltip(chip, root.tooltipText())
      onExited: if (root.bar) root.bar.hideTooltip(chip)
      onClicked: function(mouse) { root.triggerPress(mouse.button) }
    }
  }

  Item {
    id: button
    anchors.fill: parent
    implicitWidth: usageChip.width
    implicitHeight: root.barSize

    UsageChip {
      id: usageChip
      anchors.centerIn: parent
    }
  }

  // ------------------------------------------------------------- Popup Dialog
  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.popupOpen
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(450))
    contentHeight: {
      var headerH = (root.settingsMode ? settingsHeader.implicitHeight : statsHeader.implicitHeight) + panelSeparator.implicitHeight + 16
      var needed = headerH + contentColumn.implicitHeight + Style.space(12)
      return panel.fittedContentHeight(needed, Style.space(760))
    }

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: settingsMode && settingsContent.editorActive

      onMoveRequested: function(dx, dy) {
        if (dy !== 0) flick.contentY = root.clamp(flick.contentY + dy * 56, 0, Math.max(0, flick.contentHeight - flick.height))
      }
      onCloseRequested: root.close()
      onTextKey: function(t) {
        if (t === "r" || t === "R") root.triggerRefresh(true)
        else if (t === "s" || t === "S") root.settingsMode ? root.saveSettings() : root.openSettings()
        else if (t === "n" || t === "N") { if (!root.settingsMode) root.newSession() }
        else if (t === "q" || t === "Q") root.close()
        else if (!root.settingsMode && t >= "1" && t <= "5") {
          var idx = parseInt(t) - 1
          var list = root.provider ? (root.provider.recentSessions || []) : []
          if (idx >= 0 && idx < list.length) {
            var s = list[idx]
            root.resumeSession(s.conversationId, s.workspace)
          }
        }
      }

      ColumnLayout {
        id: panelMainColumn
        anchors.fill: parent
        spacing: 8

        Header {
          id: statsHeader
          visible: !root.settingsMode && !!root.provider
          provider: root.provider
        }

        SettingsHeader {
          id: settingsHeader
          visible: root.settingsMode
        }

        PanelSeparator {
          id: panelSeparator
          Layout.fillWidth: true
          foreground: root.foreground

          Item {
            anchors.fill: parent
            clip: true
            visible: usageMain.refreshing

            Rectangle {
              id: loadingGlow
              anchors.verticalCenter: parent.verticalCenter
              height: 2
              width: Math.max(60, panelSeparator.width * 0.35)
              radius: 1
              color: root.accent

              NumberAnimation on x {
                loops: Animation.Infinite
                running: root.popupOpen && usageMain.refreshing
                from: -loadingGlow.width
                to: panelSeparator.width
                duration: 800
                easing.type: Easing.InOutQuad
              }
            }
          }
        }

        Flickable {
          id: flick
          Layout.fillWidth: true
          Layout.fillHeight: true
          contentWidth: width
          contentHeight: contentColumn.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          flickableDirection: Flickable.VerticalFlick
          ScrollBar.vertical: ScrollBar {
            policy: flick.contentHeight > (flick.height + 2) ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
          }

          ColumnLayout {
            id: contentColumn
            width: flick.width
            spacing: 8

            SkeletonContent {
              visible: !root.settingsMode && usageMain.refreshing && (!root.provider || !root.provider.ready || !root.provider.hasLocalStats)
            }

            Text {
              textFormat: Text.PlainText
              visible: !root.settingsMode && (!root.provider || !root.provider.hasLocalStats) && !usageMain.refreshing
              Layout.fillWidth: true
              Layout.topMargin: 24
              text: "No Claude Code sessions found. Run `claude` to start."
              color: dim
              font.family: fontFamily
              font.pixelSize: 11
              horizontalAlignment: Text.AlignHCenter
            }

            StatusCard { provider: root.settingsMode ? null : root.provider }
            TodayCard { provider: root.settingsMode ? null : root.provider }
            QuotaLimitsCard { provider: root.settingsMode ? null : root.provider }
            ModelUsageCard { provider: root.settingsMode ? null : root.provider }
            WeekCard { provider: root.settingsMode ? null : root.provider }
            ToolsCard { provider: root.settingsMode ? null : root.provider }
            RecentSessionsCard { provider: root.settingsMode ? null : root.provider }

            UsageFooter {
              visible: !root.settingsMode && (root.provider && root.provider.ready && root.provider.hasLocalStats)
            }
            SettingsContent {
              id: settingsContent
              visible: root.settingsMode
            }
          }
        }
      }
    }
  }

  // --------------------------------------------------------- Components
  component Header: RowLayout {
    property var provider: null
    visible: !!provider
    Layout.fillWidth: true
    spacing: 8

    Item {
      Layout.preferredWidth: 18
      Layout.preferredHeight: 18
      Layout.alignment: Qt.AlignVCenter

      Image {
        id: headerIconImage
        source: root.iconSource
        anchors.fill: parent
        sourceSize.width: Math.round(18 * (Screen.devicePixelRatio || 1))
        sourceSize.height: Math.round(18 * (Screen.devicePixelRatio || 1))
        fillMode: Image.PreserveAspectFit
        visible: false
        layer.enabled: true
      }

      MultiEffect {
        anchors.fill: headerIconImage
        source: headerIconImage
        colorization: 1.0
        colorizationColor: root.foreground
      }
    }

    ColumnLayout {
      Layout.fillWidth: true
      spacing: 1

      RowLayout {
        Layout.fillWidth: true
        spacing: 6

        Text {
          textFormat: Text.PlainText
          text: "Claude Code"
          color: foreground
          font.family: fontFamily
          font.pixelSize: Style.font.title
          font.bold: true
          elide: Text.ElideRight
          Layout.maximumWidth: 180
        }

        Rectangle {
          visible: root.hasActiveSession
          color: root.activeStatus === "Working" ? "#10B981" : "#3B82F6"
          radius: 3
          Layout.preferredHeight: 14
          Layout.preferredWidth: activeLabel.implicitWidth + 8

          Text {
            id: activeLabel
            textFormat: Text.PlainText
            text: root.activeStatus
            color: "#FFFFFF"
            font.family: fontFamily
            font.pixelSize: 9
            font.bold: true
            anchors.centerIn: parent
          }
        }
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: 6

        Text {
          textFormat: Text.PlainText
          text: provider ? (provider.usageStatusText || "Idle") : "Idle"
          color: dim
          font.family: fontFamily
          font.pixelSize: 10
          elide: Text.ElideRight
          Layout.fillWidth: true
        }

        RowLayout {
          id: refAgeRow
          spacing: 3
          readonly property double refMs: (provider && provider.lastFullRefreshMs > 0) ? provider.lastFullRefreshMs : (provider ? provider.lastUpdatedMs : 0)
          readonly property int ageSec: refMs > 0 ? Math.max(0, Math.floor((root.nowMs - refMs) / 1000)) : -1
          visible: !usageMain.refreshing && refMs > 0

          Text {
            textFormat: Text.PlainText
            text: ""
            color: refAgeRow.ageSec > 300 ? root.urgent : dim
            font.family: root.fontFamily
            font.pixelSize: 8
            opacity: 0.7
          }

          Text {
            textFormat: Text.PlainText
            text: {
              var a = refAgeRow.ageSec
              if (a < 0) return ""
              if (a < 10) return "Refreshed just now"
              if (a < 60) return "Refreshed " + a + "s ago"
              if (a < 3600) return "Refreshed " + Math.floor(a / 60) + "m ago"
              return "Refreshed " + Math.floor(a / 3600) + "h " + Math.floor((a % 3600) / 60) + "m ago"
            }
            color: refAgeRow.ageSec > 300 ? root.urgent : dim
            font.family: fontFamily
            font.pixelSize: 9
            opacity: 0.8
          }
        }

        RowLayout {
          spacing: 3
          visible: usageMain.refreshing

          Text {
            textFormat: Text.PlainText
            text: ""
            color: root.accent
            font.family: root.fontFamily
            font.pixelSize: 8
            transformOrigin: Item.Center

            RotationAnimation on rotation {
              running: usageMain.refreshing
              loops: Animation.Infinite
              from: 0
              to: 360
              duration: 800
            }
          }

          Text {
            textFormat: Text.PlainText
            text: "Refreshing…"
            color: root.accent
            font.family: fontFamily
            font.pixelSize: 9
            opacity: 0.9
          }
        }
      }
    }

    // Compact Action Icons
    RowLayout {
      spacing: 4
      Layout.alignment: Qt.AlignVCenter

      Button {
        text: ""
        foreground: root.foreground
        tooltipText: "New session (n)"
        tooltipBackground: root.background
        tooltipForeground: root.foreground
        fontFamily: root.fontFamily
        fontSize: 11
        horizontalPadding: 6
        verticalPadding: 4
        onClicked: root.newSession()
      }

      Button {
        iconText: ""
        iconSpinning: root.refreshFlash || usageMain.refreshing
        foreground: (root.refreshFlash || usageMain.refreshing) ? root.accent : root.foreground
        tooltipText: "Refresh (r)"
        tooltipBackground: root.background
        tooltipForeground: root.foreground
        fontFamily: root.fontFamily
        iconSize: 11
        horizontalPadding: 6
        verticalPadding: 4
        active: root.refreshFlash || usageMain.refreshing
        onClicked: {
          root.triggerRefresh(true)
          keyCatcher.forceActiveFocus()
        }
      }

      Button {
        text: ""
        foreground: root.foreground
        tooltipText: "Settings (s)"
        tooltipBackground: root.background
        tooltipForeground: root.foreground
        fontFamily: root.fontFamily
        fontSize: 11
        horizontalPadding: 6
        verticalPadding: 4
        onClicked: root.openSettings()
      }
    }
  }

  component SettingsHeader: RowLayout {
    Layout.fillWidth: true
    spacing: 8

    Text {
      textFormat: Text.PlainText
      text: "Claude Usage Settings"
      color: foreground
      font.family: fontFamily
      font.pixelSize: Style.font.title
      font.bold: true
      Layout.fillWidth: true
      Layout.alignment: Qt.AlignVCenter
    }

    Button {
      text: "Usage"
      foreground: root.foreground
      tooltipText: "Back to usage"
      tooltipBackground: root.background
      tooltipForeground: root.foreground
      fontFamily: root.fontFamily
      fontSize: 10
      horizontalPadding: 8
      verticalPadding: 4
      onClicked: root.showUsage()
    }

    Button {
      text: "Save"
      foreground: root.foreground
      tooltipText: "Save settings"
      tooltipBackground: root.background
      tooltipForeground: root.foreground
      fontFamily: root.fontFamily
      fontSize: 10
      horizontalPadding: 8
      verticalPadding: 4
      active: true
      onClicked: root.saveSettings()
    }
  }

  component SkeletonBlock: Rectangle {
    id: skel
    property real baseOpacity: 0.10
    radius: 4
    color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, baseOpacity)

    SequentialAnimation on opacity {
      loops: Animation.Infinite
      running: root.popupOpen
      NumberAnimation { from: 0.4; to: 0.85; duration: 800; easing.type: Easing.InOutQuad }
      NumberAnimation { from: 0.85; to: 0.4; duration: 800; easing.type: Easing.InOutQuad }
    }
  }

  component SkeletonContent: ColumnLayout {
    Layout.fillWidth: true
    spacing: 8

    // TodayCard Skeleton
    SectionCard {
      title: "Today & Totals"
      RowLayout {
        width: parent.width
        spacing: Style.space(8)
        Repeater {
          model: 3
          delegate: ColumnLayout {
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            spacing: 4
            SkeletonBlock {
              Layout.fillWidth: true
              Layout.preferredHeight: 28
              radius: 4
            }
            SkeletonBlock {
              Layout.fillWidth: true
              Layout.preferredHeight: 10
              radius: 3
            }
          }
        }
      }
    }

    // QuotaLimitsCard Skeleton
    SectionCard {
      title: "Quota Limits"
      ColumnLayout {
        width: parent.width
        spacing: 8
        Repeater {
          model: 2
          delegate: ColumnLayout {
            Layout.fillWidth: true
            spacing: 5
            RowLayout {
              Layout.fillWidth: true
              SkeletonBlock {
                Layout.preferredWidth: 90
                Layout.preferredHeight: 11
              }
              Item { Layout.fillWidth: true }
              SkeletonBlock {
                Layout.preferredWidth: 45
                Layout.preferredHeight: 11
              }
            }
            SkeletonBlock {
              Layout.fillWidth: true
              Layout.preferredHeight: 6
              radius: 3
            }
          }
        }
      }
    }

    // RecentSessionsCard Skeleton
    SectionCard {
      title: "Recent Sessions"
      ColumnLayout {
        width: parent.width
        spacing: 8
        Repeater {
          model: 3
          delegate: RowLayout {
            Layout.fillWidth: true
            spacing: 8
            SkeletonBlock {
              Layout.preferredWidth: 14
              Layout.preferredHeight: 14
              radius: 7
            }
            ColumnLayout {
              Layout.fillWidth: true
              spacing: 4
              SkeletonBlock {
                Layout.fillWidth: true
                Layout.preferredHeight: 12
              }
              SkeletonBlock {
                Layout.preferredWidth: 130
                Layout.preferredHeight: 10
              }
            }
          }
        }
      }
    }
  }

  component StatusCard: SectionCard {
    property var provider: null
    visible: !!provider && String(provider.authHelpText || "") !== ""
    titleColor: urgent
    title: provider ? (provider.usageStatusText || "Status") : ""
    subtitle: provider ? provider.authHelpText : ""
  }

  component TodayCard: SectionCard {
    property var provider: null
    visible: !!provider && provider.ready && provider.hasLocalStats
    title: "Today & Totals"

    ColumnLayout {
      width: parent.width
      spacing: Style.space(6)

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.space(8)

        StatBlock {
          Layout.fillWidth: true
          Layout.preferredWidth: 1
          value: provider ? String(provider.todayPrompts || 0) : "0"
          label: "prompts today"
        }
        StatBlock {
          Layout.fillWidth: true
          Layout.preferredWidth: 1
          value: provider ? String(provider.todaySteps || 0) : "0"
          label: "steps today"
        }
        StatBlock {
          Layout.fillWidth: true
          Layout.preferredWidth: 1
          value: provider ? usageMain.formatNumber(provider.todayTotalTokens || 0) : "0"
          label: "tokens today"
        }
        StatBlock {
          Layout.fillWidth: true
          Layout.preferredWidth: 1
          value: provider ? String(provider.totalPrompts || 0) : "0"
          label: "total prompts"
        }
      }

      Rectangle {
        visible: !!provider && (provider.todayCacheReadTokens > 0 || provider.todayCacheHitRate > 0)
        Layout.fillWidth: true
        Layout.preferredHeight: 22
        radius: 4
        color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.08)
        border.color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.22)
        border.width: 1

        RowLayout {
          anchors.fill: parent
          anchors.leftMargin: 8
          anchors.rightMargin: 8
          spacing: 6

          Text {
            textFormat: Text.PlainText
            text: "⚡ Prompt Cache:"
            color: root.accent
            font.family: root.fontFamily
            font.pixelSize: 10
            font.bold: true
          }

          Text {
            textFormat: Text.PlainText
            text: (provider ? (provider.todayCacheHitRate || 0) : 0) + "% hit rate"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: 10
            font.bold: true
          }

          Text {
            textFormat: Text.PlainText
            text: "·"
            color: root.dim
            font.pixelSize: 9
          }

          Text {
            textFormat: Text.PlainText
            text: "Saved " + usageMain.formatNumber(provider ? (provider.todayCacheReadTokens || 0) : 0) + " cached tokens"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: 10
            Layout.fillWidth: true
            elide: Text.ElideRight
          }
        }
      }
    }
  }

  component QuotaLimitsCard: SectionCard {
    property var provider: null
    visible: !!provider && provider.quotaGroups && provider.quotaGroups.length > 0
    title: "Quota Limits"

    ColumnLayout {
      width: parent.width
      spacing: 8

      Repeater {
        model: provider ? (provider.quotaGroups || []) : []
        delegate: ColumnLayout {
          required property var modelData
          Layout.fillWidth: true
          spacing: 4

          RowLayout {
            Layout.fillWidth: true
            spacing: 5

            Rectangle {
              width: 6
              height: 6
              radius: 3
              color: root.modelColor(modelData.name)
            }

            Text {
              textFormat: Text.PlainText
              text: modelData.name || "Group"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: 10
              font.bold: true
              Layout.fillWidth: true
            }
          }

          Repeater {
            model: modelData.buckets || []
            delegate: ColumnLayout {
              required property var modelData
              Layout.fillWidth: true
              spacing: 2

              RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Text {
                  textFormat: Text.PlainText
                  text: modelData.label || modelData.name || "Limit"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: 10
                  Layout.fillWidth: true
                  elide: Text.ElideRight
                }

                Text {
                  textFormat: Text.PlainText
                  readonly property string exact: root.formatExactResetTime(modelData.resetTime || modelData.reset_time)
                  text: {
                    var cd = root.formatCountdown(modelData.resetTime || modelData.reset_time)
                    return exact ? (cd + " · " + exact) : cd
                  }
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: 9
                  font.bold: true
                }

                Text {
                  textFormat: Text.PlainText
                  readonly property real pct: Number(modelData.remainingPercent !== undefined ? modelData.remainingPercent : ((modelData.remainingFraction || 0) * 100))
                  text: Math.round(pct) + "% remaining"
                  color: pct <= 15 ? (bar ? bar.urgent : Color.urgent) : (pct <= 30 ? "#F59E0B" : root.foreground)
                  font.family: root.fontFamily
                  font.pixelSize: 9
                  font.bold: true
                }
              }

              Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 7
                color: root.track
                radius: 2
                clip: true

                readonly property real frac: Math.min(1.0, Math.max(0.0, Number(modelData.remainingFraction !== undefined ? modelData.remainingFraction : (modelData.remaining_fraction || 0))))

                Rectangle {
                  anchors.left: parent.left
                  anchors.top: parent.top
                  anchors.bottom: parent.bottom
                  width: parent.width * parent.frac
                  color: {
                    if (parent.frac <= 0.15 || modelData.forecastStatus === "critical") return bar ? bar.urgent : Color.urgent
                    if (parent.frac <= 0.30 || modelData.forecastStatus === "warning") return "#F59E0B"
                    return modelData.color || root.modelColor(modelData.name)
                  }
                  radius: 2
                  Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                }
              }

              RowLayout {
                visible: !!(modelData.forecastText && modelData.forecastText !== "")
                Layout.fillWidth: true
                spacing: 4

                Text {
                  textFormat: Text.PlainText
                  readonly property string burnStr: modelData.burnRateText ? ("🔥 " + modelData.burnRateText + " · ") : ""
                  text: burnStr + (modelData.forecastText || "")
                  color: {
                    if (modelData.forecastStatus === "critical") return bar ? bar.urgent : Color.urgent
                    if (modelData.forecastStatus === "warning") return "#F59E0B"
                    if (modelData.forecastStatus === "safe") return "#10B981"
                    return root.dim
                  }
                  font.family: root.fontFamily
                  font.pixelSize: 8
                  font.bold: modelData.forecastStatus === "critical" || modelData.forecastStatus === "warning"
                  elide: Text.ElideRight
                  Layout.fillWidth: true
                }
              }
            }
          }
        }
      }
    }
  }

  component ModelUsageCard: SectionCard {
    id: modelCardRoot
    property var provider: null
    property string timeRange: "today" // "today" | "week" | "all"
    visible: !!provider && ((provider.modelList && provider.modelList.length > 0) || (provider.modelUsage && Object.keys(provider.modelUsage).length > 0))
    title: "Model Usage Breakdown"

    headerAccessory: Component {
      Rectangle {
        color: root.track
        radius: 3
        implicitHeight: 18
        implicitWidth: toggleRow.implicitWidth + 4
        border.color: root.outline
        border.width: 1

        RowLayout {
          id: toggleRow
          anchors.centerIn: parent
          spacing: 1

          Repeater {
            model: [
              { key: "today", label: "Today" },
              { key: "week", label: "Last 7 Days" },
              { key: "all", label: "All time" }
            ]

            delegate: Rectangle {
              required property var modelData
              readonly property bool isSelected: modelCardRoot.timeRange === modelData.key
              radius: 2
              implicitHeight: 14
              implicitWidth: optText.implicitWidth + 8
              color: isSelected ? root.accent : (optMouse.containsMouse ? root.cardHover : "transparent")

              Behavior on color { ColorAnimation { duration: 100 } }

              Text {
                id: optText
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: modelData.label
                color: isSelected ? "#FFFFFF" : (optMouse.containsMouse ? root.foreground : root.dim)
                font.family: root.fontFamily
                font.pixelSize: 9
                font.bold: isSelected
              }

              MouseArea {
                id: optMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: modelCardRoot.timeRange = modelData.key
              }
            }
          }
        }
      }
    }

    readonly property var rawModelList: {
      if (provider && provider.modelList && provider.modelList.length > 0)
        return provider.modelList
      var usage = provider ? (provider.modelUsage || {}) : {}
      var res = []
      for (var k in usage) res.push(usage[k])
      return res
    }

    function getPrompts(m, range) {
      if (!m) return 0
      if (range === "today") return Number(m.todayPrompts || 0)
      if (range === "week") return Number(m.weekPrompts || 0)
      return Number(m.prompts || 0)
    }

    function getSteps(m, range) {
      if (!m) return 0
      if (range === "today") return Number(m.todaySteps || 0)
      if (range === "week") return Number(m.weekSteps || 0)
      return Number(m.steps || 0)
    }

    readonly property real totalPromptsForRange: {
      var list = rawModelList
      var sum = 0
      for (var i = 0; i < list.length; i++) {
        sum += getPrompts(list[i], timeRange)
      }
      return sum
    }

    readonly property real totalStepsForRange: {
      var list = rawModelList
      var sum = 0
      for (var i = 0; i < list.length; i++) {
        sum += getSteps(list[i], timeRange)
      }
      return sum
    }

    readonly property var displayModelList: {
      var list = rawModelList.slice()
      list.sort(function(a, b) {
        var aP = getPrompts(a, timeRange)
        var bP = getPrompts(b, timeRange)
        var aS = getSteps(a, timeRange)
        var bS = getSteps(b, timeRange)
        var aScore = aP * 10000 + aS
        var bScore = bP * 10000 + bS
        if (bScore !== aScore) return bScore - aScore
        return (Number(b.prompts || 0)) - (Number(a.prompts || 0))
      })
      return list
    }

    ColumnLayout {
      width: parent.width
      spacing: 6

      Text {
        visible: modelCardRoot.totalPromptsForRange === 0 && modelCardRoot.totalStepsForRange === 0
        textFormat: Text.PlainText
        text: modelCardRoot.timeRange === "today"
          ? "No prompts recorded yet today"
          : (modelCardRoot.timeRange === "week" ? "No prompts recorded in the last 7 days" : "No model activity recorded")
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: 9
        Layout.alignment: Qt.AlignHCenter
        Layout.topMargin: 2
        Layout.bottomMargin: 2
      }

      Repeater {
        model: modelCardRoot.displayModelList
        delegate: ColumnLayout {
          required property var modelData
          Layout.fillWidth: true
          spacing: 2

          readonly property int pCount: modelCardRoot.getPrompts(modelData, modelCardRoot.timeRange)
          readonly property int sCount: modelCardRoot.getSteps(modelData, modelCardRoot.timeRange)
          readonly property real shareFrac: modelCardRoot.totalPromptsForRange > 0
            ? (pCount / modelCardRoot.totalPromptsForRange)
            : (modelCardRoot.totalStepsForRange > 0 ? (sCount / modelCardRoot.totalStepsForRange) : 0)
          readonly property real sharePct: Math.round(shareFrac * 100)

          RowLayout {
            Layout.fillWidth: true
            spacing: 6

            Text {
              textFormat: Text.PlainText
              text: modelData.name || "Model"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: 10
              font.bold: true
              elide: Text.ElideRight
              Layout.fillWidth: true
            }

            Text {
              textFormat: Text.PlainText
              text: {
                var p = pCount
                var s = sCount
                var sFmt = s >= 1000 ? (s / 1000).toFixed(1) + "k" : String(s)
                var tok = Number(modelData.todayTokens || 0)
                var tFmt = tok > 0 ? (" · " + usageMain.formatNumber(tok) + " tok") : ""
                return p + " prompts · " + sFmt + " steps" + tFmt
              }
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: 9
            }

            Text {
              textFormat: Text.PlainText
              text: (modelCardRoot.totalPromptsForRange > 0 || modelCardRoot.totalStepsForRange > 0) ? (sharePct + "%") : "0%"
              color: pCount > 0 ? root.foreground : root.dim
              font.family: root.fontFamily
              font.pixelSize: 9
              font.bold: true
            }
          }

          Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 6
            color: root.track
            radius: 2
            clip: true

            Rectangle {
              anchors.left: parent.left
              anchors.top: parent.top
              anchors.bottom: parent.bottom
              width: parent.width * Math.min(1.0, Math.max(0.0, shareFrac))
              color: modelData.color || root.modelColor(modelData.name)
              radius: 2
              Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
            }
          }
        }
      }
    }
  }

  component WeekCard: SectionCard {
    id: weekCardRoot
    property var provider: null
    visible: !!provider && provider.recentDays && provider.recentDays.length > 0
               && provider.recentDays.some(function(d) { return d.messageCount > 0 })
    title: "Last 7 Days Activity"

    readonly property real maxCount: {
      var days = provider ? (provider.recentDays || []) : []
      var m = 1
      for (var i = 0; i < days.length; i++) {
        var val = Number(days[i].messageCount || days[i].prompts || 0)
        if (val > m) m = val
      }
      return m
    }

    ColumnLayout {
      width: parent.width
      spacing: 5

      Repeater {
        model: provider ? provider.recentDays : []
        delegate: RowLayout {
          required property var modelData
          Layout.fillWidth: true
          spacing: 6
          readonly property real count: modelData ? Number(modelData.messageCount || modelData.prompts || 0) : 0

          Text {
            textFormat: Text.PlainText
            text: {
              var d = modelData.date
              if (!d) return ""
              var dt = new Date(d + "T00:00:00")
              var names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
              return names[dt.getDay()] + " " + String(dt.getMonth() + 1).padStart(2, "0") + "/" + String(dt.getDate()).padStart(2, "0")
            }
            color: dim
            font.family: fontFamily
            font.pixelSize: 10
            Layout.preferredWidth: 48
          }

          Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 8
            color: track
            radius: 2
            clip: true

            Rectangle {
              anchors.left: parent.left
              anchors.top: parent.top
              anchors.bottom: parent.bottom
              width: parent.width * (count / weekCardRoot.maxCount)
              color: root.alpha(foreground, 0.78)
              radius: 2
              Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
            }
          }

          Text {
            textFormat: Text.PlainText
            text: count + " prompts"
            color: foreground
            font.family: fontFamily
            font.pixelSize: 10
            font.bold: true
            horizontalAlignment: Text.AlignRight
            Layout.preferredWidth: 62
          }
        }
      }
    }
  }

  component ToolsCard: SectionCard {
    property var provider: null
    visible: !!provider && provider.toolUsage && Object.keys(provider.toolUsage).length > 0
    title: "Top Tool Executions"

    GridLayout {
      width: parent.width
      columns: 2
      columnSpacing: 10
      rowSpacing: 4

      Repeater {
        model: {
          var res = []
          if (provider && provider.toolUsage) {
            for (var k in provider.toolUsage) {
              res.push({ name: k, count: provider.toolUsage[k] })
            }
          }
          return res.slice(0, 6)
        }

        delegate: RowLayout {
          required property var modelData
          Layout.fillWidth: true
          spacing: 4

          Text {
            textFormat: Text.PlainText
            text: modelData.name
            color: dim
            font.family: fontFamily
            font.pixelSize: 10
            elide: Text.ElideRight
            Layout.fillWidth: true
          }
          Text {
            textFormat: Text.PlainText
            text: String(modelData.count)
            color: foreground
            font.family: fontFamily
            font.pixelSize: 10
            font.bold: true
          }
        }
      }
    }
  }

  component RecentSessionsCard: SectionCard {
    id: recentSessionsCardRoot
    property var provider: null
    property bool expanded: false
    readonly property int defaultLimit: Math.max(3, Math.min(10, Number(root.settings ? root.settings.recentSessionsLimit : 5) || 5))
    visible: !!provider && provider.recentSessions && provider.recentSessions.length > 0
    title: "Recent Sessions"
    subtitle: "Click or press 1-" + Math.min(5, (provider ? (provider.recentSessions || []).length : 0)) + " to resume"

    ColumnLayout {
      width: parent.width
      spacing: 6

      Repeater {
        id: sessionRepeater
        model: provider ? (provider.recentSessions || []).slice(0, recentSessionsCardRoot.expanded ? 10 : recentSessionsCardRoot.defaultLimit) : []
        delegate: ColumnLayout {
          required property var modelData
          required property int index
          Layout.fillWidth: true
          spacing: 2

          Rectangle {
            id: sessionItemCard
            Layout.fillWidth: true
            Layout.leftMargin: (modelData.indent ? 16 : 0)
            implicitHeight: sessionCol.implicitHeight + 8
            radius: 4
            readonly property bool isHovered: sessionMouseArea.containsMouse || killMouse.containsMouse
            color: isHovered ? root.cardHover : "transparent"

            Behavior on color { ColorAnimation { duration: 120 } }

            MouseArea {
              id: sessionMouseArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.resumeSession(modelData.conversationId, modelData.workspace, modelData.preview || modelData.title, modelData.pid)
            }

            ColumnLayout {
              id: sessionCol
              anchors.fill: parent
              anchors.margins: 4
              spacing: 3

              RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Text {
                  visible: !!modelData.isSubagent
                  textFormat: Text.PlainText
                  text: "└─"
                  color: root.accent
                  font.family: fontFamily
                  font.pixelSize: 10
                  font.bold: true
                }

                Text {
                  visible: index < 5 && !modelData.isSubagent
                  textFormat: Text.PlainText
                  text: "[" + (index + 1) + "]"
                  color: sessionItemCard.isHovered ? root.accent : root.dim
                  font.family: fontFamily
                  font.pixelSize: 9
                  font.bold: true
                }

                Text {
                  textFormat: Text.PlainText
                  text: modelData.preview || modelData.title || "Session"
                  color: sessionItemCard.isHovered ? root.accent : root.foreground
                  font.family: fontFamily
                  font.pixelSize: 11
                  font.bold: true
                  elide: Text.ElideRight
                  Layout.fillWidth: true
                }

                RowLayout {
                  spacing: 4

                  Rectangle {
                    visible: !!modelData.isSubagent
                    color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.15)
                    border.color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.3)
                    border.width: 1
                    radius: 3
                    Layout.preferredHeight: 14
                    Layout.preferredWidth: subagentBadgeText.implicitWidth + 6

                    Text {
                      id: subagentBadgeText
                      textFormat: Text.PlainText
                      text: (modelData.agentName && modelData.agentName !== "Claude Code") ? modelData.agentName.toUpperCase() : "SUBAGENT"
                      color: root.accent
                      font.family: fontFamily
                      font.pixelSize: 8
                      font.bold: true
                      anchors.centerIn: parent
                    }
                  }

                  Rectangle {
                    visible: !!modelData.isActive
                    radius: 3
                    color: killMouse.containsMouse ? root.urgent : root.track
                    Layout.preferredHeight: 14
                    Layout.preferredWidth: 14

                    Behavior on color { ColorAnimation { duration: 80 } }

                    Text {
                      textFormat: Text.PlainText
                      text: ""
                      color: "#FFFFFF"
                      font.family: fontFamily
                      font.pixelSize: 8
                      font.bold: true
                      anchors.centerIn: parent
                    }

                    MouseArea {
                      id: killMouse
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: function(mouse) {
                        mouse.accepted = true
                        root.killSession(modelData.conversationId)
                      }
                    }
                  }

                  Rectangle {
                    color: modelData.isActive ? "#10B981" : root.track
                    radius: 3
                    Layout.preferredHeight: 14
                    Layout.preferredWidth: sText.implicitWidth + 6

                    Text {
                      id: sText
                      textFormat: Text.PlainText
                      text: modelData.isActive ? "ACTIVE" : "IDLE"
                      color: modelData.isActive ? "#FFFFFF" : root.dim
                      font.family: fontFamily
                      font.pixelSize: 8
                      font.bold: true
                      anchors.centerIn: parent
                    }
                  }
                }
              }

              RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Rectangle {
                  color: root.track
                  radius: 2
                  Layout.preferredHeight: 14
                  Layout.preferredWidth: wsText.implicitWidth + 8

                  Text {
                    id: wsText
                    textFormat: Text.PlainText
                    text: " " + (modelData.workspaceName || "Workspace")
                    color: root.foreground
                    font.family: fontFamily
                    font.pixelSize: 8
                    font.bold: true
                    anchors.centerIn: parent
                  }
                }

                Text { textFormat: Text.PlainText; text: "·"; color: root.dim; font.pixelSize: 9 }
                Text {
                  textFormat: Text.PlainText
                  text: modelData.stepCount + " steps"
                  color: root.dim
                  font.family: fontFamily
                  font.pixelSize: 9
                }
              }
            }
          }

          PanelSeparator {
            Layout.fillWidth: true
            foreground: root.foreground
            strength: 0.12
            visible: index < (sessionRepeater.count - 1)
          }
        }
      }

      Item {
        visible: !!provider && provider.recentSessions && provider.recentSessions.length > recentSessionsCardRoot.defaultLimit
        Layout.fillWidth: true
        implicitHeight: 18

        Text {
          anchors.centerIn: parent
          textFormat: Text.PlainText
          text: recentSessionsCardRoot.expanded ? "Show fewer sessions ▴" : ("Show all sessions (" + ((provider && provider.recentSessions) ? provider.recentSessions.length : 0) + ") ▾")
          color: moreMouse.containsMouse ? root.accent : root.dim
          font.family: fontFamily
          font.pixelSize: 9
          font.bold: true
        }

        MouseArea {
          id: moreMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: recentSessionsCardRoot.expanded = !recentSessionsCardRoot.expanded
        }
      }
    }
  }

  component UsageFooter: RowLayout {
    Layout.fillWidth: true
    spacing: 8

    Text {
      textFormat: Text.PlainText
      Layout.fillWidth: true
      text: "j/k scroll · 1-5 resume · n new · r refresh · s settings · q/esc close"
      color: dim
      font.family: fontFamily
      font.pixelSize: 10
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.WordWrap
    }
  }

  component SettingsContent: ColumnLayout {
    id: settingsRoot
    Layout.fillWidth: true
    spacing: 10

    readonly property bool editorActive: Boolean(
      (refreshIntervalField && refreshIntervalField.field && refreshIntervalField.field.activeFocus)
      || (alertThresholdField && alertThresholdField.field && alertThresholdField.field.activeFocus)
      || (recentSessionsLimitField && recentSessionsLimitField.field && recentSessionsLimitField.field.activeFocus)
      || (terminalField && terminalField.activeFocus)
    )

    SectionCard {
      title: "Refresh Interval"
      subtitle: "Telemetry and quota polling rate (scales to 10s when active)"

      ColumnLayout {
        width: parent.width
        spacing: 8

        NumberField {
          id: refreshIntervalField
          label: "Refresh interval (seconds)"
          value: Number(root.draftValue("refreshIntervalSec", 60))
          from: 10
          to: 1800
          stepSize: 10
          fieldWidth: parent.width
          foreground: root.foreground
          accent: Color.accent
          fontFamily: root.fontFamily
          onModified: function(value) { root.setDraftValue("refreshIntervalSec", value) }
        }
      }
    }

    SectionCard {
      title: "Bar Badge Mode"
      subtitle: "Active Sessions: badge appears when active • Prompts: daily total • Off: icon only"

      ColumnLayout {
        width: parent.width
        spacing: 8

        ButtonGroup {
          id: badgeModeButtonGroup
          foreground: root.foreground
          accent: root.accent
          fontFamily: root.fontFamily
          fontSize: 10
          options: [
            { value: "active", label: "Active", tooltip: "Show badge count when Claude Code sessions are active" },
            { value: "prompts", label: "Prompts", tooltip: "Show total prompt count for today" },
            { value: "quota", label: "Quota %", tooltip: "Show lowest remaining quota percentage directly on bar" },
            { value: "off", label: "Off", tooltip: "Hide badge entirely" }
          ]
          value: root.draftValue("badgeMode", root.draftValue("showBadge", true) === false ? "off" : "active")
          onChanged: function(v) {
            badgeModeButtonGroup.value = v
            root.updateSetting("badgeMode", v)
          }

          Connections {
            target: root
            function onDraftSettingsChanged() {
              badgeModeButtonGroup.value = String(root.draftValue("badgeMode", root.draftValue("showBadge", true) === false ? "off" : "active"))
            }
          }
        }
      }
    }

    SectionCard {
      title: "Low Quota Desktop Alerts"
      subtitle: "Notify via desktop notifications when any quota falls below threshold"

      ColumnLayout {
        width: parent.width
        spacing: 8

        RowLayout {
          Layout.fillWidth: true
          spacing: 8

          Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: "Enable low quota desktop alerts"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: 11
          }

          ToggleSwitch {
            checked: root.draftValue("enableQuotaAlerts", true) !== false
            onToggled: root.setDraftValue("enableQuotaAlerts", checked)
          }
        }

        NumberField {
          id: alertThresholdField
          Layout.fillWidth: true
          label: "Alert threshold (% quota remaining)"
          value: Number(root.draftValue("quotaAlertThreshold", 15))
          from: 5
          to: 50
          stepSize: 5
          fieldWidth: parent.width
          foreground: root.foreground
          accent: Color.accent
          fontFamily: root.fontFamily
          enabled: root.draftValue("enableQuotaAlerts", true) !== false
          opacity: enabled ? 1.0 : 0.45
          onModified: function(value) { root.setDraftValue("quotaAlertThreshold", value) }
        }
      }
    }

    SectionCard {
      title: "Live Hook Updates"
      subtitle: "Refresh the bar instantly on session events, instead of only on a timer"

      ColumnLayout {
        width: parent.width
        spacing: 8

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          wrapMode: Text.WordWrap
          text: {
            if (!root.provider || !root.provider.hooksKnown) return "Checking…"
            return root.provider.hooksInstalled
              ? "Installed — SessionStart, UserPromptSubmit, Stop, Notification, PermissionRequest, and SessionEnd ping this widget the moment they fire."
              : "Not installed — the widget only updates on its refresh interval."
          }
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: 10
        }

        RowLayout {
          Layout.fillWidth: true
          spacing: 8

          Button {
            text: (root.provider && root.provider.hooksInstalled) ? "Remove hooks" : "Install hooks"
            foreground: root.foreground
            tooltipText: (root.provider && root.provider.hooksInstalled)
              ? "Remove these hook entries from ~/.claude/settings.json (a backup is written first)"
              : "Add hook entries to ~/.claude/settings.json (a backup is written first)"
            tooltipBackground: root.background
            tooltipForeground: root.foreground
            fontFamily: root.fontFamily
            fontSize: 10
            horizontalPadding: 8
            verticalPadding: 4
            enabled: !!root.provider && !root.provider.hooksBusy
            onClicked: {
              if (root.provider.hooksInstalled) root.provider.removeHooks()
              else root.provider.installHooks()
            }
          }

          Text {
            textFormat: Text.PlainText
            visible: !!root.provider && root.provider.hooksBusy
            text: "working…"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: 9
          }
        }
      }
    }

    SectionCard {
      title: "Terminal Emulator Override"
      subtitle: "Command used to launch or resume sessions"

      ColumnLayout {
        width: parent.width
        spacing: 6

        TextField {
          id: terminalField
          Layout.fillWidth: true
          placeholderText: "Default: xdg-terminal-exec"
          text: String(root.draftValue("terminalCommand", ""))
          foreground: root.foreground
          accent: root.accent
          font.family: root.fontFamily
          font.pixelSize: 11
          onTextEdited: root.setDraftOnly("terminalCommand", text)
          onEditingFinished: root.setDraftValue("terminalCommand", text)
          onAccepted: root.setDraftValue("terminalCommand", text)

          Connections {
            target: root
            function onDraftSettingsChanged() {
              terminalField.text = String(root.draftValue("terminalCommand", ""))
            }
          }
        }

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: "Leave blank for system default. Supports foot, ghostty, kitty, alacritty, or custom command."
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: 9
          wrapMode: Text.WordWrap
        }
      }
    }

    SectionCard {
      title: "Default Recent Sessions Count"
      subtitle: "Number of recent sessions shown before expanding"

      ColumnLayout {
        width: parent.width
        spacing: 8

        NumberField {
          id: recentSessionsLimitField
          Layout.fillWidth: true
          label: "Initial display count (3 - 10)"
          value: Number(root.draftValue("recentSessionsLimit", 5))
          from: 3
          to: 10
          stepSize: 1
          fieldWidth: parent.width
          foreground: root.foreground
          accent: Color.accent
          fontFamily: root.fontFamily
          onModified: function(value) { root.setDraftValue("recentSessionsLimit", value) }
        }
      }
    }

    Text {
      textFormat: Text.PlainText
      visible: root.settingsStatusText !== ""
      Layout.fillWidth: true
      text: root.settingsStatusText
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: 10
      horizontalAlignment: Text.AlignHCenter
    }

    Text {
      textFormat: Text.PlainText
      Layout.fillWidth: true
      text: "s saves · esc closes"
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: 10
      horizontalAlignment: Text.AlignHCenter
    }
  }

  component SectionCard: BorderSurface {
    id: section
    property string title: ""
    property string subtitle: ""
    property color titleColor: foreground
    property Component headerAccessory: null
    default property alias content: body.data

    Layout.fillWidth: true
    color: card
    borderSpec: Border.flat(Qt.rgba(foreground.r, foreground.g, foreground.b, 0.05), 1)
    padding: 10
    radius: Style.cornerRadius
    implicitHeight: body.implicitHeight + contentTopInset + contentBottomInset
    clip: true

    ColumnLayout {
      id: body
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.topMargin: section.contentTopInset
      anchors.rightMargin: section.contentRightInset
      anchors.bottomMargin: section.contentBottomInset
      anchors.leftMargin: section.contentLeftInset
      spacing: 6

      RowLayout {
        visible: section.title !== "" || section.headerAccessory !== null
        Layout.fillWidth: true
        spacing: 6

        PanelSectionHeader {
          visible: section.title !== ""
          Layout.fillWidth: true
          text: section.title
          foreground: section.titleColor
          fontFamily: root.fontFamily
          fontSize: 11
        }

        Loader {
          sourceComponent: section.headerAccessory
          visible: !!section.headerAccessory
          Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
        }
      }

      Text {
        textFormat: Text.PlainText
        visible: section.subtitle !== ""
        Layout.fillWidth: true
        text: section.subtitle
        color: dim
        font.family: fontFamily
        font.pixelSize: 10
        wrapMode: Text.WordWrap
        elide: Text.ElideRight
      }
    }
  }

  component StatBlock: ColumnLayout {
    property string value: "0"
    property string label: ""
    spacing: 1
    Layout.alignment: Qt.AlignHCenter

    Text {
      textFormat: Text.PlainText
      text: value
      color: foreground
      font.family: fontFamily
      font.pixelSize: 16
      font.bold: true
      horizontalAlignment: Text.AlignHCenter
      Layout.fillWidth: true
    }
    Text {
      textFormat: Text.PlainText
      text: label
      color: dim
      font.family: fontFamily
      font.pixelSize: 9
      horizontalAlignment: Text.AlignHCenter
      Layout.fillWidth: true
      elide: Text.ElideRight
    }
  }
}
