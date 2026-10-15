import importlib.machinery
import importlib.util
import json
import os
import shutil
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


def proc(pm_id=3, name="dev-app-abc123", created=1000, pid=34567):
    return {"pm_id": pm_id, "name": name, "pid": pid, "pm2_env": {"created_at": created}}


class LeaseTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.env = patch.dict(os.environ, {"DEV_LEASE_DIR": self.temp.name})
        self.env.start()
        self.addCleanup(self.temp.cleanup)
        self.addCleanup(self.env.stop)
        self.record = {"id": "a" * 32, "expires": 100, "name": "dev-app-abc123", "pm_id": 3,
                       "created": 1000, "cwd": "/test", "shared": False}

    def save(self):
        lease.save(self.record)

    def test_create_records_the_named_process(self):
        with patch.object(lease, "processes", return_value=[proc(), proc(pm_id=4, name="other")]):
            token = lease.create("dev-app-abc123")
        saved = lease.read(token)
        self.assertEqual((saved["pm_id"], saved["created"]), (3, 1000))

    def test_create_refuses_missing_or_duplicate_name(self):
        for procs in ([], [proc(), proc(pm_id=4)]):
            with patch.object(lease, "processes", return_value=procs):
                with self.assertRaises(RuntimeError):
                    lease.create("dev-app-abc123")

    def test_reused_pm_id_drops_lease_and_spares_the_process(self):
        self.save()
        with patch.object(lease.time, "time", return_value=99), \
                patch.object(lease, "processes", return_value=[proc(created=2000)]), patch.object(lease, "pm2") as pm2:
            self.assertEqual(lease.renew_pid(34567), "untracked")
            lease.sweep()
            pm2.assert_not_called()
        self.assertFalse(lease.path_for(self.record["id"]).exists())

    def test_renew_extends_twelve_hours(self):
        self.save()
        with patch.object(lease, "processes", return_value=[proc()]), patch.object(lease.time, "time", return_value=200):
            self.assertEqual(lease.renew_pid(34567), self.record["id"])
        saved = lease.read(self.record["id"])
        self.assertEqual((saved["expires"], saved["shared"]), (200 + 43200, True))

    def test_untracked_process_not_adopted(self):
        self.save()
        with patch.object(lease, "processes", return_value=[proc()]):
            self.assertEqual(lease.renew_pid(45678), "untracked")

    def test_sweep_skips_unexpired_live_server(self):
        self.save()
        with patch.object(lease.time, "time", return_value=99), \
                patch.object(lease, "processes", return_value=[proc()]), patch.object(lease, "pm2") as pm2:
            lease.sweep()
            pm2.assert_not_called()
        self.assertTrue(lease.path_for(self.record["id"]).exists())

    def test_sweep_deletes_expired_server(self):
        self.save()
        gone = iter([[proc()], []])
        with patch.object(lease.time, "time", return_value=101), \
                patch.object(lease, "processes", side_effect=lambda: next(gone)), patch.object(lease, "pm2") as pm2:
            lease.sweep()
            pm2.assert_called_once_with("delete", "3")
        self.assertFalse(lease.path_for(self.record["id"]).exists())

    def test_sweep_drops_lease_of_vanished_server(self):
        self.save()
        with patch.object(lease.time, "time", return_value=99), \
                patch.object(lease, "processes", return_value=[]), patch.object(lease, "pm2") as pm2:
            lease.sweep()
            pm2.assert_not_called()
        self.assertFalse(lease.path_for(self.record["id"]).exists())

    def test_stop_never_deletes_a_different_process(self):
        self.save()
        with patch.object(lease, "processes", return_value=[proc(name="someone-else")]), \
                patch.object(lease, "pm2") as pm2:
            lease.stop(self.record["id"])
            pm2.assert_not_called()

    def test_renewal_wins_before_stop(self):
        self.save()
        with patch.object(lease.time, "time", return_value=99), patch.object(lease, "pm2") as pm2:
            lease.stop(self.record["id"], expired_only=True)
            pm2.assert_not_called()

    def test_release_preserves_reused_server(self):
        self.record["shared"] = True
        self.save()
        with patch.object(lease, "pm2") as pm2:
            lease.stop(self.record["id"], release=True)
            pm2.assert_not_called()

    def test_invalid_record_id_cannot_escape_directory(self):
        with self.assertRaises(ValueError):
            lease.read("../elsewhere")

    def test_macbook_online_reads_its_tailnet_peer(self):
        def status(*peers):
            out = json.dumps({"Peer": {str(i): {"DNSName": n, "Online": o} for i, (n, o) in enumerate(peers)}})
            return subprocess.CompletedProcess([], 0, stdout=out)
        cases = [((("rios-macbook-air.ts.net.", True), ("rio-raspberry-pi.ts.net.", False)), True),
                 ((("rios-macbook-air.ts.net.", False), ("rio-raspberry-pi.ts.net.", True)), False)]
        for peers, online in cases:
            with patch.object(lease.subprocess, "run", return_value=status(*peers)):
                self.assertIs(lease.macbook_online(), online)
        # A renamed MacBook must not read as offline forever.
        with patch.object(lease.subprocess, "run", return_value=status(("rios-macbook-pro.ts.net.", True))):
            with self.assertRaises(RuntimeError):
                lease.macbook_online()

    def test_stop_pid_refuses_untracked_server(self):
        self.save()
        with patch.object(lease, "processes", return_value=[proc()]), patch.object(lease, "pm2") as pm2:
            with self.assertRaises(RuntimeError):
                lease.main(["stop-pid", "45678"])
            pm2.assert_not_called()

    def test_no_daemon_means_no_processes_and_no_spawn(self):
        with patch.dict(os.environ, {"PM2_HOME": self.temp.name}), patch.object(lease, "pm2") as pm2:
            self.assertEqual(lease.processes(), [])
            pm2.assert_not_called()


