#!/usr/bin/env python3
"""Unit tests for claude_usage_hooks."""

import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "scripts"))

from claude_usage_hooks import (
    HOOK_COMMAND,
    HOOK_EVENTS,
    hooks_installed,
    install,
    load_settings,
    remove,
)


class TestClaudeUsageHooks(unittest.TestCase):
    def test_install_on_missing_settings_file(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            path = Path(tmpdir) / "settings.json"
            self.assertFalse(path.exists())

            changed = install(path)
            self.assertTrue(changed)
            self.assertTrue(path.exists())

            settings = load_settings(path)
            self.assertTrue(hooks_installed(settings))
            for event in HOOK_EVENTS:
                self.assertIn(event, settings["hooks"])

    def test_install_is_idempotent(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            path = Path(tmpdir) / "settings.json"
            self.assertTrue(install(path))
            self.assertFalse(install(path), "a second install should be a no-op")

            settings = load_settings(path)
            # Exactly one of our entries per event, not duplicated
            for event in HOOK_EVENTS:
                our_entries = [
                    e for g in settings["hooks"][event] for e in g.get("hooks", [])
                    if e.get("command") == HOOK_COMMAND
                ]
                self.assertEqual(len(our_entries), 1)

    def test_install_preserves_existing_unrelated_hooks(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            path = Path(tmpdir) / "settings.json"
            path.write_text(json.dumps({
                "theme": "auto",
                "hooks": {
                    "SessionStart": [
                        {
                            "matcher": "*",
                            "hooks": [
                                {"type": "command", "command": "bash '/home/user/.claude/hooks/herdr-agent-state.sh' session", "timeout": 10}
                            ]
                        }
                    ]
                }
            }))

            install(path)
            settings = load_settings(path)

            # theme untouched
            self.assertEqual(settings["theme"], "auto")
            # herdr's SessionStart hook is still there, ours added alongside it
            session_start_commands = [
                e.get("command")
                for g in settings["hooks"]["SessionStart"]
                for e in g.get("hooks", [])
            ]
            self.assertIn("bash '/home/user/.claude/hooks/herdr-agent-state.sh' session", session_start_commands)
            self.assertIn(HOOK_COMMAND, session_start_commands)

    def test_remove_only_removes_our_entries(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            path = Path(tmpdir) / "settings.json"
            path.write_text(json.dumps({
                "hooks": {
                    "SessionStart": [
                        {
                            "matcher": "*",
                            "hooks": [
                                {"type": "command", "command": "bash '/home/user/.claude/hooks/herdr-agent-state.sh' session", "timeout": 10}
                            ]
                        }
                    ]
                }
            }))

            install(path)
            self.assertTrue(hooks_installed(load_settings(path)))

            changed = remove(path)
            self.assertTrue(changed)

            settings = load_settings(path)
            self.assertFalse(hooks_installed(settings))
            # herdr's hook survived
            session_start_commands = [
                e.get("command")
                for g in settings["hooks"]["SessionStart"]
                for e in g.get("hooks", [])
            ]
            self.assertIn("bash '/home/user/.claude/hooks/herdr-agent-state.sh' session", session_start_commands)
            # events we added with no other hooks are cleaned up entirely
            for event in HOOK_EVENTS:
                if event == "SessionStart":
                    continue
                self.assertNotIn(event, settings.get("hooks", {}))

    def test_remove_on_settings_with_no_hooks_is_a_noop(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            path = Path(tmpdir) / "settings.json"
            path.write_text(json.dumps({"theme": "auto"}))
            self.assertFalse(remove(path))
            self.assertEqual(load_settings(path), {"theme": "auto"})

    def test_backup_written_before_change(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            path = Path(tmpdir) / "settings.json"
            path.write_text(json.dumps({"theme": "auto"}))

            install(path)

            backup = path.with_suffix(".json.claude-usage.bak")
            self.assertTrue(backup.exists())
            self.assertEqual(json.loads(backup.read_text()), {"theme": "auto"})


if __name__ == "__main__":
    unittest.main()
