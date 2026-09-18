# Claude Usage for Omarchy

Claude Code active session monitor, prompt metrics, tool telemetry, interactive session launcher, and 7-day usage stats in the Omarchy top bar.

This is a fork of [antigravity-usage](https://github.com/BoeyCorp/antigravity-usage) by Jesse Burlamaque, adapted to report on [Claude Code](https://claude.com/product/claude-code) sessions instead of Google Antigravity.

## Features

### 1. Status Bar Icon & Live Badge
- **Themed Vector Icon**: Clean 4-pointed sparkle icon dynamically colorized to match your active Omarchy theme foreground color via `MultiEffect`.
- **State Pulse Indicator**: Color-coded pulse dot indicating real-time agent activity:
  - 🟢 **Green (Pulsing)**: Agent is actively executing/thinking (`Working`).
  - 🔵 **Blue**: Session is open but waiting for user input (`Waiting`).
  - ⚪ **Transparent**: Idle (no active sessions).
- **Configurable Bar Badge Mode**: Dynamic badge pill with configurable display modes:
  - `active` (Default): Number of concurrent background sessions currently running (auto-hides when idle for a clean bar).
  - `prompts`: Total prompts executed today (auto-hides when 0).
  - `off`: Disables the badge completely for an ultra-minimal bar icon.
- **Detailed Tooltip**: Hovering the bar widget shows active session status, today's prompt count, and current model.

### 2. Interactive Session Management
- **Quick Terminal Resume**: Click any session card or press `1`–`5` to immediately resume that session in your terminal (`claude --resume <id>`).
- **Terminal Emulator Override**: Configurable terminal command/binary override (e.g. `foot`, `ghostty`, `kitty`, `alacritty`, or custom command) with automatic working directory handoff, defaulting to `xdg-terminal-exec`.
- **New Session Launcher**: Click the `` header button or press `n` to launch a brand-new `claude` session in your chosen terminal.
- **Process Termination**: Hover over any running session and click the red `` button to terminate the session process cleanly (`SIGTERM`).
- **Configurable Recent Sessions**: Choose your preferred default display limit (3 to 10 sessions) with one-click expansion to view all recent sessions, complete with styled workspace tags (` <ws>`), step counters, and relative timestamps.

### 3. Model Usage Breakdown with Timeframe Toggle
- **Timeframe Switcher**: Interactive segmented pill toggle in the top-right corner to switch between:
  - **Today**: Prompt and step counts for the current calendar day.
  - **Last 7 Days**: Usage aggregated across the past week.
  - **All time**: All-time cumulative model usage.
- **Dynamic Sorting & Animated Visuals**: Models automatically re-sort by activity in the selected timeframe (Opus / Sonnet / Haiku, color-coded by tier), and progress bars smoothly animate (`Easing.OutCubic`) to reflect proportional usage share.
- **Consistent Metrics**: Clean, uniform `X prompts · Y steps` formatting across all models and timeframes.
- **Real Token Counts**: Today's token usage (input + output + cache) is aggregated directly from local transcript `usage` blocks, broken down per model.

### 4. Quota Limits, Burn Rate & Desktop Alerts
- **Real-Time Quota Buckets**: Live quota fetched from Omarchy's own first-party `omarchy-agent-usage-claude --limits-only` collector — the same command that backs the built-in Agents panel. It hits Anthropic's authoritative OAuth usage endpoint directly (using the access token already in `~/.claude/.credentials.json`), so numbers are exact, structured JSON with real ISO reset times — no scraping, no timezone-text parsing.
- **Per-Model Scoped Limits**: Any model-specific window your account has (e.g. an Opus-only weekly cap) shows up as its own row alongside the plan-wide Session and Weekly buckets, labeled from what the collector reports (`Opus Weekly`, etc.) instead of collapsing into the generic bucket.
- **Burn Rate Velocity & Reset Forecasting**: Real-time hourly consumption tracking (`🔥 X%/h`) and intelligent reset pacing projections (`On pace · ~65% at reset` or early warnings `Depletes in ~2.0h before reset`), computed the same way as the original project from timestamped local snapshots.
- **Dual Reset Time Display**: Shows both relative countdown timers (e.g. `2h 15m`) and exact local wall-clock times (e.g. `04:15 AM`).
- **Real Tier Label**: The bar/popup show your actual plan (`Pro`, `Max 5x`, …) as reported by the collector, instead of a generic placeholder.
- **Configurable Low Quota Alerts**: Toggle desktop notifications on/off and configure custom remaining percentage thresholds (5% to 50%, default 15%) via `omarchy-notification-send`.
- **Cheap & Cached**: the collector resolves in well under a second. The scanner caches its result, serves it instantly on every poll, and only re-queries in a detached background process once the cache is older than 3 minutes (with exponential backoff on failures), so the bar widget never blocks waiting on it.

### 5. Performance & Telemetry
- **Sub-50ms High Performance**: Incremental transcript caching indexed by file modification time and size keeps full telemetry and session scans fast even with dozens of past sessions.
- **Direct PID Session Tracking**: Claude Code writes `~/.claude/sessions/*.json` with the owning PID and live `status` directly, so active/working/waiting detection and session termination need no lock-file or `/proc` scanning.
- **Dynamic Configured Model**: Automatically detects your default model selection from `~/.claude/settings.json`.
- **Adaptive Polling**: Automatically scales refresh frequency from 60s idle down to 10s when an active session is working, then returns to 60s when idle.
- **Today & Totals Summary**: Quick stats for prompts today, steps today, and cumulative total prompts.
- **7-Day Activity Chart**: Daily prompt activity visualization across the past week.
- **Tool Telemetry Breakdown**: Live call counters for tools (`Bash`, `Read`, `Edit`, `Write`, `Grep`, `Glob`, `Task`, `WebFetch`, `WebSearch`, etc.).
- **Stale Session Pruning**: Automatically prunes `~/.claude/sessions/*.json` entries whose backing process has already exited.

### 6. Live Hook Updates (optional)
- **Instant Refresh on Session Events**: An opt-in **Live Hook Updates** section in the settings panel wires Claude Code's own `SessionStart`, `UserPromptSubmit`, `Stop`, `Notification`, `PermissionRequest`, and `SessionEnd` hooks to ping the bar the moment they fire, instead of waiting for the next scheduled poll (10–60s).
- **Non-Destructive Install**: A single Install button adds one lightweight hook entry per event to `~/.claude/settings.json` — every other hook you (or another plugin, e.g. Herdr) already have configured, for any event, is left completely untouched. A timestamped backup (`settings.json.claude-usage.bak`) is written before every change.
- **One-Click Removal**: The same button, now labeled Remove, takes out only the entries this plugin added; nothing else in `settings.json` is affected.
- **Still Polls as a Safety Net**: The adaptive refresh timer keeps running regardless, so quota burn-rate tracking and anything the hooks don't cover stay up to date even without them installed.

---

## Requirements

- Python 3.9+ (standard library only: `json`, `datetime`, `pathlib`, `collections`, `subprocess`, `signal`, `fcntl`)
- [Claude Code](https://claude.com/product/claude-code) CLI (`claude`) on `PATH`, logged in, with local session data in `~/.claude`
- Omarchy Shell / Quickshell, with its first-party `omarchy-agent-usage-claude` collector on `PATH` (ships with Omarchy itself — it's what the Quota Limits card calls for real numbers, the same command that backs the built-in Agents panel)

---

## Installation

```sh
omarchy plugin add https://github.com/BoeyCorp/claude-usage.git --enable
omarchy restart shell
```

There's no separate Agents-panel integration step needed — Omarchy's own `omarchy-agent-usage-claude` collector already backs the built-in Agents panel, and this widget calls that same command for its Quota Limits card.

---

## Update

```sh
omarchy plugin update boeycorp.claude-usage --yes
omarchy restart shell
```

---

## Removal

To remove the plugin from Omarchy:

```sh
omarchy plugin remove boeycorp.claude-usage
omarchy restart shell
```

If you installed the [Live Hook Updates](#6-live-hook-updates-optional) feature, remove its hooks first (from the widget's settings panel, or `python3 ~/.config/omarchy/plugins/boeycorp.claude-usage/scripts/claude_usage_hooks.py remove`) so they don't linger as dead entries in `~/.claude/settings.json` — the hook command itself (`omarchy-shell -q ...`) fails silently if left behind, but it's still dead weight worth cleaning up.

---

## Interactions & Shortcuts

### Mouse Controls
- **Left Click**: Open/close popup panel.
- **Middle Click**: Force immediate telemetry refresh.
- **Right Click**: Toggle in-popup settings view (or click the `` header button).

### Keyboard Shortcuts (when popup is open)
| Shortcut | Action |
|---|---|
| `1`–`5` | Quick-resume the corresponding recent session in terminal |
| `n` | Launch a new `claude` terminal session |
| `r` | Force refresh telemetry |
| `s` | Toggle between Stats and Settings view (or save settings) |
| `j` / `k` | Scroll popup content down / up |
| `q` or `Esc` | Close popup panel |

### IPC Commands & Custom Keybindings

The widget registers an IPC target (`boeycorp.claude-usage`), callable as `omarchy-shell <target> <method>`, allowing compositor keybindings (e.g. Hyprland / Sway):

| Action | Command |
|---|---|
| Toggle popup | `omarchy-shell boeycorp.claude-usage toggle` |
| Open popup | `omarchy-shell boeycorp.claude-usage open` |
| Close popup | `omarchy-shell boeycorp.claude-usage close` |
| Refresh telemetry | `omarchy-shell boeycorp.claude-usage refresh` |
| Open settings | `omarchy-shell boeycorp.claude-usage settings` |

Add `-q` to suppress output and fail silently if the shell isn't running (used internally by the Live Hook Updates feature above).

---

## Configuration

Configuration lives in `~/.config/omarchy/shell.json` or can be adjusted directly in the widget's in-popup settings view (right-click or press `s`):

| Key | Type | Default | Description |
|---|---|---|---|
| `refreshIntervalSec` | integer (10–1800) | `60` | Telemetry refresh rate in seconds (adaptively scales to 10s when active) |
| `badgeMode` | enum (`active`, `prompts`, `off`) | `"active"` | Bar badge display mode (`active` sessions count, today's `prompts`, or disabled `off`) |
| `enableQuotaAlerts` | boolean | `true` | Send desktop notifications when model quota falls below threshold |
| `quotaAlertThreshold` | integer (5–50) | `15` | Low quota percentage alert threshold |
| `terminalCommand` | string | `""` | Terminal emulator command override (`foot`, `ghostty`, `kitty`, `alacritty`, or blank for `xdg-terminal-exec`) |
| `recentSessionsLimit` | integer (3–10) | `5` | Initial number of recent sessions to display before expanding |

**Live Hook Updates** (see [feature 6](#6-live-hook-updates-optional)) isn't a `shell.json` setting — it's real state read fresh from `~/.claude/settings.json` each time you open the settings panel, with its own Install/Remove button rather than a toggle.

Two environment variables are also honored by the scripts themselves (not exposed in the settings UI):

| Variable | Default | Description |
|---|---|---|
| `CLAUDE_USAGE_DATA_DIR` | `~/.claude` | Override the Claude Code data directory the scanner (and hooks installer) reads |
| `CLAUDE_USAGE_AGENT_COLLECTOR` | first `omarchy-agent-usage-claude` on `PATH` | Override the collector binary used for the Quota Limits card |

---

## Development & Testing

Run the automated test suite verifying session detection, plain-text sanitization, and telemetry schema contracts:

```sh
python3 -m unittest discover -s tests
```

---

## License

MIT © Jesse Burlamaque (original antigravity-usage) & BoeyCorp contributors (Claude Code adaptation)