@unittest.skipUnless(os.environ.get("DEV_LEASE_INTEGRATION"), "isolated pm2 + portless integration opt-in")
class Pm2Tests(unittest.TestCase):
    def test_portless_server_lifecycle(self):
        # Cleanups run last-in first-out: pm2 kill must reach the daemon before its home is removed.
        state = tempfile.mkdtemp(prefix="dev-lease-test-")
        self.addCleanup(shutil.rmtree, state)
        env = dict(os.environ, DEV_LEASE_DIR=state, PM2_HOME=os.path.join(state, "pm2"))
        def run(*args):
            return subprocess.check_output(args, env=env, text=True, cwd=state).strip()
        self.addCleanup(lambda: subprocess.run(["pm2", "kill"], env=env, capture_output=True))
        name = "dev-lease-test-" + os.path.basename(state)[-8:].lower()
        command = "import http.server,os; http.server.HTTPServer(('127.0.0.1',int(os.environ['PORT'])),http.server.SimpleHTTPRequestHandler).serve_forever()"
        run("pm2", "start", "portless", "--name", name, "--interpreter", "none", "--no-autorestart",
            "--kill-timeout", "20000", "--", "run", "--name", name, "/usr/bin/python3", "-c", command)
        token = run(sys.executable, str(lease.HERE), "create", name)
        pid = json.loads(run("pm2", "jlist"))[0]["pid"]
        route = None
        for _ in range(300):  # a cold pm2 + portless start can pass 10s
            routes = json.loads((Path.home() / ".portless/routes.json").read_text())
            route = next((r for r in routes if r["pid"] == pid), None)
            if route:
                try:
                    with urllib.request.urlopen("http://127.0.0.1:%s" % route["port"], timeout=1) as response:
                        self.assertEqual(response.status, 200)
                    break
                except OSError:
                    pass
            time.sleep(0.1)
        else:
            self.fail("portless test server did not answer")
        self.assertEqual(run(sys.executable, str(lease.HERE), "renew-pid", str(pid)), token)
        run(sys.executable, str(lease.HERE), "sweep")
        self.assertTrue((Path(state) / (token + ".json")).exists())
        record = json.loads((Path(state) / (token + ".json")).read_text())
        record["expires"] = 0
        (Path(state) / (token + ".json")).write_text(json.dumps(record))
        run(sys.executable, str(lease.HERE), "sweep")
        self.assertFalse((Path(state) / (token + ".json")).exists())
        self.assertEqual(json.loads(run("pm2", "jlist")), [])
        with socket.socket() as sock:
            self.assertNotEqual(sock.connect_ex(("127.0.0.1", route["port"])), 0)
        routes = json.loads((Path.home() / ".portless/routes.json").read_text())
        self.assertFalse(any(r["pid"] == pid for r in routes))


if __name__ == "__main__":
    unittest.main()
