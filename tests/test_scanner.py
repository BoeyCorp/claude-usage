#!/usr/bin/env python3
"""Smoke and unit tests for claude_usage_scanner."""

import json
import os
import signal
import sys
import tempfile
import time
from pathlib import Path

# Add scripts directory to sys.path
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "scripts"))

from claude_usage_scanner import (
    read_active_sessions,
    pid_alive,
    kill_session,
    scan,
    default_base_dir,
    sanitize_plain_text,
    read_configured_model,
    compute_bucket_forecast,
    update_quota_snapshots,
    format_hours_duration,
    normalize_timestamp_seconds,
    parse_transcripts,
    parse_usage_output,
    fetch_claude_usage_quota,
    check_and_send_quota_notifications,
    get_quota_backoff,
    record_quota_failure,
    record_quota_success,
)


import datetime as dt
import unittest


def write_session_file(sessions_dir: Path, session_id: str, pid: int, status: str = "busy", cwd: str = "/tmp/project") -> Path:
    sessions_dir.mkdir(parents=True, exist_ok=True)
    p = sessions_dir / f"{pid}.json"
    p.write_text(json.dumps({
        "pid": pid,
        "sessionId": session_id,
        "cwd": cwd,
        "status": status,
        "kind": "interactive",
        "updatedAt": int(time.time() * 1000),
    }))
    return p


