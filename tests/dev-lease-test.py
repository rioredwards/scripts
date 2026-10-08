import importlib.machinery
import importlib.util
import json
import os
import shlex
import socket
import subprocess
import sys
import time
import urllib.request
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

# Loading an extensionless script would write a stray .pyc beside it.
sys.dont_write_bytecode = True
loader = importlib.machinery.SourceFileLoader("lease", str(Path(__file__).parents[1] / "dev-lease"))
spec = importlib.util.spec_from_loader(loader.name, loader)
lease = importlib.util.module_from_spec(spec)
loader.exec_module(lease)


class LeaseTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.env = patch.dict(os.environ, {"DEV_LEASE_DIR": self.temp.name})
        self.env.start()
        self.addCleanup(self.temp.cleanup)
        self.addCleanup(self.env.stop)
        self.record = {"id": "a" * 32, "expires": 100, "pane": "w1:p1",
                       "terminal": "term_unique", "session": "default", "cwd": "/test",
                       "shell": {"pid": 12345, "identity": "shell"},
                       "runner": {"pid": 23456, "identity": "runner"},
                       "child": {"pid": 34567, "identity": "server"}}

    def save(self):
        lease.save(self.record)

    def test_pid_zero_and_one_never_signalable(self):
        for pid in (0, 1, -1):
            with self.assertRaises(ValueError):
                lease.identity(pid)

    def test_reused_pid_fails_closed(self):
        with patch.object(lease, "identity", return_value="different"):
            with self.assertRaises(RuntimeError):
                lease.check(self.record["child"])

    def test_missing_pid_is_not_a_match(self):
        with patch.object(lease, "identity", return_value=None):
            self.assertFalse(lease.check(self.record["child"]))

    def test_renew_extends_twelve_hours(self):
        self.save()
        with patch.object(lease, "check", return_value=True), patch.object(lease.time, "time", return_value=200):
            self.assertEqual(lease.renew_pid(34567), self.record["id"])
        self.assertEqual(lease.read(self.record["id"])["expires"], 200 + 43200)

    def test_untracked_process_not_adopted(self):
        self.assertEqual(lease.renew_pid(45678), "untracked")
        self.assertEqual(list(lease.records()), [])

    def test_sweep_skips_unexpired(self):
        self.save()
        with patch.object(lease.time, "time", return_value=99), patch.object(lease, "stop") as stop:
            lease.sweep()
            stop.assert_not_called()

    def test_sweep_rechecks_expiration_under_lock(self):
        self.save()
        with patch.object(lease.time, "time", return_value=101), patch.object(lease, "stop") as stop:
            lease.sweep()
            stop.assert_called_once_with(self.record["id"], expired_only=True)

    def test_renewal_wins_before_stop(self):
        self.save()
        with patch.object(lease.time, "time", return_value=99), patch.object(lease, "herdr") as herdr:
            lease.stop(self.record["id"], expired_only=True)
            herdr.assert_not_called()

    def test_wrong_terminal_never_signals(self):
        self.save()
        with patch.object(lease, "herdr", return_value={"pane": {"terminal_id": "other"}}), \
                patch.object(lease.os, "kill") as kill:
            with self.assertRaises(RuntimeError):
                lease.stop(self.record["id"])
            kill.assert_not_called()

    def test_stop_rejects_reused_child_before_any_signal(self):
        self.save()
        with patch.object(lease, "pane_state", return_value=True), \
                patch.object(lease, "check", side_effect=RuntimeError("identity changed")), \
                patch.object(lease.os, "kill") as kill:
            with self.assertRaises(RuntimeError):
                lease.stop(self.record["id"])
            kill.assert_not_called()

    def test_invalid_record_id_cannot_escape_directory(self):
        with self.assertRaises(ValueError):
            lease.read("../elsewhere")

    def test_release_preserves_reused_server(self):
        self.record["shared"] = True
        self.save()
        with patch.object(lease, "herdr") as herdr:
            lease.stop(self.record["id"], release=True)
            herdr.assert_not_called()

    def test_registration_failure_closes_only_matching_terminal(self):
        info = {"process_info": {"shell_pid": 123, "foreground_processes": [{"pid": 123}]}}
        with patch.object(lease, "save", side_effect=OSError("disk full")), \
                patch.object(lease, "pane_state", return_value=True), \
                patch.object(lease, "herdr", side_effect=[info, {}]) as herdr:
            with self.assertRaises(OSError):
                lease.create("w1:p1", "term_unique")
            self.assertEqual(herdr.call_args.args[1:], ("pane", "close", "w1:p1"))

    def test_registration_failure_preserves_other_foreground_process(self):
        info = {"process_info": {"shell_pid": 123, "foreground_processes": [{"pid": 456}]}}
        with patch.object(lease, "save", side_effect=OSError("disk full")), \
                patch.object(lease, "pane_state", return_value=True), \
                patch.object(lease, "herdr", return_value=info) as herdr:
            with self.assertRaises(OSError):
                lease.create("w1:p1", "term_unique")
            self.assertEqual(herdr.call_count, 1)


