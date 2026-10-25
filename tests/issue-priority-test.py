"""Exercise the actual hook with offline GitHub state."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SID = "priority-test-" + str(os.getpid())
RECORD = f"Priority source: user (P1). Session: {SID}"

class Guard(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.bin = Path(self.temp.name)
        self.state = {"labels": [{"name": "P1"}, {"name": "priority:user"}], "body": RECORD}
        gh = self.bin / "gh"
        gh.write_text("#!/bin/sh\n[ -z \"$GH_FAIL\" ] || exit 1\ncat \"$GH_STATE\"\n")
        gh.chmod(0o755)
        self.marker = Path("/tmp/claude-issue-skill-" + SID)
        self.marker.touch()
        self.env = dict(os.environ, PATH=str(self.bin)+":"+os.environ["PATH"], GH_STATE=str(self.bin / "state"))

    def tearDown(self):
        self.marker.unlink(missing_ok=True)
        self.temp.cleanup()

    def call(self, args, tool="Bash"):
        (self.bin / "state").write_text(json.dumps(self.state))
        payload = {"session_id": SID, "cwd": str(ROOT), "tool_name": tool, "tool_input": args}
        run = subprocess.run(["bash", str(ROOT / "hooks/issue-skill-guard.sh")], input=json.dumps(payload), text=True, capture_output=True, env=self.env)
        self.assertEqual(run.returncode, 0, run.stderr)
        return '"deny"' in run.stdout

    def shell(self, command):
        return self.call({"cmd": command})

    def test_cmd_needs_skill(self):
        self.marker.unlink()
        self.assertTrue(self.shell("gh issue edit 1 -R owner/repo --add-label P2"))

    def test_connector_needs_skill(self):
        self.marker.unlink()
        self.assertTrue(self.call({"repository_full_name": "owner/repo", "issue_number": 1, "title": "x"}, "mcp__github__update_issue"))

    def test_protected_downgrade(self):
        self.assertTrue(self.shell("gh issue edit 1 -R owner/repo --remove-label P1 --add-label P2"))

    def test_marker_removal(self):
        self.assertTrue(self.shell("gh issue edit 1 -R owner/repo --remove-label priority:user"))

    def test_connector_replacement(self):
        self.assertTrue(self.call({"repository_full_name": "owner/repo", "issue_number": 1, "labels": ["P2"]}, "mcp__codex_apps__github_update_issue"))

    def test_connector_remove(self):
        self.assertTrue(self.call({"repository_full_name": "owner/repo", "issue_number": 1, "label": "P1"}, "mcp__github__remove_issue_label"))

    def test_unrelated_label(self):
        self.assertFalse(self.shell("gh issue edit 1 -R owner/repo --add-label Ready"))

    def test_body_must_preserve_record(self):
        self.assertTrue(self.shell("gh issue edit 1 -R owner/repo --body 'new plan'"))
        self.assertFalse(self.shell(f"gh issue edit 1 -R owner/repo --body 'new plan\n\n{RECORD}'"))

    def test_agent_regrade(self):
        self.state = {"labels": [{"name": "P2"}], "body": f"Priority source: agent (P2). Session: {SID}"}
        self.assertFalse(self.shell(f"gh issue edit 1 -R owner/repo --remove-label P2 --add-label P3 --body 'Priority source: agent (P3). Session: {SID}'"))

    def test_legacy_unclear(self):
        self.state = {"labels": [{"name": "P1"}], "body": "old seed"}
        self.assertTrue(self.shell("gh issue edit 1 -R owner/repo --remove-label P1 --add-label P2"))
        self.assertFalse(self.shell(f"gh issue edit 1 -R owner/repo --add-label priority:user --body '{RECORD}'"))

    def test_scoped_explicit_change(self):
        command = f"RIO_PRIORITY_OK=owner/repo#1:P2 gh issue edit 1 -R owner/repo --remove-label P1 --add-label P2 --body 'Priority source: user (P2). Session: {SID}'"
        self.assertFalse(self.shell(command))
        self.assertTrue(self.shell(command.replace("repo#1", "repo#2")))

    def test_create_provenance(self):
        self.assertTrue(self.shell("gh issue create -R owner/repo --label P1 --body seed"))
        self.assertFalse(self.shell(f"gh issue create -R owner/repo --label P1,priority:user --body '{RECORD}'"))
        self.assertFalse(self.call({"repository_full_name": "owner/repo", "labels": ["P2"], "body": f"Priority source: agent (P2). Session: {SID}"}, "mcp__github__create_issue"))

    def test_failed_read_blocks_write(self):
        self.env["GH_FAIL"] = "1"
        self.assertTrue(self.shell("gh issue edit 1 -R owner/repo --add-label Ready"))
        self.assertFalse(self.shell("gh issue view 1 -R owner/repo"))

    def test_raw_api_routes_to_guarded_edit(self):
        self.assertTrue(self.shell("gh api repos/owner/repo/issues/1/labels -X PUT -f 'labels[]=P2'"))
        self.assertFalse(self.shell("gh api repos/owner/repo/issues/1/labels"))

    def test_cli_boolean_flags(self):
        for flag in ("--remove-milestone", "--remove-parent", "--remove-type"):
            self.assertTrue(self.shell(f"gh issue edit 1 -R owner/repo {flag} --remove-label P1"))
            self.assertFalse(self.shell(f"gh issue edit 1 -R owner/repo {flag}"))

    def test_multi_target_rejected(self):
        self.state = {"labels": [{"name": "P2"}], "body": f"Priority source: agent (P2). Session: {SID}"}
        self.assertTrue(self.shell(f"gh issue edit 1 2 -R owner/repo --remove-label P2 --add-label P3 --body 'Priority source: agent (P3). Session: {SID}'"))

    def test_final_raw_api_and_mixed_write(self):
        for command in ("gh api -X DELETE repos/owner/repo/issues/1/labels/P1",
                        "gh api -X PATCH repos/owner/repo/issues/1",
                        "gh api -X PATCH 'repos/owner/repo/issues/1'",
                        "gh issue edit 1 -R owner/repo --add-label Ready; gh api -X DELETE repos/owner/repo/issues/1/labels/P1"):
            self.assertTrue(self.shell(command), command)

    def test_help_without_skill(self):
        self.marker.unlink()
        self.assertFalse(self.shell("gh issue edit --help"))
        self.assertTrue(self.shell("gh issue edit --help\ngh issue edit 1 -R owner/repo --remove-label P1"))

    def test_attached_flags_and_alias(self):
        self.assertTrue(self.shell("gh issue edit 1 -Rowner/repo --remove-label=P1 --add-label=P2"))
        self.assertTrue(self.shell("gh issue new -Rowner/repo -lP1 -bseed"))

    def test_dynamic_label_rejected(self):
        self.assertTrue(self.shell('gh issue edit 1 -R owner/repo --add-label "$LABEL"'))

if __name__ == "__main__":
    unittest.main()
