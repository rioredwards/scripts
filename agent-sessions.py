#!/usr/bin/env python3
"""Aggregate AI coding-agent sessions across providers into one list.

Providers: Claude Code, Codex, OpenCode.
Emits TSV (one row per session) sorted newest-first:

    <epoch>\t<when>\t<provider>\t<repo>\t<title>\t<resume-payload>

resume-payload is JSON the picker wrapper uses to reattach.

A cache at ~/.cache/agent-sessions/cache.json keyed by file path + mtime lets
repeat runs skip re-parsing sessions that have not changed.
"""

from __future__ import annotations

import glob
import json
import os
import re
import sqlite3
import sys
import time
from pathlib import Path

HOME = Path.home()
LIMIT = int(os.environ.get("AGENT_SESSIONS_LIMIT", "300"))
CACHE_DIR = Path(os.environ.get("XDG_CACHE_HOME", str(HOME / ".cache"))) / "agent-sessions"
CACHE_PATH = CACHE_DIR / "cache.json"
# Generated titles (id -> {"summary", ...}), filled by agent-sessions-summarize.py.
SUMMARY_PATH = CACHE_DIR / "summaries.json"

# Loaded cache (path -> {"mtime": float, "rec": {...}}) and the cache rebuilt
# this run (drops entries whose files have vanished).
_CACHE: dict = {}
_NEW_CACHE: dict = {}


def load_cache() -> None:
    global _CACHE
    try:
        _CACHE = json.loads(CACHE_PATH.read_text())
    except Exception:
        _CACHE = {}


def save_cache() -> None:
    try:
        CACHE_PATH.parent.mkdir(parents=True, exist_ok=True)
        CACHE_PATH.write_text(json.dumps(_NEW_CACHE))
    except Exception:
        pass


def cached(path: str, mtime: float, extract):
    """Return record for `path`, reusing cache when mtime is unchanged."""
    ent = _CACHE.get(path)
    if ent and ent.get("mtime") == mtime:
        _NEW_CACHE[path] = ent
        return dict(ent["rec"])
    rec = extract()
    _NEW_CACHE[path] = {"mtime": mtime, "rec": rec}
    return dict(rec)


_TAG_DROP = re.compile(
    r"<local-command-[^>]*>.*?</local-command-[^>]*>"
    r"|<command-message>.*?</command-message>"
    r"|<bash-(input|stdout|stderr)>.*?</bash-\1>",
    re.S,
)
_SCHED = re.compile(r'<scheduled-task[^>]*\bname="([^"]+)"')
_TAGS = re.compile(r"<[^>]+>")


def clean_title(s: str, n: int = 80) -> str:
    s = s or ""
    m = _SCHED.search(s)
    if m:
        return "⏰ " + m.group(1)
    s = _TAG_DROP.sub(" ", s)
    s = _TAGS.sub(" ", s)  # strip remaining tags, keep inner text
    s = " ".join(s.split())
    if not s:
        return "(no preview)"
    return s[: n - 1] + "…" if len(s) > n else s


def rel(epoch: float) -> str:
    """Compact relative age: 30s, 10m, 1h, 4d, 3w, 1y."""
    d = max(0, int(time.time() - epoch))
    if d < 60:
        return f"{d}s"
    if d < 3600:
        return f"{d // 60}m"
    if d < 86400:
        return f"{d // 3600}h"
    if d < 604800:
        return f"{d // 86400}d"
    if d < 31536000:
        return f"{d // 604800}w"
    return f"{d // 31536000}y"


def clip(s: str, n: int = 80) -> str:
    s = " ".join((s or "").split())
    return s[: n - 1] + "…" if len(s) > n else s


# --------------------------------------------------------------------------- #
# Claude Code: ~/.claude/projects/<enc-cwd>/<sessionId>.jsonl
# --------------------------------------------------------------------------- #
def claude_extract(path: str, sid: str) -> dict:
    """Read first user message (title) + real cwd. Dir-name decode is lossy."""
    title, cwd = None, ""
    try:
        with open(path, "r", errors="ignore") as fh:
            for line in fh:
                try:
                    o = json.loads(line)
                except Exception:
                    continue
                if not cwd and isinstance(o.get("cwd"), str):
                    cwd = o["cwd"]
                if title is None and o.get("type") == "user":
                    c = o.get("message", {}).get("content")
                    raw = ""
                    if isinstance(c, str):
                        raw = c
                    elif isinstance(c, list):
                        for part in c:
                            if isinstance(part, dict) and part.get("type") == "text":
                                raw = part.get("text", "")
                                break
                    t = clean_title(raw)
                    if t != "(no preview)":  # skip pure-wrapper messages
                        title = t
                if title is not None and cwd:
                    break
    except Exception:
        pass
    cwd = cwd or str(HOME)
    return {
        "provider": "claude",
        "id": sid,
        "repo": cwd,
        "path": path,
        "title": title or "(no preview)",
        "resume": {"kind": "cli", "cwd": cwd, "cmd": ["claude", "--resume", sid]},
    }


