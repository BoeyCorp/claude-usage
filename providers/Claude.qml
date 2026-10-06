import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root
    visible: false

    property string providerId: "claude"
    property string providerName: "Claude Code"
    property var settings: ({})
    property bool enabled: true
    property bool ready: false
    property bool refreshing: false
    property bool active: false
    property string activeStatus: "Idle"
    property bool hasActiveSession: false
    property string usageStatusText: ""
    property string authHelpText: ""
    property string currentModel: ""
    property string tierLabel: "Anthropic"
    property string updatedAt: ""
    property double lastUpdatedMs: 0
    property string quotaUpdatedAt: ""
    property double lastFullRefreshMs: 0

    property int todayPrompts: 0
    property int todaySessions: 0
    property int todaySteps: 0
    property int todayTotalTokens: 0
    property var todayTokensByModel: ({})
    property int todayCacheReadTokens: 0
    property int todayCacheCreationTokens: 0
    property double todayCacheHitRate: 0.0

    property var recentDays: []
    property int totalPrompts: 0
    property int totalSessions: 0
    property int totalSteps: 0

    property var activeSessions: []
    property var recentSessions: []
    property var toolUsage: ({})
    property var modelUsage: ({})
    property var limits: []
    property var quotaGroups: []
    property var modelList: []
    property var recentWorkspaces: []

    property bool hasLocalStats: false

    readonly property string scannerScriptPath: pathFromUrl(Qt.resolvedUrl("../scripts/claude_usage_scanner.py"))
    readonly property string hooksScriptPath: pathFromUrl(Qt.resolvedUrl("../scripts/claude_usage_hooks.py"))

    property bool hooksInstalled: false
    property bool hooksKnown: false
    property bool hooksBusy: false

    function pathFromUrl(url) {
        var value = String(url || "")
        if (value.indexOf("file://") === 0)
            return decodeURIComponent(value.substring(7))
        return value
    }

    property double refreshStartTime: 0

    Timer {
        id: minRefreshDurationTimer
        interval: 800
        repeat: false
        onTriggered: root.refreshing = false
    }

    Process {
        id: scanner
        running: false
        command: []

        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.applyUsage(text)
        }

        stderr: StdioCollector {
            waitForEnd: true
            onStreamFinished: function(text) {
                if (text && text.trim() !== "")
                    console.warn("claude-usage/scanner", text.trim())
            }
        }

        onExited: function(exitCode, exitStatus) {
            var elapsed = Date.now() - root.refreshStartTime
            if (elapsed < 800) {
                minRefreshDurationTimer.interval = Math.max(50, 800 - elapsed)
                minRefreshDurationTimer.restart()
            } else {
                root.refreshing = false
            }

            if (exitCode !== 0 && !root.ready) {
                root.usageStatusText = "Scanner error (exit " + exitCode + ")"
                root.authHelpText = "The usage scanner exited with an error. Check that python3 is installed."
            }
        }
    }

    Process {
        id: hooksProc
        running: false
        command: []

        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.applyHooksResult(text)
        }

        stderr: StdioCollector {
            waitForEnd: true
            onStreamFinished: function(text) {
                if (text && text.trim() !== "")
                    console.warn("claude-usage/hooks", text.trim())
            }
        }

        onExited: function(exitCode, exitStatus) {
            root.hooksBusy = false
        }
    }

    function applyHooksResult(content) {
        try {
            var data = JSON.parse(String(content || "{}"))
            root.hooksInstalled = data.installed === true
            root.hooksKnown = true
        } catch (e) {
            console.error("claude-usage/hooks", "Failed to parse hooks result:", e)
        }
    }

    function runHooksAction(action) {
        if (hooksProc.running)
            return
        root.hooksBusy = true
        hooksProc.command = ["python3", root.hooksScriptPath, action]
        hooksProc.running = true
    }

    function checkHooks() {
        runHooksAction("status")
    }

    function installHooks() {
        runHooksAction("install")
    }

    function removeHooks() {
        runHooksAction("remove")
    }

    function applyUsage(content) {
        try {
            var data = JSON.parse(String(content || "{}"))
            if (!data.ready && data.schemaVersion === undefined)
                return

            root.ready = true
            root.active = data.active === true
            root.activeStatus = data.activeStatus || (data.active ? "Active" : "Idle")
            root.hasActiveSession = data.hasActiveSession === true
            root.hasLocalStats = data.hasLocalStats !== false
            root.tierLabel = data.tierLabel || "Anthropic"
            root.currentModel = data.currentModel || ""

            root.todayPrompts = Math.max(0, Number(data.todayPrompts || 0))
            root.todaySessions = Math.max(0, Number(data.todaySessions || 0))
            root.todaySteps = Math.max(0, Number(data.todaySteps || 0))
            root.todayTotalTokens = Math.max(0, Number(data.todayTotalTokens || 0))
            root.todayTokensByModel = data.todayTokensByModel || ({})
            root.todayCacheReadTokens = Math.max(0, Number(data.todayCacheReadTokens || 0))
            root.todayCacheCreationTokens = Math.max(0, Number(data.todayCacheCreationTokens || 0))
            root.todayCacheHitRate = Number(data.todayCacheHitRate || 0)

            root.recentDays = data.recentDays || []
            root.totalPrompts = Math.max(0, Number(data.totalPrompts || 0))
            root.totalSessions = Math.max(0, Number(data.totalSessions || 0))
            root.totalSteps = Math.max(0, Number(data.totalSteps || 0))

            root.activeSessions = data.activeSessions || []
            root.recentSessions = data.recentSessions || []
            root.toolUsage = data.toolUsage || ({})
            root.modelUsage = data.modelUsage || ({})
            root.modelList = data.modelList || []
            root.limits = data.limits || []
            root.quotaGroups = data.quotaGroups || []
            root.recentWorkspaces = data.recentWorkspaces || []

            root.usageStatusText = data.usageStatusText || ""
            root.authHelpText = data.authHelpText || ""
            root.updatedAt = data.updatedAt || ""
            root.lastUpdatedMs = Date.now()
            root.quotaUpdatedAt = data.quotaUpdatedAt || ""
            root.lastFullRefreshMs = Number(data.lastFullRefreshMs || data.quotaUpdatedMs || 0)
        } catch (e) {
            root.usageStatusText = "Scanner error"
            root.authHelpText = String(e)
            console.error("claude-usage", "Failed to parse scanner output:", e)
        }
    }

    function refresh(force) {
        if (scanner.running)
            return

        minRefreshDurationTimer.stop()
        root.refreshStartTime = Date.now()
        root.refreshing = true
        var cmd = ["python3", root.scannerScriptPath]
        if (force === true) {
            cmd.push("--force")
        }

        var enableAlerts = (root.settings && root.settings.enableQuotaAlerts !== undefined) ? Boolean(root.settings.enableQuotaAlerts) : true
        if (enableAlerts) {
            var thresholdPct = (root.settings && root.settings.quotaAlertThreshold !== undefined) ? Number(root.settings.quotaAlertThreshold) : 15
            cmd.push("--notify-low-quota", String(thresholdPct || 15))
        }

        scanner.command = cmd
        scanner.running = true
    }
}
