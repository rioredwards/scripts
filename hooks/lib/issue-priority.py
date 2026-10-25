"""Validate inspectable issue writes. No Python startup on unrelated calls."""
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys

MARK = "priority:user"
PRIORITIES = {"P1", "P2", "P3"}
RECORD = re.compile(r"^Priority source: (user|agent) \((P[123])\)\. Session: ([\w-]+)$", re.M)
VALUE_FLAGS = {
    "--repo", "-R", "--label", "-l", "--add-label", "--remove-label", "--body", "-b",
    "--body-file", "-F", "--title", "-t", "--assignee", "-a", "--add-assignee",
    "--remove-assignee", "--milestone", "-m", "--project", "-p", "--add-project",
    "--remove-project", "--parent", "--add-sub-issue", "--remove-sub-issue", "--type",
    "--blocked-by", "--blocking", "--add-blocked-by", "--remove-blocked-by",
    "--add-blocking", "--remove-blocking", "--attach",
}
BOOL_FLAGS = {"--remove-milestone", "--remove-parent", "--remove-type"}


def deny(reason):
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "issue-skill-guard: " + reason}}))
    sys.exit(0)


def gh(*args):
    try:
        result = subprocess.run(["gh", *args], cwd=payload.get("cwd") or None, capture_output=True, text=True, timeout=4, check=True)
        return json.loads(result.stdout)
    except (OSError, ValueError, subprocess.SubprocessError):
        deny("Cannot read current issue priority. Fix GitHub access and retry; no write was authorized.")


def labels(value):
    if value is None:
        return None
    if isinstance(value, str):
        return set(value.split(","))
    return {v["name"] if isinstance(v, dict) else v for v in value}


def record(body):
    matches = RECORD.findall(body)
    return matches[0] if len(matches) == 1 else None


def verify(change):
    repo, number = change.get("repo"), change.get("number")
    if not repo:
        deny("Supply --repo owner/repo or an explicit GitHub issue URL so the checked target matches the write.")
    if not re.fullmatch(r"[\w.-]+/[\w.-]+", repo):
        deny("Use an explicit owner/repo and literal issue number.")
    old = {"labels": [], "body": ""} if change["create"] else gh("issue", "view", str(number), "--repo", repo, "--json", "labels,body")
    before = labels(old["labels"])
    after = change.get("labels")
    if after is None:
        after = (before | change.get("add", set())) - change.get("remove", set())
    priorities = after & PRIORITIES
    body = change.get("body", old.get("body") or "")
    previous, current = record(old.get("body") or ""), record(body)
    altered = (before & PRIORITIES) != priorities
    protected = MARK in before or (previous and previous[0] == "user")
    known_agent = previous and previous[0] == "agent" and previous[1] in before
    override = change.get("approval") == f"{repo}#{number}:{next(iter(priorities), '')}"
    if not change["create"]:
        if (altered and (protected or not known_agent)) or (protected and MARK not in after):
            if not (override and current and current[0] == "user" and current[2] == sid and MARK in after):
                deny("Preserve priority and priority:user. Only an explicit user request permits a change: use RIO_PRIORITY_OK=owner/repo#number:Pn on gh issue edit and update the user decision record. Standing nightly approval does not authorize this.")
        if protected and current != previous and not override:
            if previous or not (current and current[0] == "user" and current[1] in priorities):
                deny("Preserve the user priority decision line when rewriting the issue body.")
    if change["create"] or altered or MARK in after or current is not None:
        if len(priorities) != 1 or not current or current[1] not in priorities or ((current[0] == "user") != (MARK in after)):
            deny("Use one P1/P2/P3 and one line: Priority source: user|agent (Pn). Session: <id>. Explicit user choices also require priority:user.")
        if change["create"] and current[2] != sid:
            deny("Record this session as the source of a new issue priority.")