def collect_claude() -> list[dict]:
    out = []
    for f in glob.glob(str(HOME / ".claude" / "projects" / "*" / "*.jsonl")):
        p = Path(f)
        try:
            mtime = p.stat().st_mtime
        except OSError:
            continue
        rec = cached(f, mtime, lambda f=f, p=p: claude_extract(f, p.stem))
        rec["time"] = mtime
        rec["path"] = f  # always set: stale cache entries may predate this field
        out.append(rec)
    return out


# --------------------------------------------------------------------------- #
# Codex: ~/.codex/sessions/Y/M/D/rollout-*-<uuid>.jsonl
# --------------------------------------------------------------------------- #
def codex_extract(path: str) -> dict | None:
    sid, cwd, title = None, "", None
    try:
        with open(path, "r", errors="ignore") as fh:
            for line in fh:
                try:
                    o = json.loads(line)
                except Exception:
                    continue
                if o.get("type") == "session_meta":
                    pl = o.get("payload", {})
                    sid = pl.get("id")
                    cwd = pl.get("cwd", "") or ""
                if title is None:
                    pl = o.get("payload", {})
                    raw = ""
                    if o.get("type") == "event_msg" and pl.get("type") == "user_message":
                        raw = pl.get("message", "")
                    elif pl.get("role") == "user":
                        c = pl.get("content")
                        if isinstance(c, list):
                            for part in c:
                                if isinstance(part, dict) and part.get("text"):
                                    raw = part["text"]
                                    break
                    if raw:
                        t = clean_title(raw)
                        if t != "(no preview)":
                            title = t
                if sid and title is not None:
                    break
    except Exception:
        pass
    if not sid:
        return None
    cwd = cwd or str(HOME)
    return {
        "provider": "codex",
        "id": sid,
        "repo": cwd,
        "path": path,
        "title": title or "(no preview)",
        "resume": {"kind": "cli", "cwd": cwd, "cmd": ["codex", "resume", sid]},
    }


def collect_codex() -> list[dict]:
    out = []
    root = HOME / ".codex" / "sessions"
    for f in glob.glob(str(root / "**" / "rollout-*.jsonl"), recursive=True):
        p = Path(f)
        try:
            mtime = p.stat().st_mtime
        except OSError:
            continue
        rec = cached(f, mtime, lambda f=f: codex_extract(f))
        if rec is None:
            _NEW_CACHE.pop(f, None)
            continue
        rec["time"] = mtime
        rec["path"] = f  # always set: stale cache entries may predate this field
        out.append(rec)
    return out


# --------------------------------------------------------------------------- #
# OpenCode: ~/.local/share/opencode/opencode.db -> session table (has it all)
# Single fast query, no cache needed.
# --------------------------------------------------------------------------- #
def collect_opencode() -> list[dict]:
    db = HOME / ".local" / "share" / "opencode" / "opencode.db"
    if not db.exists():
        return []
    out = []
    try:
        con = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
        for sid, directory, title, t_updated in con.execute(
            "SELECT id, directory, title, time_updated FROM session"
        ):
            out.append(
                {
                    "provider": "opencode",
                    "id": sid,
                    "repo": directory or str(HOME),
                    "time": (t_updated or 0) / 1000.0,
                    "title": clip(title or "(untitled)"),
                    "resume": {
                        "kind": "cli",
                        "cwd": directory or str(HOME),
                        "cmd": ["opencode", "--session", sid],
                    },
                }
            )
        con.close()
    except Exception:
        pass
    return out


def main() -> None:
    load_cache()
    sessions = []
    for fn in (collect_claude, collect_codex, collect_opencode):
        try:
            sessions += fn()
        except Exception:
            pass
    save_cache()

    sessions.sort(key=lambda s: s["time"], reverse=True)
    sessions = sessions[:LIMIT]

    # Prefer a generated summary when available (claude/codex first-message
    # titles are noisy; opencode already has a clean db title).
    try:
        sums = json.loads(SUMMARY_PATH.read_text())
    except Exception:
        sums = {}
    for s in sessions:
        if s["provider"] in ("claude", "codex"):
            ent = sums.get(s["id"])
            if ent and ent.get("summary"):
                s["title"] = ent["summary"]

    REPO_W = 20
    for s in sessions:
        repo = (Path(s["repo"]).name or "?") if s["repo"] else "?"
        if len(repo) > REPO_W:
            repo = repo[: REPO_W - 1] + "…"
        # Fixed-width visible column (fzf renders this as one field); the
        # resume payload rides along as a hidden tab-delimited field.
        display = f"{rel(s['time']):>3}  {s['provider']:<8}  {repo:<{REPO_W}}  {s['title']}"
        print(f"{display}\t{json.dumps(s['resume'])}")


if __name__ == "__main__":
    try:
        main()
        sys.stdout.flush()
    except BrokenPipeError:
        os.dup2(os.open(os.devnull, os.O_WRONLY), sys.stdout.fileno())
        sys.exit(0)
