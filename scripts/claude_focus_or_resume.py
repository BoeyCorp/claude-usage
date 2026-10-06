#!/usr/bin/env python3
"""Focus an existing Hyprland terminal window for a Claude Code session, or launch a new terminal.

Prevents duplicate terminal processes and lock contention when a session is already open
in another workspace or window.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Any


def get_ppid(pid: int) -> int | None:
    try:
        with open(f"/proc/{pid}/stat", "r") as f:
            parts = f.read().split(")")
            if len(parts) > 1:
                return int(parts[1].split()[1])
    except Exception:
        pass
    return None


def focus_hyprland_window(address: str, pid: int | None = None) -> bool:
    """Focus Hyprland window via Lua eval or classic dispatcher."""
    # 1. Modern Hyprland (v0.47+ / 0.56+) Lua eval
    lua_code = f'local a = "{address}"; for _, w in ipairs(hl.get_windows()) do if tostring(w.address) == a then hl.dispatch(hl.dsp.focus({{ window = w }})); return "ok" end end'
    try:
        res = subprocess.run(["hyprctl", "eval", lua_code], capture_output=True, text=True, timeout=2)
        if res.returncode == 0 and "ok" in res.stdout:
            return True
    except Exception:
        pass

    # 2. Classic dispatcher
    try:
        res = subprocess.run(["hyprctl", "dispatch", "focuswindow", f"address:{address}"], capture_output=True, text=True, timeout=2)
        if res.returncode == 0:
            return True
    except Exception:
        pass

    # 3. PID dispatcher
    if pid:
        try:
            res = subprocess.run(["hyprctl", "dispatch", "focuswindow", f"pid:{pid}"], capture_output=True, text=True, timeout=2)
            if res.returncode == 0:
                return True
        except Exception:
            pass

    return False


def find_and_focus_window(cid: str, title: str = "", pid: int | None = None) -> bool:
    """Find and focus an active Hyprland window hosting the target session."""
    try:
        raw = subprocess.check_output(["hyprctl", "clients", "-j"], timeout=2)
        clients = json.loads(raw)
    except Exception:
        return False

    if not isinstance(clients, list) or not clients:
        return False

    client_pids = {c.get("pid"): c for c in clients if c.get("pid")}

    # 1. Match by session PID ancestor tree
    if pid and pid > 1:
        cur = pid
        visited = set()
        while cur and cur > 1 and cur not in visited:
            if cur in client_pids:
                client = client_pids[cur]
                if focus_hyprland_window(client.get("address", ""), client.get("pid")):
                    return True
            visited.add(cur)
            cur = get_ppid(cur)

    # 2. Match by running processes whose cmdline contains the conversationId
    if cid:
        for entry in os.scandir("/proc"):
            if entry.name.isdigit():
                try:
                    p_num = int(entry.name)
                    with open(f"/proc/{entry.name}/cmdline", "rb") as f:
                        cmdline = f.read().decode("utf-8", errors="ignore")
                        if cid in cmdline and ("claude" in cmdline or "agy" in cmdline):
                            cur = p_num
                            visited = set()
                            while cur and cur > 1 and cur not in visited:
                                if cur in client_pids:
                                    client = client_pids[cur]
                                    if focus_hyprland_window(client.get("address", ""), client.get("pid")):
                                        return True
                                visited.add(cur)
                                cur = get_ppid(cur)
                except Exception:
                    continue

    # 3. Match window title containing conversationId or session title
    if cid:
        for c in clients:
            w_title = c.get("title", "")
            if cid in w_title:
                if focus_hyprland_window(c.get("address", ""), c.get("pid")):
                    return True

    clean_title = (title or "").strip()
    if len(clean_title) >= 10:
        for c in clients:
            w_title = c.get("title", "")
            if clean_title.lower() in w_title.lower():
                if focus_hyprland_window(c.get("address", ""), c.get("pid")):
                    return True

    return False


def main() -> None:
    parser = argparse.ArgumentParser(description="Focus open Hyprland window or launch terminal")
    parser.add_argument("--cid", default="", help="Conversation ID")
    parser.add_argument("--title", default="", help="Session title")
    parser.add_argument("--pid", type=int, default=0, help="Process PID if known")
    parser.add_argument("fallback", nargs=argparse.REMAINDER, help="Terminal launch command")
    args = parser.parse_args()

    fallback_cmd = args.fallback
    if fallback_cmd and fallback_cmd[0] == "--":
        fallback_cmd = fallback_cmd[1:]

    # Attempt to focus existing Hyprland window
    if args.cid or args.pid:
        if find_and_focus_window(args.cid, args.title, args.pid or None):
            sys.exit(0)

    # No existing window found — launch terminal
    if fallback_cmd:
        try:
            subprocess.Popen(fallback_cmd)
        except Exception as e:
            sys.stderr.write(f"Failed to launch terminal: {e}\n")
            sys.exit(1)


if __name__ == "__main__":
    main()