@unittest.skipUnless(os.environ.get("DEV_LEASE_INTEGRATION"), "isolated Herdr integration opt-in")
class HerdrTests(unittest.TestCase):
    def test_expiry_renewal_and_failed_process(self):
        with tempfile.TemporaryDirectory(prefix="dev-lease-test-") as state:
            env = dict(os.environ, DEV_LEASE_DIR=state, DEV_HERDR_SESSION="codex-dev-lease-test")
            def cli(*args):
                return subprocess.check_output([sys.executable, str(lease.HERE), *args], env=env, text=True).strip()
            def herdr(*args):
                output = subprocess.check_output(["herdr", "--session", env["DEV_HERDR_SESSION"], *args], text=True)
                return json.loads(output)["result"] if output.startswith("{") else output
            workspace = herdr("workspace", "create", "--cwd", state, "--no-focus")
            root = workspace["root_pane"]["pane_id"]
            def start(command, failed=False):
                pane = herdr("pane", "split", root, "--direction", "right", "--cwd", state, "--no-focus")["pane"]["pane_id"]
                token = cli("create", pane)
                launch = ["exec", "env", "DEV_LEASE_DIR=" + state, sys.executable, str(lease.HERE), "run", token, *command]
                herdr("pane", "run", pane, shlex.join(launch))
                path = Path(state) / (token + ".json")
                for _ in range(100):
                    record = json.loads(path.read_text())
                    if "child" in record or (failed and "runner" in record):
                        return token, record
                    time.sleep(0.1)
                self.fail(herdr("pane", "read", pane, "--lines", "20"))
            other = subprocess.Popen(["sleep", "90"])
            self.addCleanup(lambda: (other.terminate(), other.wait()) if other.poll() is None else None)
            token, record = start(["sleep", "90"])
            cli("renew-pid", str(record["child"]["pid"]))
            renewed = json.loads((Path(state) / (token + ".json")).read_text())
            self.assertGreater(renewed["expires"], time.time() + 43100)
            cli("sweep")
            self.assertIsNotNone(lease.identity(record["child"]["pid"]))
            renewed["expires"] = 0
            (Path(state) / (token + ".json")).write_text(json.dumps(renewed))
            cli("sweep")
            self.assertIsNone(lease.identity(record["child"]["pid"]))
            self.assertFalse((Path(state) / (token + ".json")).exists())
            self.assertIsNone(other.poll())
            # Exercise Portless's real graceful shutdown, not only a direct child.
            name = "lease-test-" + record["id"][:12]
            command = "import http.server,os; http.server.HTTPServer(('127.0.0.1',int(os.environ['PORT'])),http.server.SimpleHTTPRequestHandler).serve_forever()"
            token, record = start(["portless", "run", "--name", name, "/usr/bin/python3", "-c", command])
            route = None
            for _ in range(100):
                routes = json.loads((Path.home() / ".portless/routes.json").read_text())
                route = next((r for r in routes if r["pid"] == record["child"]["pid"]), None)
                if route:
                    try:
                        with urllib.request.urlopen("http://127.0.0.1:%s" % route["port"], timeout=1) as response:
                            self.assertEqual(response.status, 200)
                        break
                    except OSError:
                        pass
                time.sleep(0.1)
            else:
                self.fail("Portless test server did not answer")
            # A renewal queued on the same lock must win before expiry cleanup.
            with patch.dict(os.environ, {"DEV_LEASE_DIR": state}), lease.locked():
                renewal = subprocess.Popen([sys.executable, str(lease.HERE), "renew-pid", str(record["child"]["pid"])], env=env, stdout=subprocess.PIPE, text=True)
                time.sleep(0.1)
                self.assertIsNone(renewal.poll())
            self.assertEqual(renewal.communicate(timeout=5)[0].strip(), token)
            cli("sweep")
            self.assertIsNotNone(lease.identity(record["child"]["pid"]))
            cli("stop", token)
            with socket.socket() as sock:
                self.assertNotEqual(sock.connect_ex(("127.0.0.1", route["port"])), 0)
            routes = json.loads((Path.home() / ".portless/routes.json").read_text())
            self.assertFalse(any(r["pid"] == record["child"]["pid"] for r in routes))
            token, record = start(["/usr/bin/false"])
            time.sleep(0.5)
            cli("stop", token)
            self.assertFalse((Path(state) / (token + ".json")).exists())
            token, record = start(["/nonexistent/dev-lease-test"], failed=True)
            time.sleep(0.5)
            cli("stop", token)
            self.assertFalse((Path(state) / (token + ".json")).exists())
            herdr("pane", "close", root)


if __name__ == "__main__":
    unittest.main()
