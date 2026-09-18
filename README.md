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
- **Real-Time Quota Buckets**: Live quota information fetched from `claude -p /usage --output-format json --no-session-persistence` (Claude Code's own local `/usage` command), covering the Current Session and Current Week (all models) limits your subscription actually reports.
- **Burn Rate Velocity & Reset Forecasting**: Real-time hourly consumption tracking (`🔥 X%/h`) and intelligent reset pacing projections (`On pace · ~65% at reset` or early warnings `Depletes in ~2.0h before reset`), computed the same way as the original project from timestamped local snapshots.
- **Dual Reset Time Display**: Shows both relative countdown timers (e.g. `2h 15m`) and exact local wall-clock times (e.g. `04:15 AM`), parsed from `/usage`'s human-readable reset time (e.g. `resets Sep 18, 8pm (Australia/Perth)`) into a real timezone-aware timestamp.
- **Configurable Low Quota Alerts**: Toggle desktop notifications on/off and configure custom remaining percentage thresholds (5% to 50%, default 15%) via `omarchy-notification-send`.
- **Cheap & Cached**: `/usage` is a local Claude Code command — it resolves in well under a second and doesn't spend any API/model quota itself. The scanner caches the result, serves it instantly on every poll, and only re-queries in a detached background process once the cache is older than 3 minutes (with exponential backoff on failures), so the bar widget never blocks waiting on it.

### 5. Performance & Telemetry
- **Sub-50ms High Performance**: Incremental transcript caching indexed by file modification time and size keeps full telemetry and session scans fast even with dozens of past sessions.
- **Direct PID Session Tracking**: Claude Code writes `~/.claude/sessions/*.json` with the owning PID and live `status` directly, so active/working/waiting detection and session termination need no lock-file or `/proc` scanning.
- **Dynamic Configured Model**: Automatically detects your default model selection from `~/.claude/settings.json`.
- **Adaptive Polling**: Automatically scales refresh frequency from 60s idle down to 10s when an active session is working, then returns to 60s when idle.
- **Today & Totals Summary**: Quick stats for prompts today, steps today, and cumulative total prompts.
- **7-Day Activity Chart**: Daily prompt activity visualization across the past week.
- **Tool Telemetry Breakdown**: Live call counters for tools (`Bash`, `Read`, `Edit`, `Write`, `Grep`, `Glob`, `Task`, `WebFetch`, `WebSearch`, etc.).
- **Stale Session Pruning**: Automatically prunes `~/.claude/sessions/*.json` entries whose backing process has already exited.

### 6. Dual Omarchy Integration
- **Standalone Bar Widget**: Full-featured QML popup panel (`boeycorp.claude-usage`).
- **Native Agents Panel Collector**: Includes companion binary (`bin/omarchy-agent-usage-claude`) compatible with Omarchy's system-wide `omarchy.agents` contract (`--limits-only`).

---

## Requirements

- Python 3.9+ (standard library only: `json`, `datetime`, `pathlib`, `collections`, `subprocess`, `signal`, `fcntl`, `zoneinfo`)
- [Claude Code](https://claude.com/product/claude-code) CLI (`claude`) on `PATH`, logged in, with local session data in `~/.claude` — the Quota Limits card shells out to `claude -p /usage` for real numbers
- Omarchy Shell / Quickshell

---

## Installation

```sh
omarchy plugin add https://github.com/BoeyCorp/claude-usage.git --enable
omarchy restart shell
```

### (Optional) Native `omarchy.agents` Panel Integration

To also include Claude Code as a tab inside Omarchy's built-in Agents panel:

```sh
mkdir -p ~/.local/bin
ln -sf ~/.config/omarchy/plugins/boeycorp.claude-usage/bin/omarchy-agent-usage-claude ~/.local/bin/omarchy-agent-usage-claude
```

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

If you configured the optional Agents panel integration:

```sh
rm -f ~/.local/bin/omarchy-agent-usage-claude
```

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

The widget registers an IPC target (`boeycorp.claude-usage`), allowing compositor keybindings (e.g. Hyprland / Sway):

| Action | Command |
|---|---|
| Toggle popup | `omarchy-shell shell toggle boeycorp.claude-usage` |
| Open popup | `omarchy-shell shell summon boeycorp.claude-usage` |
| Close popup | `omarchy-shell shell hide boeycorp.claude-usage` |
| Refresh telemetry | `omarchy-shell ipc call boeycorp.claude-usage refresh` |
| Open settings | `omarchy-shell ipc call boeycorp.claude-usage settings` |

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

Two environment variables are also honored by the scanner script itself (not exposed in the settings UI):

| Variable | Default | Description |
|---|---|---|
| `CLAUDE_USAGE_DATA_DIR` | `~/.claude` | Override the Claude Code data directory the scanner reads |
| `CLAUDE_USAGE_CLI` | first `claude` on `PATH` | Override the `claude` binary used for the `/usage` quota query |

---

## Development & Testing

Run the automated test suite verifying session detection, plain-text sanitization, and telemetry schema contracts:

```sh
python3 -m unittest discover -s tests
```

---

## License

MIT © Jesse Burlamaque (original antigravity-usage) & BoeyCorp contributors (Claude Code adaptation)
