"""Exercise the real hook process and live rule file without an agent session."""
import json
import os
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parent
DASH = chr(0x2014)
# A heredoc note that was denied once (Oct 2026): `build(vercel):` read as a CLI call.
PROD_GUARD_NOTE = """cat > /tmp/note.md <<'EOF'
- Agents can no longer connect to any `.neon.tech` host, pull Vercel env, deploy, or call Neon/Vercel write APIs.
- The prod URL lives only in Vercel Production env.
- Main's `apps/web/vercel.json` hard-fails every preview build.
- Rules: `neon-direct-connection`, `neon-cli-read-only`, `vercel-cli-read-only`, `vercel-api-read-only`, `vercel-mcp-read-only`.
- Rio does its one-time Vercel/Neon setup on the Neon branch (neon cleanup after).
- Vercel shows a red check on every PR push.
- https://github.com/straightaway-cocktails/straightaway-next/pull/499 "build(vercel): previews build only on a named throwaway Neon branch"
EOF"""


class RulesTests(unittest.TestCase):
    def run_hook(self, kind, payload, agent="claude", delegate=False, attention="foreground", **extra_env):
        env = dict(os.environ, AGENT_RULES_FILE=str(ROOT / "rules.json"), AGENT_ATTENTION=attention, **extra_env)
        env.pop("AGENT_DELEGATE", None)
        if delegate:
            env["AGENT_DELEGATE"] = "1"
        return subprocess.run(
            ["sh", str(ROOT / "run.sh"), kind, agent],
            input=json.dumps(payload), text=True, capture_output=True, env=env,
        )

    def test_issue_plans_and_work_comments_have_no_length_cap(self):
        body = "execution detail " * 120
        commands = [
            f"gh issue create --repo owner/repo --body '{body}'",
            f"gh issue edit 1 --repo owner/repo --add-label Ready --body '{body}'",
            f"gh issue comment 1 --repo owner/repo --body '{body}'",
            "gh issue edit 1 --repo owner/repo --body-file /tmp/plan.md",
            "gh issue create --repo owner/repo -F /tmp/seed.md",
            "gh issue comment 1 --repo owner/repo --body-file /tmp/evidence.md",
            f"gh pr comment 1 --body '{body}'",
            "gh pr comment 1 --body-file /tmp/review.md",
            f"gh pr review 1 --comment --body '{body}'",
            f"gh api repos/owner/repo/issues -f body='{body}'",
            f"gh api repos/owner/repo/issues/1 -X PATCH -f body='{body}'",
            f"gh api repos/owner/repo/issues/1/comments -f body='{body}'",
            f"gh api repos/owner/repo/pulls/1/comments -f body='{body}'",
            f"gh api repos/owner/repo/pulls/1/reviews -f body='{body}'",
            f"gh issue edit 1 --body '{body}' && gh issue edit 2 --body '{body}'",
        ]
        for agent, tool, key in (("claude", "Bash", "command"),
                                 ("codex", "exec_command", "cmd"),
                                 ("codex", "shell", "command")):
            for command in commands:
                with self.subTest(agent=agent, command=command):
                    result = self.run_hook("tool", {"tool_name": tool, "tool_input": {key: command}}, agent)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertNotIn('"permissionDecision": "deny"', result.stdout)

    def test_pr_summaries_keep_the_length_cap_and_override(self):
        body = "summary detail " * 120
        commands = [
            f"gh pr create --body '{body}'",
            f"gh pr edit 1 --body '{body}'",
            f"gh api repos/owner/repo/pulls -f body='{body}'",
            f"gh api --method PATCH repos/owner/repo/pulls/1 -f body='{body}'",
            f"gh api 'repos/owner/repo/pulls/1' -X PATCH -f body='{body}'",
            "gh pr create --body-file /tmp/summary.md",
            "gh pr edit 1 -F /tmp/summary.md",
        ]
        for agent, tool, key in (("claude", "Bash", "command"),
                                 ("codex", "exec_command", "cmd"),
                                 ("codex", "shell", "command")):
            for command in commands:
                with self.subTest(agent=agent, command=command):
                    payload = {"tool_name": tool, "tool_input": {key: command}}
                    result = self.run_hook("tool", payload, agent)
                    self.assertEqual(json.loads(result.stdout)["hookSpecificOutput"]["permissionDecision"], "deny")
                    self.assertIn("pr-body", result.stdout)
                    payload["tool_input"][key] = "RIO_LONG_OK=1 " + command
                    self.assertNotIn('"permissionDecision": "deny"', self.run_hook("tool", payload, agent).stdout)
            result = self.run_hook("tool", {"tool_name": tool, "tool_input": {key: "gh pr edit 1 --body 'Fix the import. Local checks pass.'"}}, agent)
            self.assertNotIn('"permissionDecision": "deny"', result.stdout)

    def test_ui_launches_require_verified_safety(self):
        # Only submit hook payloads. These commands are never executed.
        commands = [
            "pnpm run e2e", "npm run e2e:only", "pnpm test:e2e",
            "yarn e2e", "bun run test:e2e", "pnpm --filter desktop run e2e",
            "npx playwright test", "pnpm exec playwright test tests/app.spec.ts",
            "./node_modules/.bin/playwright test", "npx cypress run",
            "pnpm run pr:shots", "node scripts/pr-shots.mjs",
            "ssh macbook 'pnpm run e2e'", "timeout 60 npx playwright test",
            "cd /tmp && pnpm run e2e",
        ]
        for agent, tool, key in (("claude", "Bash", "command"),
                                 ("codex", "exec_command", "cmd"),
                                 ("codex", "shell", "command")):
            for command in commands:
                with self.subTest(agent=agent, command=command):
                    payload = {"tool_name": tool, "tool_input": {key: command}}
                    result = self.run_hook("tool", payload, agent)
                    self.assertEqual(json.loads(result.stdout)["hookSpecificOutput"]["permissionDecision"], "deny")
                    self.assertIn("ui-tests-need-safe-target", result.stdout)
                    for mode in ("headless", "approved", "isolated"):
                        payload["tool_input"][key] = f"RIO_UI_TEST_MODE={mode} {command}"
                        self.assertNotIn("permissionDecision", self.run_hook("tool", payload, agent).stdout)
            for command in ("pnpm test", "pnpm run typecheck", "pnpm run build",
                            "npx playwright show-report", "rg 'playwright test' .",
                            "echo 'headless: false'", "echo 'npx playwright test'",
                            "python3 - <<'PY'\ncommands = ['pnpm run e2e', '--headed']\nPY",
                            "python3 - <<'PY'\ncases = ['npx playwright test && npx cypress open', 'timeout 60 npx playwright test --headed']\nPY"):
                result = self.run_hook("tool", {"tool_name": tool, "tool_input": {key: command}}, agent)
                self.assertNotIn('"permissionDecision": "deny"', result.stdout)

    def test_explicit_visible_launches_cannot_claim_headless(self):
        commands = [
            "npx playwright test --headed", "npx playwright test --ui",
            "npx playwright test --debug", "PWDEBUG=1 npx playwright test",
            "node -e 'chromium.launch({headless: false})'",
            "python3 -c 'browser.launch(headless=False)'",
            "node -e 'electron.launch({args: []})'",
            "npx cypress open", "cypress open",
            "npx playwright test && npx cypress open",
            "cd /tmp && npx playwright test --headed",
            "agent-browser --headed open http://example.test",
        ]
        for agent, tool, key in (("claude", "Bash", "command"),
                                 ("codex", "exec_command", "cmd")):
            for command in commands:
                for mode in ("", "headless", "approved", "isolated", "approvedly"):
                    with self.subTest(agent=agent, command=command, mode=mode):
                        cmd = f"RIO_UI_TEST_MODE={mode} {command}" if mode else command
                        result = self.run_hook("tool", {"tool_name": tool, "tool_input": {key: cmd}}, agent)
                        if mode in ("approved", "isolated"):
                            self.assertNotIn("permissionDecision", result.stdout)
                        else:
                            self.assertEqual(json.loads(result.stdout)["hookSpecificOutput"]["permissionDecision"], "deny")
        payload = {"tool_name": "mcp__node_repl__js", "tool_input": {"code": "await electron.launch({})"}}
        self.assertIn("visible-tests-need-consent", self.run_hook("tool", payload).stdout)

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
                           ("Should I go ahead?\nWhy you: this plan needs your yes before work starts.", 0),
                           ("Should I go ahead?", 2),
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

    def test_bounce_is_never_approval(self):
        rules = {r["id"]: r for r in json.loads((ROOT / "rules.json").read_text())["rules"]}
        self.assertIn("never his yes", rules["ask-needs-step-5"]["text"])
        self.assertIn("never treat silence as approval", rules["away-no-questions"]["text"])

    def test_away_bounces_every_question(self):
        """attention=away: nobody answers, so even a step-5 ask bounces."""
        for text, code in (("❓ Merge to prod?\nWhy you: it ships to customers.", 2),
                           ("Okay to merge?", 2),
                           ("Tests pass. Logged the merge ask to the inbox.", 0)):
            with self.subTest(text=text):
                result = self.run_hook("response", {"last_assistant_message": text}, attention="away")
                self.assertEqual(result.returncode, code, result.stderr)
                if code:
                    self.assertIn("away-no-questions", result.stderr)
                    self.assertNotIn("ask-needs-step-5", result.stderr)

    def test_away_matches_the_same_asks(self):  # rules.json has no regex reuse, so guard the copy
        rules = {r["id"]: r for r in json.loads((ROOT / "rules.json").read_text())["rules"]}
        self.assertEqual(rules["away-no-questions"]["match"], rules["ask-needs-step-5"]["match"])

    def test_broken_knob_registry_keeps_ungated_rules(self):
        merge = {"tool_name": "Bash", "tool_input": {"command": "gh pr " + "merge 5"}}
        for knobs in ("/nonexistent/agent-knobs.json", os.devnull):
            with self.subTest(knobs=knobs):
                result = self.run_hook("tool", merge, AGENT_KNOBS_FILE=knobs)
                self.assertEqual(json.loads(result.stdout)["hookSpecificOutput"]["permissionDecision"], "deny")
                result = self.run_hook("response", {"last_assistant_message": "Okay to merge?"}, AGENT_KNOBS_FILE=knobs)
                self.assertEqual(result.returncode, 0, result.stderr)

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

    def test_wrap_up_names_not_numbers(self):
        """The next-step box cannot hold links, so it names PRs and issues in words."""
        tool = "mcp__ccd_turn__wrap_up"
        blocked = [
            {"recap": "What's left: 3 small fixes (#207, #228, #159).", "ask": "Start the three fixes?"},
            {"recap": "Done.", "ask": "Merge #42?"},
            {"recap": "Done:\n#207 fixed"},
            {"recap": "Order #5 shipped; PR#207 waits."},
        ]
        allowed = [
            {"recap": "What's left: the invite fix, error visibility, and number reset.", "ask": "Start them?"},
            {"recap": "Safeway Store #123 is mapped; color #123456 unchanged."},
        ]
        for data in blocked + allowed:
            with self.subTest(data=data):
                result = self.run_hook("tool", {"tool_name": tool, "tool_input": data})
                self.assertEqual(result.returncode, 0, result.stderr)
                if data in blocked:
                    verdict = json.loads(result.stdout)["hookSpecificOutput"]
                    self.assertEqual(verdict["permissionDecision"], "deny")
                else:
                    self.assertNotIn("deny", result.stdout)

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

    def test_merges_need_rio_on_every_path(self):
        """Any agent: shell gh or an MCP merge tool."""
        blocked = [
            ("Bash", {"command": "gh pr merge 12 --squash"}),
            ("exec_command", {"cmd": "gh pr merge --auto 12"}),
            ("mcp__github__merge_pull_request", {"pull_number": 12}),
            ("mcp__ccd_pr__set_auto_merge", {"enabled": True}),
        ]
        allowed = [
            ("Bash", {"command": "RIO_MERGE_OK=1 gh pr merge 12"}),
            ("Bash", {"command": "gh pr view 12 --json mergeable"}),
            ("Bash", {"command": "git merge origin/main"}),
            ("Bash", {"command": "grep -rn 'gh pr merge' hooks/"}),
            ("mcp__github__disable_pr_auto_merge", {"pull_number": 12}),
        ]
        for name, data in blocked:
            with self.subTest(blocked=data):
                out = self.run_hook("tool", {"tool_name": name, "tool_input": data}).stdout
                self.assertEqual(json.loads(out)["hookSpecificOutput"]["permissionDecision"], "deny")
        for name, data in allowed:
            with self.subTest(allowed=data):
                self.assertNotIn("merge a PR", self.run_hook("tool", {"tool_name": name, "tool_input": data}).stdout)

    def test_automations_get_the_mini_reminder(self):
        hits = [
            ("Bash", {"command": "launchctl bootstrap gui/501 ~/Library/LaunchAgents/x.plist"}),
            ("exec_command", {"cmd": "crontab -l > c; crontab c"}),
            ("Write", {"file_path": "/Users/x/Library/LaunchAgents/com.rio.job.plist", "content": "x"}),
            ("mcp__scheduled-tasks__create_scheduled_task", {"name": "daily"}),
        ]
        for name, data in hits:
            with self.subTest(hit=data):
                self.assertIn("Mac Mini", self.run_hook("tool", {"tool_name": name, "tool_input": data}).stdout)
        for cmd in ("launchctl list", "cat ~/Library/LaunchAgents/x.plist", "grep -n crontab notes.md"):
            with self.subTest(quiet=cmd):
                self.assertNotIn("Mac Mini", self.run_hook("tool", {"tool_name": "Bash", "tool_input": {"command": cmd}}).stdout)
        self.assertNotIn("Mac Mini", self.run_hook("tool", {"tool_name": "Write", "tool_input": {"file_path": "/x/notes.md", "content": "crontab -e"}}).stdout)

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

    def assert_prod_guard(self, blocked, allowed):
        """blocked: (rule id, tool, command or MCP input); allowed: (tool, command or MCP input)."""
        def payload(tool, cmd):
            if isinstance(cmd, dict):
                return {"tool_name": tool, "tool_input": cmd}
            return {"tool_name": tool, "tool_input": {"cmd" if tool == "exec_command" else "command": cmd}}
        for rule, tool, cmd in blocked:
            with self.subTest(blocked=(tool, cmd)):
                out = json.loads(self.run_hook("tool", payload(tool, cmd)).stdout)["hookSpecificOutput"]
                self.assertEqual(out["permissionDecision"], "deny")
                self.assertIn(f"[rule: {rule}]", out["permissionDecisionReason"])
        for tool, cmd in allowed:
            with self.subTest(allowed=(tool, cmd)):
                self.assertNotIn("deny", self.run_hook("tool", payload(tool, cmd)).stdout)

    def test_neon_command_guards(self):
        """Text guards block known calls; they do not prove absence of production authority."""
        host = "ep-cool-darkness-a1b2c3d4.us-east-2.aws.neon.tech"
        pooler = "ep-cool-darkness-a1b2c3d4-pooler.c-2.us-east-2.aws.neon.tech"
        api = "https://console.neon.tech/api/v2/projects/p-1/branches"
        py = "keyfor --run NEON_API_KEY -- python3 - <<'PY'\nimport json, urllib.request\n%s\nPY"
        get = py % ("req = urllib.request.Request('%s', headers={'Authorization': 'Bearer k'})\n"
                    "data = json.load(urllib.request.urlopen(req))\nneon = data['branches']" % api)
        delete = py % ("import requests\nrequests.delete('%s/br-1')" % api)
        direct, cli, rest, mcp = ("neon-direct-connection", "neon-cli-read-only",
                                  "neon-api-read-only", "neon-mcp-read-only")
        blocked = [
            (direct, "Bash", f"psql -h {host} -U neondb_owner neondb"),
            (direct, "Bash", f"psql 'postgresql://u:p@{pooler}/neondb?sslmode=require'"),
            (direct, "Bash", f"pg_dump -h {host} -d neondb > x.dump"),
            (direct, "Bash", f"pg_restore -d 'postgres://u:p@{host}/neondb' x.dump"),
            (direct, "Bash", f"pgcli postgres://u:p@{host}/neondb"),
            (direct, "Bash", f"DATABASE_URL=postgres://u:p@{host}/neondb pnpm db:migrate"),
            (direct, "Bash", f"PGHOST={host} psql neondb"),
            (direct, "Bash", "psql \"host=db.neon.tech dbname=neondb\""),
            (direct, "Bash", "psql --host=db.neon.tech neondb"),
            (direct, "exec_command", f"psql -h {host} neondb"),
            (direct, "mcp__postgres__query", {"url": f"postgres://u:p@{host}/neondb"}),
            (cli, "Bash", "neonctl connection-string"),
            (cli, "Bash", "neonctl cs main --project-id p-1"),
            (cli, "Bash", "neonctl branches create --name x"),
            (cli, "Bash", "neonctl branches delete br-1"),
            (cli, "Bash", "neonctl branches rename a b"),
            (cli, "Bash", "neonctl branches restore main ^self@2026-10-25"),
            (cli, "Bash", "neonctl branches set-default br-1"),
            (cli, "Bash", "neonctl branches set-primary br-1"),
            (cli, "Bash", "neonctl databases list"),
            (cli, "Bash", "neonctl roles list"),
            (cli, "Bash", "neonctl set-context --project-id p-1"),
            (cli, "Bash", "neonctl auth"),
            (cli, "Bash", "neonctl ip-allow add 1.2.3.4"),
            (cli, "Bash", "neon branches delete br-1"),
            (cli, "Bash", "npx neonctl@latest branches delete br-1"),
            (cli, "Bash", "neonctl projects list && neonctl branches delete br-1"),
            (cli, "Bash", "neonctl --api-key x branches delete br-1"),
            (cli, "Bash", "keyfor --run NEON_API_KEY -- neonctl branches delete br-1"),
            (cli, "Bash", "if true; then neonctl branches delete br-1; fi"),
            (cli, "Bash", "(neon branches delete br-1)"),
            (cli, "Bash", "neonctl branches delete br-1; echo done"),
            (rest, "Bash", f"curl -X DELETE -H 'Authorization: Bearer k' {api}/br-1"),
            (rest, "Bash", f"curl -sS --request POST {api}"),
            (rest, "Bash", f"curl -s -d '{{}}' {api}"),
            (rest, "Bash", f"curl --json '{{}}' {api}"),
            (rest, "Bash", f"curl -s \\\n  -X PATCH \\\n  {api}/br-1"),
            (rest, "Bash", "curl https://console.neon.tech/api/v2/projects/p-1/connection_uri?role_name=x"),
            (rest, "Bash", f"curl {api}/b/roles/r/reveal_password"),
            (rest, "Bash", "RIO_NEON_WRITE_OK=1 curl https://console.neon.tech/api/v2/projects/p-1/connection_uri"),
            (rest, "Bash", delete),
            (rest, "Bash", py % f"urllib.request.Request('{api}/b', method=\"DELETE\")"),
            (rest, "Bash", f"node -e \"fetch('{api}', {{method: 'POST'}})\""),
            (mcp, "mcp__neon__run_sql", {"sql": "drop table x"}),
            (mcp, "mcp__neon__get_connection_string", {}),
            (mcp, "mcp__neon__run_sql_transaction", {}),
            (mcp, "mcp__neon__prepare_database_migration", {}),
            (mcp, "mcp__neon__complete_database_migration", {}),
            (mcp, "mcp__neon__provision_neon_auth", {}),
            (mcp, "mcp__neon__delete_branch", {}),
            (mcp, "mcp__plugin_neon_neon__run_sql", {}),
        ]
        allowed = [
            ("Bash", "grep neon.tech"),
            ("Bash", "grep -rh neon.tech docs"),
            ("Bash", "git commit -m \"neon cleanup\""),
            ("Bash", "gh pr view 448"),
            ("Bash", "echo 'see https://neon.tech/docs/connect'"),
            ("Bash", "psql postgres://localhost/straightaway_next_dev"),
            ("Bash", "psql -h 127.0.0.1 straightaway_next_test"),
            ("Bash", "pnpm db:migrate"),
            ("Bash", "createdb x"),
            ("Bash", "pg_restore -d straightaway_next_recovery_check file.dump"),
            ("Bash", "neonctl projects list"),
            ("Bash", "neonctl projects get p-1"),
            ("Bash", "neonctl branches list --project-id p-1 -o json"),
            ("Bash", "neonctl -o json branches get main"),
            ("Bash", "neonctl me"),
            ("Bash", "neonctl orgs list"),
            ("Bash", "neonctl operations list --project-id p-1"),
            ("Bash", "neonctl --help"),
            ("Bash", "neonctl --version"),
            ("Bash", "neonctl branches --help"),
            ("Bash", "neon projects list"),
            ("Bash", "keyfor --run NEON_API_KEY -- neonctl branches list"),
            ("Bash", f"curl -s -H 'Authorization: Bearer k' {api}"),
            ("Bash", f"curl -s {api} | jq . | cut -d ' ' -f1"),
            ("Bash", get),
            # Rio's explicit yes for that call: the documented write override
            ("Bash", f"RIO_NEON_WRITE_OK=1 curl -X DELETE {api}/br-1"),
            ("Bash", "RIO_NEON_WRITE_OK=1 " + delete),
            ("mcp__neon__list_projects", {}),
            ("mcp__neon__describe_branch", {}),
            ("mcp__neon__get_database_tables", {}),
            ("Bash", "python3 - <<'PY'\nneon = 2\nPY"),
            # prose: neon as a word, not a command token; neon.tech without a host shape
            ("Bash", PROD_GUARD_NOTE),
            ("Bash", "echo 'connect to any .neon.tech host' >> notes.md"),
            ("Bash", "echo \"the Neon branch (neon cleanup) is done\""),
            ("Bash", "git commit -m \"fix(neon): cleanup\""),
            ("Bash", "grep -E \"neon|vercel\" notes.md"),
            ("Bash", "grep -c \"neonctl branches delete\" notes.md"),
        ]
        self.assert_prod_guard(blocked, allowed)

    def test_vercel_is_read_only(self):
        """Deploys and anything that loads Vercel-held secrets are Rio's; status and logs stay open."""
        cli, mcp, api = "vercel-cli-read-only", "vercel-mcp-read-only", "vercel-api-read-only"
        blocked = [(cli, "Bash", cmd) for cmd in (
            "vercel", "vercel --debug", "vercel .", "vercel apps/web", "vercel deploy",
            "vercel --prod", "vercel deploy --prod", "vercel build", "vercel build --prod",
            "vercel build --target production", "vercel dev", "vercel redeploy dpl_1",
            "vercel promote dpl_1", "vercel rollback", "vercel rm dpl_1", "vercel remove x",
            "vercel alias set a b", "vercel domains ls", "vercel dns ls", "vercel certs ls",
            "vercel pull --environment=production", "vercel link --yes", "vercel git connect",
            "vercel integration add neon", "vercel teams switch x", "vercel api /v9/projects",
            "vercel secrets ls", "vercel rolling-release start", "vercel project rm x",
            "vercel project add x", "vercel env pull .env.prod", "vercel env add X production",
            "vercel env rm X", "vercel blob del x", "vercel ls --prod",
            "vercel ls && vercel env pull", "vercel ls; vercel deploy",
            "vercel logout && vercel env pull", "vc logout; vc deploy",
            "cd apps/web && vercel --prod --yes", "npx vercel@latest deploy",
            "npx --yes vercel env pull", "pnpm dlx vercel deploy",
            "pnpm -C apps/web exec vercel deploy", "/opt/homebrew/bin/vercel deploy",
            "sh -c 'vercel deploy'", "bash -lc \"vercel env pull\"",
            "ssh mini 'cd x && vercel deploy'", "ssh mini vercel deploy",
            "VERCEL_ORG_ID=x vercel deploy", "x=$(vercel env pull)",
            "vercel --scope straightaway deploy", "bash <<'EOF'\nvercel deploy\nEOF",
            "vc", "vc deploy", "vc --prod", "vc env pull", "npx vc deploy",
            "vc deploy --prod", "cd apps/web && vercel --prod", "npx vercel deploy",
            "pnpm dlx vercel pull", "pnpm exec vercel env pull", "vercel; echo done",
            "if true; then vercel deploy; fi", "for d in a; do vercel deploy; done",
            "(cd apps/web && vercel deploy)", "(vercel deploy)", "true && { vercel deploy; }",
            "cat <(vercel env pull /dev/stdout)", "/bin/zsh -c \"vercel env pull\"",
            "bash --norc -c 'vercel deploy'",
        )] + [(api, "Bash", cmd) for cmd in (
            "curl -s -H \"Authorization: Bearer $VERCEL_TOKEN\" 'https://api.vercel.com/v9/projects/prj_x/env?decrypt=true'",
            "curl https://api.vercel.com/v10/projects/prj_x/env/env_1",
            "curl -X POST https://api.vercel.com/v13/deployments -d @body.json",
            "curl -X DELETE https://api.vercel.com/v9/projects/prj_x",
            "curl --request PATCH https://api.vercel.com/v9/projects/prj_x",
            "curl -X POST https://api.vercel.com/v1/integrations/deploy/prj_x/abc",
            "python3 -c \"import requests; requests.post('https://api.vercel.com/v13/deployments', json={})\"",
        )] + [
            (cli, "exec_command", "vercel env pull"),
            (cli, "shell", "vercel deploy"),
            (mcp, "mcp__vercel__deploy_to_vercel", {}),
            (mcp, "mcp__vercel__buy_domain", {}),
            (mcp, "mcp__plugin_vercel_vercel__deploy_to_vercel", {}),
        ]
        allowed = [("Bash", cmd) for cmd in (
            "vercel ls", "vercel list", "vercel inspect https://x.vercel.app --logs",
            "vercel logs https://x.vercel.app --json", "vercel whoami", "vercel env ls",
            "vercel env ls production", "vercel project ls", "vercel project inspect x",
            "vercel help deploy", "vercel --version", "vercel -v", "vercel --help",
            "vercel --scope straightaway ls", "vercel -S straightaway logs x",
            "npx vercel@latest ls", "x=$(vercel ls)", "cd apps/web && vercel ls",
            "grep vercel README.md", "cat apps/web/vercel.json",
            "git commit -m \"fix vercel deploy notes\"", "pnpm add -D vercel",
            "npm i -g vercel@latest", "which vercel neonctl", "pnpm build",
            "python3 - <<'PY'\nvercel = 1\nPY",
            "vc ls", "vc logs https://x.vercel.app", "which vc",
            "vercel logout", "vc logout",
            "curl -s -H \"Authorization: Bearer $VERCEL_TOKEN\" https://api.vercel.com/v9/projects",
            "curl 'https://api.vercel.com/v6/deployments?projectId=prj_x&limit=5'",
            "grep -rn api.vercel.com docs",
            # prose and arguments: vercel/vc is a word here, not a command token
            PROD_GUARD_NOTE, "git commit -m \"docs: vercel env notes\"",
            "git commit -m \"build(vercel): previews\"", "grep -r \"vercel env pull\" docs/",
            "echo \"run vercel deploy later\" >> notes.md", "pnpm --filter web build",
            "echo \"the CLI (vercel deploy) is blocked\"", "grep -c \"vercel env pull\" notes.md",
            "jq '.rules[] | select(.id | test(\"neon|vercel|railway\"))' rules.json",
            "ls node_modules/vercel/", "grep vc: notes.md", "echo vercel-cli-read-only",
        )] + [
            ("mcp__vercel__list_deployments", {}),
            ("mcp__vercel__get_deployment_build_logs", {}),
            ("mcp__vercel__search_vercel_documentation", {}),
            ("mcp__vercel__web_fetch_vercel_url", {}),
        ]
        self.assert_prod_guard(blocked, allowed)

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

    def test_piped_pytest_only_blocks_full_runs(self):
        """A piped full suite is denied; a piped single test file is a focused run."""
        blocked = ["pytest -q | tail -5", "python3 -m pytest -q 2>&1 | tail -3"]
        allowed = [
            "python3 -m pytest -q hooks/rules/test_rules.py 2>&1 | tail -3",
            "pytest -q tests/unit/test_a.py | tail",
            "pytest -q -k ledger | tail",
        ]
        for cmd in blocked:
            with self.subTest(blocked=cmd):
                out = self.run_hook("tool", {"tool_name": "Bash", "tool_input": {"command": cmd}})
                self.assertIn("piping a full pytest run", out.stdout)
        for cmd in allowed:
            with self.subTest(allowed=cmd):
                out = self.run_hook("tool", {"tool_name": "Bash", "tool_input": {"command": cmd}})
                self.assertNotIn("piping a full pytest run", out.stdout)

    def test_raw_tabs_are_never_written(self):
        """Sheets writes aimed at a distributor Raw tab are denied; reads and other tabs pass."""
        raw = "Springboard-" + "Raw"
        py = "service.spreadsheets().values().%s(spreadsheetId=ID, range='" + raw + "!A1', body=b).execute()"
        denied = [
            ("Bash", {"command": "python3 -c \"" + py % "append" + "\""}),
            ("Bash", {"command": "python3 -c \"" + py % "update" + "\""}),
            ("Bash", {"command": "gws sheets spreadsheets values append --params '{\"range\":\"Columbia-Full-" + "Raw!A1\"}'"}),
            ("Bash", {"command": "gog sheets append ID '" + raw + "!A1' a b"}),
            ("Bash", {"command": "curl -X POST https://sheets.googleapis.com/v4/spreadsheets/ID/values/" + raw + "!A1:append"}),
            ("Write", {"file_path": "/tmp/x.py", "content": "ws = sh.worksheet('Americal-" + "Raw')\nws.update('A1', rows)\n"}),
            ("Write", {"file_path": "/tmp/x.py", "content": "r = {'appendCells': {}}  # Romano-" + "Raw sheetId"}),
        ]
        allowed = [
            ("Bash", {"command": "python3 -c \"" + py % "get" + "\""}),
            ("Bash", {"command": "gog sheets get ID '" + raw + "!A1:Z9'"}),
            ("Bash", {"command": "python3 -c \"" + (py % "append").replace(raw, "Springboard-Clean") + "\""}),
            ("Bash", {"command": "grep -n 'append' foo.py && echo " + raw}),
        ]
        for tool, inp in denied:
            with self.subTest(denied=inp):
                out = self.run_hook("tool", {"tool_name": tool, "tool_input": inp})
                self.assertIn("deny", out.stdout)
                self.assertIn("Raw tabs", out.stdout)
        for tool, inp in allowed:
            with self.subTest(allowed=inp):
                out = self.run_hook("tool", {"tool_name": tool, "tool_input": inp})
                self.assertNotIn("Raw tabs", out.stdout)

    def test_system_edits_route_to_system_skill(self):
        """Edit/Write into Rio's system files get the utils:system nudge; other paths do not."""
        hit = [
            ("Edit", {"file_path": "/Users/x/dev/agent-skills/LEDGER.md", "old_string": "a", "new_string": "b"}),
            ("Write", {"file_path": "/Users/x/.dotfiles/.agents/AGENTS.md", "content": "hi"}),
            ("Edit", {"file_path": "/Users/x/scripts/hooks/rules/rules.json", "old_string": "a", "new_string": "b"}),
            ("Edit", {"file_path": "/Users/x/.dotfiles/MACHINE_SETUP.md", "old_string": "a", "new_string": "b"}),
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

    def test_dotfiles_shell_writes_route_to_system_skill(self):
        """Shell writes into ~/.dotfiles (incl. symlinks) get the nudge; reads do not."""
        hit = [
            "ln -s ../.agents/skills ~/.dotfiles/.claude/skills",
            "D=~/.dotfiles; mv a $D/.agents/skills/",
            "cat >> ~/.dotfiles/.gitignore <<EOF\nx\nEOF",
        ]
        miss = [
            "ls -la ~/.dotfiles/.agents/skills",
            "git -C ~/.dotfiles status --short",
            "ln -s a ~/dev/app/b",
        ]
        for cmd in hit:
            with self.subTest(hit=cmd):
                out = self.run_hook("tool", {"tool_name": "Bash", "tool_input": {"command": cmd}})
                self.assertIn("utils:system", out.stdout)
        for cmd in miss:
            with self.subTest(miss=cmd):
                out = self.run_hook("tool", {"tool_name": "Bash", "tool_input": {"command": cmd}})
                self.assertNotIn("utils:system", out.stdout)

    def test_subagent_skill_line(self):
        """Subagent briefs must say which skill to load (or none); web lookups are exempt."""
        def spawn(prompt, kind="core:reviewer"):
            return self.run_hook("tool", {"tool_name": "Agent", "tool_input": {
                "description": "x", "prompt": prompt, "subagent_type": kind}})
        blocked = spawn("review the diff")
        self.assertEqual(json.loads(blocked.stdout)["hookSpecificOutput"]["permissionDecision"], "deny")
        self.assertIn("deny", spawn("Do X. Mention the Skill: line later.").stdout)
        for out in (spawn("Skill: core:review (plugins/core/skills/review/SKILL.md). Load it first."),
                    spawn("Skill: none\nfind the config"),
                    spawn("read this url", "web-fetch")):
            self.assertNotIn("deny", out.stdout)


if __name__ == "__main__":
    unittest.main()
