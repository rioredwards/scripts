"""Exercise the real hook process and live rule file without an agent session."""
import json
import os
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parent
DASH = chr(0x2014)


class RulesTests(unittest.TestCase):
    def run_hook(self, kind, payload, agent="claude", delegate=False):
        env = dict(os.environ, AGENT_RULES_FILE=str(ROOT / "rules.json"))
        env.pop("AGENT_DELEGATE", None)
        if delegate:
            env["AGENT_DELEGATE"] = "1"
        return subprocess.run(
            ["sh", str(ROOT / "run.sh"), kind, agent],
            input=json.dumps(payload), text=True, capture_output=True, env=env,
        )

    def test_responses_and_retries(self):
        for agent in ("claude", "codex"):
            for retry in (False, True):
                for delegate in (False, True):
                    with self.subTest(agent=agent, retry=retry, delegate=delegate):
                        result = self.run_hook("response", {
                            "last_assistant_message": "one" + DASH + "two",
                            "stop_hook_active": retry,
                        }, agent, delegate)
                        self.assertEqual(result.returncode, 2)
                        self.assertIn("no-em-dash-responses", result.stderr)

    def test_payload_delegate(self):
        result = self.run_hook("response", {
            "last_assistant_message": DASH, "agent_id": "test-subagent",
        })
        self.assertEqual(result.returncode, 2)

    def test_clean_response_and_ordinary_retry(self):
        for text, retry, delegate in (("Okay - done.", False, False),
                                      ("fallback", True, False),
                                      ("fallback", False, True)):
            result = self.run_hook("response", {
                "last_assistant_message": text, "stop_hook_active": retry,
            }, delegate=delegate)
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_tool_inputs(self):
        cases = [
            ("Write", {"content": DASH}),
            ("Bash", {"command": "pwd", "description": DASH}),
            ("mcp__service__update", {"command": "update", "body": DASH}),
            ("mcp__service__update", {"old_string": DASH}),
            ("Write", {"file_path": "/tmp/" + DASH, "content": "okay"}),
            ("Edit", {"old_string": "before", "new_string": DASH}),
            ("Bash", {"command": "echo " + DASH}),
            ("exec_command", {"cmd": "echo " + DASH}),
            ("mcp__service__update", {"body": DASH}),
            ("apply_patch", "*** Begin Patch\n+" + DASH),
        ]
        for agent in ("claude", "codex"):
            for name, data in cases:
                with self.subTest(agent=agent, tool=name):
                    result = self.run_hook("tool", {
                        "tool_name": name, "tool_input": data,
                    }, agent)
                    self.assertEqual(result.returncode, 0)
                    verdict = json.loads(result.stdout)["hookSpecificOutput"]
                    self.assertEqual(verdict["permissionDecision"], "deny")
                    self.assertIn("Em dashes", verdict["permissionDecisionReason"])

    def test_removing_existing_character(self):
        result = self.run_hook("tool", {"tool_name": "Edit", "tool_input": {
            "old_string": DASH, "new_string": ",", "file_path": "/tmp/test",
        }})
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")

    def test_patch_removal_and_context(self):
        patch = "*** Begin Patch\n*** Update File: example.txt\n@@\n-" + DASH + "\n+,\n unchanged " + DASH + "\n*** End Patch"
        for data in (patch, {"input": patch}, {"patch": patch}):
            result = self.run_hook("tool", {"tool_name": "apply_patch", "tool_input": data})
            self.assertEqual(result.returncode, 0)
            self.assertEqual(result.stdout, "")

    def test_registered_commands(self):
        for path, events in ((Path.home() / ".claude/settings.json", ("PreToolUse", "Stop", "SubagentStop")),
                             (Path.home() / ".codex/hooks.json", ("PreToolUse", "Stop"))):
            config = json.loads(path.read_text())
            for event in events:
                commands = [h["command"] for group in config["hooks"][event]
                            for h in group["hooks"] if "rules/run.sh" in h.get("command", "")]
                self.assertEqual(len(commands), 1)
                payload = {"hook_event_name": event, "tool_name": "Write",
                           "tool_input": {"content": DASH}, "last_assistant_message": DASH}
                result = subprocess.run(commands[0], shell=True, input=json.dumps(payload),
                                        text=True, capture_output=True)
                if event == "PreToolUse":
                    self.assertEqual(json.loads(result.stdout)["hookSpecificOutput"]["permissionDecision"], "deny")
                else:
                    self.assertEqual(result.returncode, 2, result.stderr)

    def test_ordinary_rule_still_runs(self):
        result = self.run_hook("response", {"last_assistant_message": "fallback"})
        self.assertEqual(result.returncode, 2)
        self.assertIn("no-fallbacks", result.stderr)


if __name__ == "__main__":
    unittest.main()