def shell_changes(command):
    try:
        lexer = shlex.shlex(command, posix=True, punctuation_chars=";&|()")
        lexer.whitespace_split = True
        lexer.commenters = ""
        tokens = list(lexer)
    except ValueError:
        deny("Cannot inspect this issue write. Use a literal gh issue create/edit command.")
    for i, token in enumerate(tokens[:-1]):
        if token == "-c" or (token == "ssh" and i + 2 < len(tokens)):
            yield from shell_changes(tokens[i + (2 if token == "ssh" else 1)])
    for i in range(len(tokens) - 2):
        if Path(tokens[i]).name != "gh" or tokens[i+1] != "issue" or tokens[i+2] not in {"create", "new", "edit"}:
            continue
        args = tokens[i+3:]
        change = {"create": tokens[i+2] in {"create", "new"}, "add": set(), "remove": set()}
        approval = re.search(r"(?:^|\s)RIO_PRIORITY_OK=([^\s]+)", command)
        change["approval"] = approval[1].strip("'\"") if approval else None
        n = 0
        while n < len(args):
            arg = args[n]
            if arg in {";", "&&", "||", "|"}:
                break
            flag, eq, value = arg.partition("=")
            if not eq and len(flag) > 2 and flag[:2] in {"-R", "-l", "-b", "-F"}:
                flag, value, eq = flag[:2], flag[2:], "="
            if flag.startswith("-"):
                if flag in BOOL_FLAGS and not eq:
                    n += 1
                    continue
                if flag not in VALUE_FLAGS:
                    deny("Unsupported issue option. Use explicit title/body/labels and supported metadata flags; interactive or recovered writes cannot be inspected.")
                if not eq:
                    n += 1
                    if n >= len(args):
                        deny("Issue option needs a literal value.")
                    value = args[n]
                if flag in {"--repo", "-R", "--label", "-l", "--add-label", "--remove-label", "--body", "-b", "--body-file", "-F"} and any(c in value for c in ("$", "`")):
                    deny("Use literal priority, repository and body arguments; write a body file first for computed content.")
                if flag in {"--repo", "-R"}:
                    change["repo"] = value
                elif flag in {"--label", "-l", "--add-label"}:
                    change["add"] |= labels(value)
                elif flag == "--remove-label":
                    change["remove"] |= labels(value)
                elif flag in {"--body", "-b"}:
                    change["body"] = value
                elif flag in {"--body-file", "-F"}:
                    try:
                        path = Path(value)
                        if not path.is_absolute():
                            path = Path(payload.get("cwd") or os.getcwd()) / path
                        change["body"] = path.read_text() if value != "-" else None
                        if change["body"] is None:
                            raise ValueError()
                    except (OSError, ValueError):
                        deny("Supply an inspectable body or body file; stdin bodies cannot be checked before execution.")
            elif "number" not in change:
                target = re.fullmatch(r"https://github.com/([\w.-]+/[\w.-]+)/issues/(\d+)", arg)
                if target:
                    change["repo"], change["number"] = target.groups()
                elif arg.isdigit():
                    change["number"] = arg
                else:
                    deny("Use a literal issue number or GitHub issue URL.")
            else:
                deny("Use one issue target per write, with explicit flags.")
            n += 1
        if not change["create"] and "number" not in change:
            deny("Use a literal issue number or GitHub issue URL.")
        yield change


payload = json.load(sys.stdin)
sid = payload.get("session_id", "")
args = payload.get("tool_input") or {}
try:
    command = args.get("command", args.get("cmd", ""))
    if command:
        if sys.argv[1:] == ["api"]:
            deny("Use gh issue create/edit or the GitHub connector so priority provenance can be checked; raw issue API writes are not supported.")
        changes = list(shell_changes(command))
        if len(changes) != 1:
            deny("Use one literal gh issue create/edit per tool call.")
    else:
        operation = re.search(r"(?:create_issue|update_issue|add_issue_labels|remove_issue_label)$", payload.get("tool_name", ""))[0]
        repo = args.get("repository_full_name") or args.get("repo")
        if args.get("owner") and repo and "/" not in repo:
            repo = args["owner"] + "/" + repo
        number = args.get("issue_number", args.get("number"))
        if not repo or (operation != "create_issue" and not str(number).isdigit()):
            deny("Use repository_full_name and issue_number, or gh issue edit with an explicit owner/repo.")
        change = {"create": operation == "create_issue", "repo": repo, "number": number}
        if operation == "remove_issue_label":
            change["remove"] = {args.get("label") or args.get("name")}
        elif operation == "add_issue_labels":
            change["add"] = labels(args.get("labels")) or set()
        elif args.get("labels") is not None:
            change["labels"] = labels(args["labels"])
        if args.get("body") is not None:
            change["body"] = args["body"]
        changes = [change]
    for change in changes:
        verify(change)
except (KeyError, TypeError, ValueError, AttributeError) as error:
    deny("Cannot inspect issue mutation (" + type(error).__name__ + "). Use a literal gh issue create/edit command.")