class TestClaudeUsageScanner(unittest.TestCase):
    def test_sanitize_plain_text(self):
        self.assertEqual(sanitize_plain_text("hello\x00 world\t"), "hello world")
        self.assertEqual(sanitize_plain_text(None), "")
        self.assertEqual(sanitize_plain_text("   spaced   out   "), "spaced out")

    def test_read_configured_model(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            pdir = Path(tmpdir)
            # Default fallback when no settings file exists
            self.assertEqual(read_configured_model(pdir), "Claude (Default)")

            # Reads model from settings.json
            settings_file = pdir / "settings.json"
            settings_file.write_text(json.dumps({"model": "claude-opus-5"}))
            self.assertEqual(read_configured_model(pdir), "claude-opus-5")

    def test_format_hours_duration(self):
        self.assertEqual(format_hours_duration(0.5), "30m")
        self.assertEqual(format_hours_duration(2.5), "2.5h")
        self.assertEqual(format_hours_duration(26.0), "1d 2h")
        # Rollover fix: 47.7 % 24 = 23.7, round = 24 → should become 2d, not "1d 24h"
        self.assertEqual(format_hours_duration(47.7), "2d")
        self.assertEqual(format_hours_duration(24.0), "1d")
        self.assertEqual(format_hours_duration(0), "0m")

    def test_normalize_timestamp_seconds(self):
        # Epoch seconds should pass through
        self.assertAlmostEqual(normalize_timestamp_seconds(1725753600), 1725753600.0)
        # Epoch milliseconds should be divided by 1000
        self.assertAlmostEqual(normalize_timestamp_seconds(1725753600000), 1725753600.0)
        # None returns 0
        self.assertEqual(normalize_timestamp_seconds(None), 0.0)
        # Invalid string returns 0
        self.assertEqual(normalize_timestamp_seconds("not-a-number"), 0.0)

    def test_compute_bucket_forecast(self):
        now_dt = dt.datetime.now(dt.timezone.utc)
        reset_in_5h = (now_dt + dt.timedelta(hours=5)).isoformat().replace("+00:00", "Z")

        # Stable / idle: burn rate ~ 0
        burn_txt, fc_txt, status = compute_bucket_forecast(90.0, 0.0, reset_in_5h)
        self.assertEqual(status, "stable")
        self.assertEqual(fc_txt, "Paced to reset")

        # Safe pace: 80% remaining, burning 2%/h for 5h -> 70% left at reset
        burn_txt, fc_txt, status = compute_bucket_forecast(80.0, 2.0, reset_in_5h)
        self.assertEqual(status, "safe")
        self.assertIn("On pace", fc_txt)
        self.assertEqual(burn_txt, "2.0%/h")

        # Warning / tight pace: 20% remaining, burning 2%/h for 5h -> 10% left at reset (<15%)
        burn_txt, fc_txt, status = compute_bucket_forecast(20.0, 2.0, reset_in_5h)
        self.assertEqual(status, "warning")
        self.assertIn("Tight pace", fc_txt)

        # Critical: 20% remaining, burning 10%/h for 5h -> depletes in 2.0h before 5h reset
        burn_txt, fc_txt, status = compute_bucket_forecast(20.0, 10.0, reset_in_5h)
        self.assertEqual(status, "critical")
        self.assertIn("Depletes in ~2.0h (before reset)", fc_txt)

    def test_update_quota_snapshots(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            pdir = Path(tmpdir)
            groups = [
                {
                    "name": "Claude Models",
                    "buckets": [
                        {"id": "claude-5h", "remaining_fraction": 0.90}
                    ]
                }
            ]
            rates = update_quota_snapshots(pdir, groups)
            # First snapshot establishes baseline
            self.assertIn("claude-5h", rates)
            self.assertEqual(rates["claude-5h"], 0.0)

            snap_file = pdir / "cache" / "claude_usage_quota_snapshots.json"
            self.assertTrue(snap_file.exists())

    def test_transcript_caching(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            pdir = Path(tmpdir)
            projects_dir = pdir / "projects"
            tpath = projects_dir / "-tmp-project" / "conv1.jsonl"
            tpath.parent.mkdir(parents=True, exist_ok=True)
            lines = [
                {
                    "type": "user",
                    "timestamp": "2026-09-08T01:00:00Z",
                    "message": {"role": "user", "content": "hello"}
                },
                {
                    "type": "assistant",
                    "timestamp": "2026-09-08T01:00:01Z",
                    "message": {
                        "role": "assistant",
                        "model": "claude-sonnet-5",
                        "content": [{"type": "tool_use", "name": "Bash", "input": {}}],
                        "usage": {"input_tokens": 10, "output_tokens": 5}
                    }
                },
            ]
            tpath.write_text("\n".join(json.dumps(l) for l in lines) + "\n")

            # First parse: builds cache
            tools1, models1, list1, latest1, steps1, tokens1 = parse_transcripts(
                projects_dir, "2026-09-08", ["2026-09-08"], base_dir=pdir
            )
            self.assertEqual(tools1["Bash"], 1)
            self.assertEqual(steps1["conv1"], 1)

            cache_file = pdir / "cache" / "claude_usage_transcript_cache.json"
            self.assertTrue(cache_file.exists())

            # Second parse: reads from cache
            tools2, models2, list2, latest2, steps2, tokens2 = parse_transcripts(
                projects_dir, "2026-09-08", ["2026-09-08"], base_dir=pdir
            )
            self.assertEqual(tools2["Bash"], 1)
            self.assertEqual(latest2, "claude-sonnet-5")

    def test_pid_alive(self):
        # The current process is definitely alive
        self.assertTrue(pid_alive(os.getpid()))
        # A pid of 0 or an absurdly large/non-existent pid should not be alive
        self.assertFalse(pid_alive(0))
        self.assertFalse(pid_alive(2**30))

    def test_active_session_detection_and_pruning(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            pdir = Path(tmpdir)
            sessions_dir = pdir / "sessions"

            # A session backed by this live test process: should be detected as active
            live_pid = os.getpid()
            write_session_file(sessions_dir, "live-session", live_pid, status="busy")

            # A session backed by a pid that cannot exist: should be pruned
            dead_file = write_session_file(sessions_dir, "dead-session", 2**30 - 1, status="idle")

            active = read_active_sessions(sessions_dir)
            self.assertIn("live-session", active)
            self.assertNotIn("dead-session", active)
            self.assertFalse(dead_file.exists(), "stale session file should have been pruned")

    def test_kill_session(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            pdir = Path(tmpdir)
            sessions_dir = pdir / "sessions"

            proc_pid = os.fork() if hasattr(os, "fork") else None
            if proc_pid == 0:
                # Child: sleep until killed
                time.sleep(30)
                os._exit(0)

            try:
                write_session_file(sessions_dir, "child-session", proc_pid, status="busy")
                success = kill_session("child-session", pdir)
                self.assertTrue(success)

                # Give the OS a moment to deliver SIGTERM
                deadline = time.time() + 2
                exited = False
                while time.time() < deadline:
                    wpid, _ = os.waitpid(proc_pid, os.WNOHANG)
                    if wpid == proc_pid:
                        exited = True
                        break
                    time.sleep(0.05)
                self.assertTrue(exited, "killed child process should have exited")
            finally:
                try:
                    os.kill(proc_pid, signal.SIGKILL)
                    os.waitpid(proc_pid, 0)
                except Exception:
                    pass

    def test_parse_usage_output(self):
        text = (
            "You are currently using your subscription to power your Claude Code usage\n\n"
            "Current session: 11% used · resets Sep 18, 8pm (Australia/Perth)\n"
            "Current week (all models): 2% used · resets Sep 23, 12pm (Australia/Perth)\n\n"
            "What's contributing to your limits usage?"
        )
        parsed = parse_usage_output(text)
        self.assertEqual(len(parsed["groups"]), 1)
        buckets = {b["id"]: b for b in parsed["groups"][0]["buckets"]}
        self.assertIn("session", buckets)
        self.assertIn("weekly", buckets)
        self.assertAlmostEqual(buckets["session"]["remaining_fraction"], 0.89)
        self.assertAlmostEqual(buckets["weekly"]["remaining_fraction"], 0.98)
        # Perth (UTC+8, no DST): 8pm -> 12:00 UTC, 12pm -> 04:00 UTC
        self.assertTrue(buckets["session"]["reset_time"].startswith("20"))
        self.assertIn("T12:00:00", buckets["session"]["reset_time"])
        self.assertIn("T04:00:00", buckets["weekly"]["reset_time"])

    def test_parse_usage_output_no_match(self):
        parsed = parse_usage_output("some unrelated text with no usage lines")
        self.assertEqual(parsed, {"groups": []})

    def test_fetch_claude_usage_quota_uses_query_and_caches(self):
        from unittest.mock import patch
        with tempfile.TemporaryDirectory() as tmpdir:
            pdir = Path(tmpdir)
            canned = (
                "Current session: 10% used · resets Sep 18, 8pm (Australia/Perth)\n"
                "Current week (all models): 2% used · resets Sep 23, 12pm (Australia/Perth)"
            )
            with patch("claude_usage_scanner.query_usage_text", return_value=canned) as mock_query:
                data = fetch_claude_usage_quota(pdir, force=True)
                self.assertEqual(mock_query.call_count, 1)
                self.assertEqual(len(data["groups"]), 1)

                cache_file = pdir / "cache" / "claude_usage_quota_cache.json"
                self.assertTrue(cache_file.exists())

                # A non-forced call within the cache TTL should serve from disk, not re-query
                mock_query.reset_mock()
                data2 = fetch_claude_usage_quota(pdir, force=False)
                self.assertEqual(mock_query.call_count, 0)
                self.assertEqual(data2["groups"][0]["buckets"], data["groups"][0]["buckets"])

    def test_scan_contract(self):
        from unittest.mock import patch
        canned = (
            "Current session: 10% used · resets Sep 18, 8pm (Australia/Perth)\n"
            "Current week (all models): 2% used · resets Sep 23, 12pm (Australia/Perth)"
        )
        with tempfile.TemporaryDirectory() as tmpdir:
            base_dir = Path(tmpdir)
            cache_dir = base_dir / "cache"
            cache_dir.mkdir(parents=True)

            with patch("claude_usage_scanner.query_usage_text", return_value=canned):
                data = scan(base_dir, force=False)

            self.assertEqual(data["schemaVersion"], 1)
            self.assertEqual(data["id"], "claude")
            self.assertIn("activeStatus", data)
            self.assertIn("todayPrompts", data)
            self.assertIn("recentSessions", data)
            self.assertIsInstance(data["recentSessions"], list)
            self.assertIn("limits", data)
            self.assertIsInstance(data["limits"], list)
            self.assertIn("currentModel", data)
            self.assertEqual(data["currentModel"], "Claude (Default)")
            self.assertTrue(len(data["limits"]) > 0)
            self.assertIn("burnRatePerHour", data["limits"][0])
            self.assertIn("forecastText", data["limits"][0])
            self.assertIn("forecastStatus", data["limits"][0])
            # Real percentages from the mocked /usage reply should have come through
            limits_by_group = {l["group"]: l for l in data["limits"]}
            self.assertAlmostEqual(limits_by_group["session"]["percent"], 0.10, places=2)
            self.assertAlmostEqual(limits_by_group["weekly"]["percent"], 0.02, places=2)
            # Verify recentDays entries include 'steps' field
            self.assertIn("recentDays", data)
            self.assertTrue(len(data["recentDays"]) > 0)
            for day_entry in data["recentDays"]:
                self.assertIn("steps", day_entry)
            self.assertIn("quotaUpdatedAt", data)
            self.assertTrue(len(data["quotaUpdatedAt"]) > 0)
            self.assertIn("lastFullRefreshMs", data)
            self.assertTrue(data["lastFullRefreshMs"] > 0)

    def test_scan_contract_without_usage_cli(self):
        """If `claude -p /usage` is unavailable, scan() must still return the full contract."""
        from unittest.mock import patch
        with tempfile.TemporaryDirectory() as tmpdir:
            base_dir = Path(tmpdir)
            (base_dir / "cache").mkdir(parents=True)

            with patch("claude_usage_scanner.query_usage_text", return_value=None):
                data = scan(base_dir, force=False)

            self.assertTrue(data["ready"])
            self.assertEqual(len(data["limits"]), 2)
            self.assertEqual(data["limits"][0]["percent"], 0.0)

    def test_quota_notifications_cooldown_and_consolidation(self):
        from unittest.mock import patch
        with tempfile.TemporaryDirectory() as tmpdir:
            pdir = Path(tmpdir)
            low_quota_groups = [
                {
                    "name": "Claude Models",
                    "buckets": [
                        {"id": "claude-weekly", "name": "Weekly Limit", "remainingPercent": 0},
                        {"id": "claude-5h", "name": "5-Hour Limit", "remainingPercent": 2},
                    ]
                }
            ]
            healthy_quota_groups = [
                {
                    "name": "Claude Models",
                    "buckets": [
                        {"id": "claude-weekly", "name": "Weekly Limit", "remainingPercent": 100},
                        {"id": "claude-5h", "name": "5-Hour Limit", "remainingPercent": 100},
                    ]
                }
            ]

            with patch("subprocess.run") as mock_run:
                # 1. First run: sends exactly 1 consolidated notification for the group
                check_and_send_quota_notifications(pdir, low_quota_groups, threshold_pct=15)
                self.assertEqual(mock_run.call_count, 1)
                args, _ = mock_run.call_args
                cmd = args[0]
                self.assertEqual(cmd[0], "omarchy-notification-send")
                self.assertIn("0%", cmd[7])
                self.assertIn("Weekly Limit (0%)", cmd[8])
                self.assertIn("5-Hour Limit (2%)", cmd[8])

                # 2. Second run immediately after: does NOT send duplicate
                mock_run.reset_mock()
                check_and_send_quota_notifications(pdir, low_quota_groups, threshold_pct=15)
                self.assertEqual(mock_run.call_count, 0)

                # 3. Third run later while quota remains at 0%: does NOT nag/resend
                check_and_send_quota_notifications(pdir, low_quota_groups, threshold_pct=15)
                self.assertEqual(mock_run.call_count, 0)

                # 4. Quota replenishes back to 100%
                check_and_send_quota_notifications(pdir, healthy_quota_groups, threshold_pct=15)
                self.assertEqual(mock_run.call_count, 0)

                # 5. Quota drops again in the future: sends 1 notification
                check_and_send_quota_notifications(pdir, low_quota_groups, threshold_pct=15)
                self.assertEqual(mock_run.call_count, 1)

    def test_concurrent_quota_notifications(self):
        """Verify concurrent multi-monitor scans do not send duplicate notifications."""
        from unittest.mock import patch
        import concurrent.futures
        with tempfile.TemporaryDirectory() as tmpdir:
            pdir = Path(tmpdir)
            low_quota_groups = [
                {
                    "name": "Claude Models",
                    "buckets": [
                        {"id": "claude-5h", "name": "5-Hour Limit", "remainingPercent": 3},
                    ]
                }
            ]

            with patch("subprocess.run") as mock_run:
                def run_notify():
                    check_and_send_quota_notifications(pdir, low_quota_groups, threshold_pct=15)

                # Simulate 8 concurrent monitor bar threads checking quota at the exact same moment
                with concurrent.futures.ThreadPoolExecutor(max_workers=8) as ex:
                    futures = [ex.submit(run_notify) for _ in range(16)]
                    for fut in futures:
                        fut.result()

                # Exactly ONE notification must be sent across all concurrent threads
                self.assertEqual(mock_run.call_count, 1)

    def test_quota_failure_backoff(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            pdir = Path(tmpdir)
            # Initially no backoff
            in_backoff, rem = get_quota_backoff(pdir)
            self.assertFalse(in_backoff)
            self.assertEqual(rem, 0.0)

            # Record 1st failure -> 30s backoff
            b1 = record_quota_failure(pdir, "connection refused")
            self.assertEqual(b1, 30.0)
            in_backoff, rem = get_quota_backoff(pdir)
            self.assertTrue(in_backoff)
            self.assertGreater(rem, 20.0)

            # Record 2nd failure -> 60s backoff
            b2 = record_quota_failure(pdir, "connection refused")
            self.assertEqual(b2, 60.0)

            # Record success -> backoff cleared
            record_quota_success(pdir)
            in_backoff, rem = get_quota_backoff(pdir)
            self.assertFalse(in_backoff)
            self.assertEqual(rem, 0.0)


if __name__ == "__main__":
    unittest.main()
