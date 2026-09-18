#!/usr/bin/env python3
"""Install/remove Claude Code hooks that push instant bar-widget refreshes.

Without this, the widget only learns a session started, stopped, or needs input on its next
timed poll (10s while active, 60s while idle). This wires SessionStart, UserPromptSubmit,
Stop, Notification, PermissionRequest, and SessionEnd in ~/.claude/settings.json to call
`omarchy-shell -q boeycorp.claude-usage refresh`, so the bar updates the moment something
happens instead.

Only ever touches hook entries whose command is exactly HOOK_COMMAND below — every other hook
you (or another plugin) already have configured, for any event, is left untouched. A timestamped
backup of settings.json is written before every change this script makes.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path
from typing import Any

HOOK_COMMAND = "omarchy-shell -q boeycorp.claude-usage refresh"
HOOK_TIMEOUT = 5
HOOK_EVENTS = ["SessionStart", "UserPromptSubmit", "Stop", "Notification", "PermissionRequest", "SessionEnd"]


def default_settings_path() -> Path:
    base = os.environ.get("CLAUDE_USAGE_DATA_DIR") or os.path.expanduser("~/.claude")
    return Path(base).expanduser() / "settings.json"


def load_settings(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {}
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
            return data if isinstance(data, dict) else {}
    except Exception:
        return {}


def save_settings(path: Path, data: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        backup = path.with_suffix(path.suffix + ".claude-usage.bak")
        try:
            backup.write_text(path.read_text(encoding="utf-8"), encoding="utf-8")
        except Exception:
            pass
    tmp = path.with_suffix(".tmp")
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
    tmp.replace(path)


def hooks_installed(settings: dict[str, Any]) -> bool:
    hooks = settings.get("hooks")
    if not isinstance(hooks, dict):
        return False
    for event in HOOK_EVENTS:
        for group in hooks.get(event, []) or []:
            if not isinstance(group, dict):
                continue
            for entry in group.get("hooks", []) or []:
                if isinstance(entry, dict) and entry.get("command") == HOOK_COMMAND:
                    return True
    return False


def install(path: Path) -> bool:
    """Add our hook entry to every event in HOOK_EVENTS that doesn't already have it.
    Existing hooks (ours from a prior install, or anyone else's) are never duplicated or
    disturbed. Returns True if settings.json was changed.
    """
    settings = load_settings(path)
    hooks = settings.setdefault("hooks", {})
    changed = False

    for event in HOOK_EVENTS:
        groups = hooks.setdefault(event, [])
        already = any(
            isinstance(g, dict) and any(
                isinstance(e, dict) and e.get("command") == HOOK_COMMAND
                for e in (g.get("hooks") or [])
            )
            for g in groups
        )
        if already:
            continue
        groups.append({
            "matcher": "*",
            "hooks": [{"type": "command", "command": HOOK_COMMAND, "timeout": HOOK_TIMEOUT}]
        })
        changed = True

    if changed:
        save_settings(path, settings)
    return changed


def remove(path: Path) -> bool:
    """Remove every hook entry whose command is exactly HOOK_COMMAND, dropping any matcher
    group or event key that becomes empty as a result. Everything else is left as-is.
    Returns True if settings.json was changed.
    """
    settings = load_settings(path)
    hooks = settings.get("hooks")
    if not isinstance(hooks, dict):
        return False

    changed = False
    for event in HOOK_EVENTS:
        groups = hooks.get(event)
        if not isinstance(groups, list):
            continue

        new_groups = []
        for group in groups:
            if not isinstance(group, dict):
                new_groups.append(group)
                continue
            entries = group.get("hooks") or []
            kept = [e for e in entries if not (isinstance(e, dict) and e.get("command") == HOOK_COMMAND)]
            if len(kept) != len(entries):
                changed = True
            if kept:
                new_groups.append({**group, "hooks": kept})
            # a group whose only hook was ours is simply dropped

        if new_groups:
            hooks[event] = new_groups
        elif event in hooks:
            del hooks[event]
            changed = True

    if not hooks:
        settings.pop("hooks", None)

    if changed:
        save_settings(path, settings)
    return changed


def main() -> None:
    parser = argparse.ArgumentParser(description="Manage claude-usage's live-refresh Claude Code hooks")
    parser.add_argument("action", choices=["install", "remove", "status"])
    parser.add_argument("path", nargs="?", default=None, help="Path to ~/.claude/settings.json")
    args = parser.parse_args()

    settings_path = Path(args.path).expanduser() if args.path else default_settings_path()

    if args.action == "status":
        print(json.dumps({"installed": hooks_installed(load_settings(settings_path))}))
        return

    if args.action == "install":
        changed = install(settings_path)
        print(json.dumps({"installed": True, "changed": changed}))
        return

    changed = remove(settings_path)
    print(json.dumps({"installed": hooks_installed(load_settings(settings_path)), "changed": changed}))


if __name__ == "__main__":
    sys.exit(main() or 0)
