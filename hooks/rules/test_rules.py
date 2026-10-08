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

    def test_em_dash_replies_pass(self):
        """Em dashes only matter in files; replies are never bounced for them."""
        for agent in ("claude", "codex"):
            for retry in (False, True):
                for delegate in (False, True):
                    with self.subTest(agent=agent, retry=retry, delegate=delegate):
                        result = self.run_hook("response", {
                            "last_assistant_message": "one" + DASH + "two",
                            "stop_hook_active": retry,
                        }, agent, delegate)
                        self.assertEqual(result.returncode, 0, result.stderr)

    def test_payload_delegate(self):
        result = self.run_hook("response", {
            "last_assistant_message": "fallback", "agent_id": "test-subagent",
        })
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_clean_response_and_ordinary_retry(self):
        for text, retry, delegate in (("Okay - done.", False, False),
                                      ("fallback", True, False),
                                      ("fallback", False, True)):
            result = self.run_hook("response", {
                "last_assistant_message": text, "stop_hook_active": retry,
            }, delegate=delegate)
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_asks_must_name_step_5(self):
        for text, code in (("❓ Your call on the key: keep or remove?", 2),
                           ("❓ Merge to prod?\nWhy you: it ships to customers.", 0),
                           ("Want me to make that edit in agent-skills?", 2),
                           ('Build the age gate?', 2),
                           ('▶️ Next card: #445?', 2),
                           ('Should the webview be mini-only?', 2),
                           ('Two-line guard, or leave it?', 2),
                           ('Yes / no / change?', 2),
                           ('Okay to merge?', 2),
                           ('Merged? No, the PR waits on CI.', 0),
                           ('Tests pass. Built the age gate.', 0),
                           ("Kept the key and labeled it.", 0)):
            with self.subTest(text=text):
                result = self.run_hook("response", {"last_assistant_message": text})
                self.assertEqual(result.returncode, code, result.stderr)

    def test_pr_issue_titles(self):
        allowed = [
            'An account record is a distributor entry. Safeway Store #123, account 45678.',
            'Store #123; order #456; invoice #789; ticket #42.',
            'Color #123456 and entity &#123; are ordinary text.',
            '[Fix label printing (#924)](https://github.com/owner/repo/pull/924)',
            '[Fix label printing (#7)](https://github.com/owner/repo/issues/7)',
            'Store #123. [Fix label printing (#924)](https://github.com/owner/repo/pull/924)',
        ]
        blocked = [
            'PR #924 is ready.', 'Issue #7 is open.', 'PR 7 is ready.',
            'Issues #12 and #13 are open.', 'owner/repo#924 is ready.',
            'toolbox#7 is open.', 'Pull request #7 is ready.',
            'Pull requests 12 and 13 are open.',
            '[#924](https://github.com/owner/repo/pull/924)',
            '[Issue #7](https://github.com/owner/repo/issues/7)',
            '[#7](https://github.com/owner/repo/issues/7)',
            '[PR 7](https://github.com/owner/repo/pull/7)',
            '[7](https://github.com/owner/repo/issues/7)',
            '[Fix label printing (#924)](https://github.com/owner/repo/pull/924); issue #7 is open.',
        ]
        for agent in ('claude', 'codex'):
            for text in allowed + blocked:
                with self.subTest(agent=agent, text=text):
                    result = self.run_hook('response', {'last_assistant_message': text}, agent)
                    self.assertEqual(result.returncode, 2 if text in blocked else 0, result.stderr)
                    if text in blocked:
                        self.assertIn('pr-issue-titles', result.stderr)

    def test_tool_inputs(self):
        """Em dashes are denied only when they are being written into a file."""
        blocked = [
            ("Write", {"content": DASH}),
            ("Edit", {"old_string": "before", "new_string": DASH}),
            ("MultiEdit", {"edits": [{"old_string": "a", "new_string": DASH}]}),
            ("NotebookEdit", {"new_source": DASH}),
            ("apply_patch", "*** Begin Patch\n+" + DASH),
            ("Bash", {"command": "echo " + DASH + " > notes.md"}),
            ("Bash", {"command": "cat > app.ts <<EOF\n" + DASH + "\nEOF"}),
            ("Bash", {"command": "printf x" + DASH + " | tee out.txt"}),
            ("Bash", {"command": "sed -i '' 's/-/" + DASH + "/' f.md"}),
            ("exec_command", {"cmd": "echo " + DASH + " >> notes.md"}),
        ]
        allowed = [
            ("Bash", {"command": "pwd", "description": DASH}),
            ("Bash", {"command": "echo " + DASH}),
            ("Bash", {"command": "grep -rn " + DASH + " src 2>/dev/null"}),
            ("Bash", {"command": "echo " + DASH + " 2>&1"}),
            ("Bash", {"command": "git commit -m \"$(cat <<'EOF'\na " + DASH + " b\n\nCo-Authored-By: X <x@y.z>\nEOF\n)\""}),
            ("exec_command", {"cmd": "echo " + DASH}),
            ("mcp__service__update", {"command": "update", "body": DASH}),
            ("Bash", {"command": "python3 -c 'print(\"<script type=application/json>" + DASH + "\")'"}),
        ]
        for agent in ("claude", "codex"):
            for name, data in blocked:
                with self.subTest(agent=agent, blocked=data):
                    result = self.run_hook("tool", {"tool_name": name, "tool_input": data}, agent)
                    self.assertEqual(result.returncode, 0)
                    verdict = json.loads(result.stdout)["hookSpecificOutput"]
                    self.assertEqual(verdict["permissionDecision"], "deny")
                    self.assertIn("Em dashes", verdict["permissionDecisionReason"])
            for name, data in allowed:
                with self.subTest(agent=agent, allowed=data):
                    result = self.run_hook("tool", {"tool_name": name, "tool_input": data}, agent)
                    self.assertEqual(result.returncode, 0)
                    self.assertNotIn("Em dashes", result.stdout)

    def test_dev_null_redirect_is_not_a_write(self):
        home = "/Users/rio" + "redwards/"
        reads = [
            'echo "== a =="; ls ~/scripts/hooks/rules/; echo "== b =="; sed -n 1p f 2>/dev/null',
            'echo "== a =="; ls ' + home + 'dev; cat f 2>/dev/null',
            "echo x > /dev/null; ls ~/scripts/hooks/rules/",
        ]
        writes = [
            ("echo x > ~/dev/agent-skills/LEDGER.md", "utils:system"),
            ("printf x > ~/scripts/hooks/rules/rules.json 2>/dev/null", "utils:system"),
            ("echo " + home + "dev > notes.txt", "hardcoded home"),
            ("echo x >/dev/null_other; cat ~/dev/agent-skills/f", "utils:system"),
        ]
        for cmd in reads:
            with self.subTest(read=cmd):
                out = self.run_hook("tool", {"tool_name": "Bash", "tool_input": {"command": cmd}}).stdout
                self.assertNotIn("utils:system", out)
                self.assertNotIn("hardcoded home", out)
        for cmd, expected in writes:
            with self.subTest(write=cmd):
                out = self.run_hook("tool", {"tool_name": "Bash", "tool_input": {"command": cmd}}).stdout
                self.assertIn(expected, out)

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
                           "tool_input": {"content": DASH}, "last_assistant_message": "fallback"}
                result = subprocess.run(commands[0], shell=True, input=json.dumps(payload),
                                        text=True, capture_output=True)
                if event == "PreToolUse":
                    self.assertEqual(json.loads(result.stdout)["hookSpecificOutput"]["permissionDecision"], "deny")
                elif event == "Stop":
                    self.assertEqual(result.returncode, 2, result.stderr)
                else:
                    # SubagentStop runs as a delegate: ordinary rules skip, and none are scope all.
                    self.assertEqual(result.returncode, 0, result.stderr)

    def test_ordinary_rule_still_runs(self):
        result = self.run_hook("response", {"last_assistant_message": "fallback"})
        self.assertEqual(result.returncode, 2)
        self.assertIn("no-fallbacks", result.stderr)

    def test_piped_git_push_is_blocked(self):
        """A pipe turns a refused push into exit 0; unpiped or pipefail pushes pass."""
        blocked = [
            "git push 2>&1 | tail -12",
            "cd repo && git push -u origin feat/x 2>&1 | tail",
            "git -C ~/repo push |& tee push.log",
            "git -c core.hooksPath=.githooks push origin HEAD | cat",
            "out=$(git push 2>&1 | tail -3)",
        ]
        allowed = [
            "git push",
            "git push -u origin feat/x 2>&1",
            "set -o pipefail && git push 2>&1 | tail -12",
            "git push 2>&1 | tail -5; echo ${PIPESTATUS[0]}",
            "git push && gh pr view 1 | head",
            "git log --oneline @{u}..HEAD | head",
            "git stash push -m wip | cat",
        ]
        for command in blocked:
            with self.subTest(blocked=command):
                out = self.run_hook("tool", {"tool_name": "Bash", "tool_input": {"command": command}})
                self.assertIn("git push's exit code", out.stdout)
                self.assertEqual(json.loads(out.stdout)["hookSpecificOutput"]["permissionDecision"], "deny")
        for command in allowed:
            with self.subTest(allowed=command):
                out = self.run_hook("tool", {"tool_name": "Bash", "tool_input": {"command": command}})
                self.assertNotIn("git push's exit code", out.stdout + out.stderr)

    def test_railway_is_read_only(self):
        """Railway writes and variable values are Rio's; deploy state and logs stay readable."""
        ids = {"projectId": "p", "serviceId": "s"}
        blocked = [
            ("mcp__railway__set-variables", ids),
            ("mcp__railway__list-variables", ids),
            ("mcp__railway__redeploy", ids),
            ("mcp__railway__restart-service", ids),
            ("mcp__railway__delete-service", ids),
            ("mcp__railway__accept-deploy", ids),
            ("mcp__railway__railway-agent", {"prompt": "restart it"}),
            ("Bash", {"command": "railway up"}),
            ("Bash", {"command": "railway logs && railway up --detach"}),
            ("Bash", {"command": "railway variables"}),
            ("Bash", {"command": "railway run python3 x.py"}),
            ("Bash", {"command": "railway shell"}),
            ("Bash", {"command": "railway service delete"}),
            ("Bash", {"command": "cd app; railway redeploy -y"}),
            ("mcp__railway__deploy-template", ids),
            ("mcp__railway__reset-bucket-credentials", ids),
            ("mcp__railway__get-bucket-credentials", ids),
            ("mcp__railway__retry-domain-certificate", ids),
            ("mcp__railway__test-webhook", ids),
            ("Bash", {"command": "railway --service web up"}),
            ("Bash", {"command": "railway -s web variables"}),
            ("Bash", {"command": "/opt/homebrew/bin/railway up"}),
            ("Bash", {"command": "npx @railway/cli up"}),
            ("Bash", {"command": "sh -c 'railway up'"}),
            ("Bash", {"command": "railway scale"}),
        ]
        allowed = [
            ("mcp__railway__get-status", ids),
            ("mcp__railway__list-deployments", ids),
            ("mcp__railway__get-logs", ids),
            ("Bash", {"command": "railway status"}),
            ("Bash", {"command": "railway logs --deployment abc"}),
            ("Bash", {"command": "railway deployment list"}),
            ("Bash", {"command": "grep railway README.md"}),
            ("mcp__railway__describe-service", ids),
            ("Bash", {"command": "railway service logs"}),
            ("Bash", {"command": "railway --service web status"}),
        ]
        for tool, inp in blocked:
            with self.subTest(blocked=(tool, inp)):
                result = self.run_hook("tool", {"tool_name": tool, "tool_input": inp})
                self.assertEqual(json.loads(result.stdout)["hookSpecificOutput"]["permissionDecision"], "deny")
                self.assertIn("railway", result.stdout)
        for tool, inp in allowed:
            with self.subTest(allowed=(tool, inp)):
                result = self.run_hook("tool", {"tool_name": tool, "tool_input": inp})
                self.assertNotIn("deny", result.stdout)

    def test_plugin_snapshots_are_read_only(self):
        """Installed snapshots reject writes; the source repo and reads stay open."""
        snap = "/Users/x/.cl" + "aude/rem" + "ote/plugins/h1/skills/triage/SKILL.md"
        old = "/Users/x/.cl" + "aude/plugins/ca" + "che/h1/skills/triage/SKILL.md"
        src = "/Users/x/dev/agent-skills/plugins/utils/skills/triage/SKILL.md"
        blocked = [
            ("Edit", {"file_path": snap, "old_string": "a", "new_string": "b"}),
            ("Write", {"file_path": old, "content": "hi"}),
            ("Bash", {"command": "cd %s && python3 - <<EOF\nx\nEOF" % snap}),
            ("Bash", {"command": "echo hi > %s" % snap}),
            ("Bash", {"command": "cd %s && echo hi > a.md" % snap}),
            ("Bash", {"command": "cp a.md %s" % snap}),
            ("Bash", {"command": "mv a.md %s" % snap}),
            ("Bash", {"command": "sed -i '' s/a/b/ %s" % snap}),
            ("Bash", {"command": "echo hi | tee %s" % snap}),
        ]
        allowed = [
            ("Edit", {"file_path": src, "old_string": "a", "new_string": "b"}),
            ("Bash", {"command": "cat %s" % snap}),
            ("Bash", {"command": "diff %s %s" % (src, snap)}),
            ("Bash", {"command": "grep -rn foo %s" % snap}),
            ("Bash", {"command": "cp a.md b.md; cat %s" % snap}),
            ("Bash", {"command": "cd %s && grep -n x a.md 2>/dev/null; head b.md >&2" % snap}),
            ("Bash", {"command": "claude plugin update utils@rio-agent-skills"}),
            # a file that mentions the path is not a write into it
            ("Write", {"file_path": src, "content": "import('%s')" % old}),
            # documenting the path inside the source repo is not a write to it
            ("Bash", {"command": "cd ~/dev/agent-skills && cat > R.md <<EOF\n%s\nEOF" % snap}),
        ]
        for tool, inp in blocked:
            with self.subTest(blocked=inp):
                out = self.run_hook("tool", {"tool_name": tool, "tool_input": inp})
                self.assertIn("read-only snapshots", out.stdout + out.stderr)
        for tool, inp in allowed:
            with self.subTest(allowed=inp):
                out = self.run_hook("tool", {"tool_name": tool, "tool_input": inp})
                self.assertNotIn("read-only snapshots", out.stdout + out.stderr)

    def test_env_dumps_only_in_command_position(self):
        """Only a real environment dump is denied; the word env in prose or a shebang is not."""
        blocked = [
            "env", "env | sort", "env|sort", "echo hi; env", "echo hi && env > out.txt",
            "x=$(env)", "`env`", "printenv", "printenv | cut -d= -f1", "sudo env",
            "ssh mini env", "ssh mini 'env | sort'", "ssh -o BatchMode=yes mini printenv",
            "ssh mini sudo env", "FOO=1 env", "ls\nenv\nls", "launchctl print gui/501",
            "echo a\nenv | sort",
            "/usr/bin/env", "/usr/bin/env | sort", "/usr/bin/printenv", "command env",
            "exec env", "time env", "env -0", "env -u FOO", "printenv -0", "sudo -u root env",
            "ssh mini -- env", "export", "export -p", "set", "set | grep KEY", "declare -x",
            "typeset -x", "launchctl export",
        ]
        allowed = [
            "env FOO=bar cmd", "/usr/bin/env bash", "printenv HOME", "env -i FOO=1 sh x",
            "echo use env var here", "cat > f.md <<'EOF'\nSet each env var in Vercel\nEOF",
            "cat > run.sh <<'EOF'\n#!/usr/bin/env bash\necho hi\nEOF",
            "cat > run.sh <<'EOF'\n#!/usr/bin/env python3\nEOF",
            "gh issue comment 1 --body 'env is dumped here'", "ls .env", "envsubst < a",
            "env | grep -c KEY", "printenv | wc -l", "git commit -m 'fix env handling'",
            "cat .env.example", "source .venv/bin/activate",
            "/usr/bin/env python3 script.py", "env -u FOO cmd", "command -v env", "sudo -u root ls",
            "set -euo pipefail", "set -- a b", "if [ -n \"$x\" ]; then set -x; fi", "export FOO=1",
            "export -f myfn", "declare -A map", "declare -p FOO", "launchctl getenv X",
        ]
        for command in blocked:
            with self.subTest(blocked=command):
                out = self.run_hook("tool", {"tool_name": "Bash", "tool_input": {"command": command}})
                self.assertIn("dumps the whole environment", out.stdout)
        for command in allowed:
            with self.subTest(allowed=command):
                out = self.run_hook("tool", {"tool_name": "Bash", "tool_input": {"command": command}})
                self.assertNotIn("dumps the whole environment", out.stdout)

    def test_scratchpad_paths_do_not_route_to_system_skill(self):
        """Claude scratchpad dirs embed the repo name (-dev-agent-skills/): never a system path."""
        scratch = "/private/tmp/claude-501/-Users-x-dev-agent-skills/sess/scratchpad/"
        cmds = [
            "cat > " + scratch + "a.md <<EOF\nhi\nEOF",
            "echo hi > " + scratch + "a.md",
            "sed -i s/a/b/ " + scratch + "a.md",
        ]
        for cmd in cmds:
            with self.subTest(cmd=cmd):
                out = self.run_hook("tool", {"tool_name": "Bash", "tool_input": {"command": cmd}})
                self.assertNotIn("utils:system", out.stdout)
        real = "cat > ~/dev/agent-skills/x.md <<EOF\nhi\nEOF"
        out = self.run_hook("tool", {"tool_name": "Bash", "tool_input": {"command": real}})
        self.assertIn("utils:system", out.stdout)

    def test_system_edits_route_to_system_skill(self):
        """Edit/Write into Rio's system files get the utils:system nudge; other paths do not."""
        hit = [
            ("Edit", {"file_path": "/Users/x/dev/agent-skills/LEDGER.md", "old_string": "a", "new_string": "b"}),
            ("Write", {"file_path": "/Users/x/.dotfiles/.agents/AGENTS.md", "content": "hi"}),
            ("Edit", {"file_path": "/Users/x/scripts/hooks/rules/rules.json", "old_string": "a", "new_string": "b"}),
        ]
        scratch = "/private/tmp/claude-501/-Users-x-dev-agent-skills/sess/scratchpad/notes.md"
        miss = [
            ("Write", {"file_path": "/Users/x/dev/app/README.md", "content": "hi"}),
            ("Write", {"file_path": scratch, "content": "hi"}),
            ("Edit", {"file_path": scratch, "old_string": "a", "new_string": "b"}),
        ]
        for tool, inp in hit:
            with self.subTest(hit=inp):
                out = self.run_hook("tool", {"tool_name": tool, "tool_input": inp})
                self.assertIn("utils:system", out.stdout)
        for tool, inp in miss:
            with self.subTest(miss=inp):
                out = self.run_hook("tool", {"tool_name": tool, "tool_input": inp})
                self.assertNotIn("utils:system", out.stdout)


if __name__ == "__main__":
    unittest.main()
