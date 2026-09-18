import QtQuick
import Quickshell
import "providers"

Item {
    id: root
    visible: false

    property var settings: ({})

    Claude {
        id: claudeProvider
        enabled: true
        settings: root.settings
    }

    property var provider: claudeProvider
    property bool refreshing: claudeProvider ? claudeProvider.refreshing : false
    property int refreshIntervalSec: Math.max(10, Number(root.setting("refreshIntervalSec", 60)))

    Timer {
        id: autoRefreshTimer
        interval: (claudeProvider && claudeProvider.hasActiveSession) ? 10000 : (root.refreshIntervalSec * 1000)
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refreshAll()
    }

    Connections {
        target: claudeProvider
        function onHasActiveSessionChanged() {
            autoRefreshTimer.restart()
        }
    }

    function setting(name, fallback) {
        var value = settings ? settings[name] : undefined
        return value === undefined || value === null ? fallback : value
    }

    function refreshAll(force) {
        claudeProvider.refresh(force === true)
    }

    function formatNumber(n) {
        if (n === undefined || n === null) return "0"
        if (n >= 1e6) return (n / 1e6).toFixed(1) + "M"
        if (n >= 1e3) return (n / 1e3).toFixed(1) + "K"
        return String(n)
    }

    function formatDateShort(dateStr) {
        if (!dateStr) return ""
        var parts = dateStr.split("-")
        if (parts.length === 3) {
            return parts[1] + "/" + parts[2]
        }
        return dateStr
    }

    function formatRelativeTime(timestamp) {
        if (!timestamp) return ""
        try {
            var ms = typeof timestamp === "number" ? timestamp : Date.parse(timestamp)
            if (isNaN(ms)) return ""
            var diff = Math.floor((Date.now() - ms) / 1000)
            if (diff < 60) return "just now"
            if (diff < 3600) return Math.floor(diff / 60) + "m ago"
            if (diff < 86400) return Math.floor(diff / 3600) + "h ago"
            return Math.floor(diff / 86400) + "d ago"
        } catch (e) {
            return ""
        }
    }
}
