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
import hashlib
import html
import json
import os
import re
import sqlite3
import sys
import textwrap
import time
from pathlib import Path

HOME = Path.home()
LIMIT = int(os.environ.get("AGENT_SESSIONS_LIMIT", "300"))
CACHE_DIR = Path(os.environ.get("XDG_CACHE_HOME", str(HOME / ".cache"))) / "agent-sessions"
CACHE_PATH = CACHE_DIR / "cache.json"
# Generated titles (id -> {"summary", ...}), filled by agent-sessions-summarize.py.
SUMMARY_PATH = CACHE_DIR / "summaries.json"
# Deterministic per-repo Nerd Font icon (full dir path -> glyph string), derived
# locally from the dir name and self-populated by this picker on cache miss.
REPO_ICON_PATH = CACHE_DIR / "repo-icons.json"
FOLDER_GLYPH = ""  # nf-fa-folder, used when derivation finds nothing

try:  # icon derivation is optional; picker still runs without it
    import sesh_icons
except Exception:
    sesh_icons = None

# Loaded cache (path -> {"mtime": float, "rec": {...}}) and the cache rebuilt
# this run (drops entries whose files have vanished).
_CACHE: dict = {}
_NEW_CACHE: dict = {}
CACHE_FORMAT_VERSION = 2
SUMMARY_CONTEXT_VERSION = 2
_CACHE_VERSION_KEY = "__format_version__"


def load_cache() -> None:
    global _CACHE
    try:
        data = json.loads(CACHE_PATH.read_text())
        _CACHE = data if isinstance(data, dict) and data.get(_CACHE_VERSION_KEY) == CACHE_FORMAT_VERSION else {}
    except Exception:
        _CACHE = {}


def save_cache() -> None:
    try:
        CACHE_PATH.parent.mkdir(parents=True, exist_ok=True)
        CACHE_PATH.write_text(json.dumps({_CACHE_VERSION_KEY: CACHE_FORMAT_VERSION, **_NEW_CACHE}))
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
_TAG = re.compile(r"<\s*(/?)\s*([A-Za-z][\w:-]*)([^<>]*)>", re.S)
_ATTR = re.compile(r"\b([A-Za-z_:][\w:.-]*)\s*=\s*(['\"])(.*?)\2", re.S)
_AGENTS_HEADER = re.compile(
    r"(?mi)^# AGENTS\.md instructions(?: for [^\r\n]+)?\s*\r?\n(?:\s*\r?\n)?(?=<INSTRUCTIONS\b)"
)
_INJECTED_TAGS = {
    "user_instructions",
    "system_instructions",
    "system-instructions",
    "developer_instructions",
    "developer-instructions",
    "skills_instructions",
    "skills-instructions",
    "system-reminder",
    "environment_context",
    "ide_opened_file",
    "ide_selection",
    "ide_diagnostics",
    "task-notification",
    "turn_aborted",
    "command-name",
    "command-message",
    "command-args",
    "scheduled-task",
    "bash-input",
    "bash-stdout",
    "bash-stderr",
    "skill",
}
_REF_MARKER = re.compile(r"\[ref:(?:file|skill) name=[^\]\r\n]+\]")


def _is_injected_tag(name: str) -> bool:
    return name in _INJECTED_TAGS or name.startswith("local-command-")


def _safe_ref(kind: str, value: str) -> str:
    value = html.unescape(value).strip()
    if kind == "file":
        value = re.split(r"[/\\]", value)[-1]
    valid = value and len(value) <= 100 and not re.search(r"[\x00-\x1f\[\]]", value)
    if kind == "skill":
        valid = bool(valid and re.fullmatch(r"[A-Za-z0-9._/-]+", value))
    return f"[ref:{kind} name={value}]" if valid else ""


def _region_refs(region: str) -> list[str]:
    refs: list[str] = []
    for match in _TAG.finditer(region):
        if match.group(1):
            continue
        name = match.group(2).lower()
        attrs = {key.lower(): value for key, _, value in _ATTR.findall(match.group(3))}
        ref = ""
        if name in ("file", "context_file", "instruction_file"):
            ref = _safe_ref("file", attrs.get("name") or attrs.get("path") or "")
        elif name == "skill":
            value = attrs.get("name", "")
            if not value:
                end = region.find("</skill>", match.end())
                body = region[match.end() : end if end >= 0 else len(region)]
                nested = re.search(r"<name>\s*([^<]+?)\s*</name>", body, re.I | re.S)
                value = nested.group(1) if nested else ""
            ref = _safe_ref("skill", value)
        if ref and ref not in refs:
            refs.append(ref)
    return refs


def _matching_region(s: str, opening: re.Match) -> tuple[int, str] | None:
    """Return end offset and full balanced injected region, or None."""
    name = opening.group(2).lower()
    if opening.group(3).rstrip().endswith("/"):
        return opening.end(), opening.group(0)
    depth = 1
    for match in _TAG.finditer(s, opening.end()):
        nested = match.group(2).lower()
        if nested != name:
            continue
        if match.group(1):
            depth -= 1
            if depth == 0:
                return match.end(), s[opening.start() : match.end()]
        elif not match.group(3).rstrip().endswith("/"):
            depth += 1
    return None


def _compact_injected_context(raw: str) -> str:
    """Replace balanced harness-owned context with small provenance refs."""
    s = raw or ""
    out: list[str] = []
    cursor = 0
    while cursor < len(s):
        agents = _AGENTS_HEADER.search(s, cursor)
        tag = _TAG.search(s, cursor)
        if agents and (not tag or agents.start() <= tag.start()):
            opening = _TAG.match(s, agents.end())
            if not opening or opening.group(2).lower() != "instructions":
                out.append(s[cursor : agents.end()])
                cursor = agents.end()
                continue
            matched = _matching_region(s, opening)
            if not matched:
                out.append(s[cursor:])
                break
            end, _ = matched
            out.extend((s[cursor : agents.start()], " [ref:file name=AGENTS.md] "))
            cursor = end
            continue
        if not tag:
            out.append(s[cursor:])
            break
        name = tag.group(2).lower()
        if tag.group(1) or not _is_injected_tag(name):
            out.append(s[cursor : tag.end()])
            cursor = tag.end()
            continue
        matched = _matching_region(s, tag)
        if not matched:
            out.append(s[cursor:])
            break
        end, region = matched
        refs = _region_refs(region)
        out.extend((s[cursor : tag.start()], " " + " ".join(refs) + " "))
        cursor = end
    return "".join(out)


def clean_title(s: str, n: int = 80) -> str:
    s = s or ""
    m = _SCHED.search(s)
    if m:
        return "⏰ " + m.group(1)
    s = clean_text(s)
    if not s:
        return "(no preview)"
    return s[: n - 1] + "…" if len(s) > n else s


def clean_text(s: str) -> str:
    """Strip wrapper tags + collapse whitespace; no truncation. For previews."""
    s = _compact_injected_context(s or "")
    s = _TAG_DROP.sub(" ", s)
    s = _TAGS.sub(" ", s)
    return " ".join(s.split())


# Turns that aren't real conversation and must never become a session's
# first/last message or title. Callers fall through to the next real turn.
#
# Stub prose with no conversational value, matched on cleaned text.
_JUNK_TEXT = re.compile(
    r"("
    r"Caveat: The messages below were generated by the user"
    r"|\[Request interrupted"
    r"|This session is being continued from a previous conversation"
    r"|The following tool was executed by the user"
    r"|\[(Image|Paste)"
    r")",
    re.I,
)
# Bare slash-command, incl. namespaced (/caveman:compress) and a few args.
_SLASH_CMD = re.compile(r"/[a-z][\w:-]*(\s|$)", re.I)


def is_wrapper_msg(raw: str) -> bool:
    """True for non-conversational turns (slash commands, command/tool output,
    injected context, interrupt stubs) that shouldn't surface as a session's
    first/last message or title. Callers fall through to the next real turn."""
    b = clean_text(raw or "")
    conversational = _REF_MARKER.sub(" ", b).strip()
    if not conversational:
        return True
    if _JUNK_TEXT.match(conversational):
        return True
    # bare leading slash-command like "/clear" or "/caveman:compress lite"
    return bool(_SLASH_CMD.match(conversational)) and len(conversational.split()) <= 3


def clip_mid(s: str, n: int = 200) -> str:
    """Truncate to n chars by eliding the middle, keeping head + tail."""
    s = s or ""
    if len(s) <= n:
        return s
    head = (n - 1) // 2
    return s[:head] + "…" + s[-(n - 1 - head) :]


# Max chars of full conversational text kept per session for the searchable
# `body` field. Caps payload + Raycast keyword-index size; nearly all sessions
# fall well under this (text-only median is a few KB).
BODY_CAP = 40_000


def clip_body(s: str, n: int = BODY_CAP) -> str:
    """Truncate searchable body to n chars (head-keep, no ellipsis)."""
    s = s or ""
    return s if len(s) <= n else s[:n]


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


def humanize(n: int) -> str:
    """Compact token count: 890, 12k, 1.2M."""
    n = int(n or 0)
    if n < 1000:
        return str(n)
    if n < 1_000_000:
        return f"{n / 1000:.0f}k"
    if n < 10_000_000:
        return f"{n / 1_000_000:.1f}M"  # 1.2M..9.9M
    return f"{n / 1_000_000:.0f}M"  # 10M+ drops the decimal


# Log-ish buckets -> sparkline glyph, so heft reads at a glance.
_BUCKETS = [
    (1_000, "▁"),
    (5_000, "▂"),
    (20_000, "▃"),
    (50_000, "▄"),
    (100_000, "▅"),
    (250_000, "▆"),
    (500_000, "▇"),
]


def bucket_glyph(n: int) -> str:
    n = int(n or 0)
    for thresh, g in _BUCKETS:
        if n < thresh:
            return g
    return "█"


# Curated pastel palette (hex), ordered around the color wheel. Each repo
# hashes to one entry deterministically.
_REPO_PALETTE = [
    "b85651", "c86f5a", "d68a5c", "c78d2f", "d6a247", "e9b143", "d9bd5f",
    "b0b846", "9fbf68", "8bba7f", "80aa9e", "78aaa8", "6faeb8", "7fa7d6",
    "879bd1", "9a8fd0", "b58ad7", "c184c8", "d3869b", "c97283", "e2cca9",
    "a89984",
]


# Named picks from the same pastel palette, reused by the other columns.
_PASTEL = {
    "red": "b85651", "coral": "c86f5a", "amber": "d6a247", "yellow": "e9b143",
    "green": "8bba7f", "blue": "879bd1",
    "claude": "e27150", "codex": "82a3ff", "opencode": "b7b1b1",
}


def _hex_fg(hexc: str) -> str:
    """'b85651' -> truecolor ANSI foreground escape."""
    r, g, b = int(hexc[0:2], 16), int(hexc[2:4], 16), int(hexc[4:6], 16)
    return f"\033[38;2;{r};{g};{b}m"


def repo_color(repo: str) -> str:
    """Stable pastel truecolor for a repo path (same each run)."""
    h = int.from_bytes(hashlib.md5((repo or "?").encode()).digest()[:4], "big")
    return _hex_fg(_REPO_PALETTE[h % len(_REPO_PALETTE)])


def token_color(n: int) -> str:
    """Heat by token volume: yellow=small, coral=med, red=big (palette)."""
    n = int(n or 0)
    if n < 20_000:
        return _hex_fg(_PASTEL["yellow"])
    if n < 100_000:
        return _hex_fg(_PASTEL["coral"])
    return _hex_fg(_PASTEL["red"])


# --------------------------------------------------------------------------- #
# Claude Code: ~/.claude/projects/<enc-cwd>/<sessionId>.jsonl
# --------------------------------------------------------------------------- #
def _claude_msg_text(o: dict) -> str:
    """Plain text of a claude jsonl user/assistant entry, else ''."""
    if o.get("type") not in ("user", "assistant"):
        return ""
    msg = o.get("message")
    if not isinstance(msg, dict):
        return ""
    c = msg.get("content")
    if isinstance(c, str):
        return c
    if isinstance(c, list):
        return " ".join(p.get("text", "") for p in c if isinstance(p, dict) and p.get("type") == "text")
    return ""


def claude_extract(path: str, sid: str) -> dict:
    """Read first user message (title) + real cwd. Dir-name decode is lossy."""
    title, cwd, tokens = None, "", 0
    first, last = "", ""
    bodies: list[str] = []
    try:
        with open(path, "r", errors="ignore") as fh:
            for line in fh:
                try:
                    o = json.loads(line)
                except Exception:
                    continue
                if not cwd and isinstance(o.get("cwd"), str):
                    cwd = o["cwd"]
                msg = o.get("message")
                if isinstance(msg, dict):
                    us = msg.get("usage")
                    if isinstance(us, dict):
                        tokens += us.get("input_tokens", 0) + us.get("output_tokens", 0)
                raw = _claude_msg_text(o)
                if raw and not is_wrapper_msg(raw):
                    body = clean_text(raw)
                    if not first:
                        first = body
                    last = body
                    bodies.append(body)
                if title is None and o.get("type") == "user":
                    c = (msg or {}).get("content")
                    raw = ""
                    if isinstance(c, str):
                        raw = c
                    elif isinstance(c, list):
                        for part in c:
                            if isinstance(part, dict) and part.get("type") == "text":
                                raw = part.get("text", "")
                                break
                    t = clean_title(raw)
                    if t != "(no preview)" and not is_wrapper_msg(raw):
                        title = t
    except Exception:
        pass
    cwd = cwd or str(HOME)
    return {
        "provider": "claude",
        "id": sid,
        "repo": cwd,
        "path": path,
        "tokens": tokens,
        "title": title or "(no preview)",
        "first": clip_mid(first),
        "last": clip_mid(last),
        "body": clip_body(" ".join(bodies)),
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
def _codex_msg_text(o: dict) -> str:
    """Plain text of a codex rollout user/assistant entry, else ''."""
    pl = o.get("payload", {})
    if not isinstance(pl, dict):
        return ""
    if o.get("type") == "event_msg" and pl.get("type") in ("user_message", "agent_message"):
        m = pl.get("message", "")
        return m if isinstance(m, str) else ""
    if pl.get("role") in ("user", "assistant"):
        c = pl.get("content")
        if isinstance(c, list):
            return " ".join(p.get("text", "") for p in c if isinstance(p, dict) and p.get("text"))
    return ""


def codex_extract(path: str) -> dict | None:
    sid, cwd, title, tokens = None, "", None, 0
    first, last = "", ""
    bodies: list[str] = []
    try:
        with open(path, "r", errors="ignore") as fh:
            for line in fh:
                try:
                    o = json.loads(line)
                except Exception:
                    continue
                pl = o.get("payload", {})
                if isinstance(pl, dict):
                    info = pl.get("info")
                    if isinstance(info, dict):
                        tu = info.get("total_token_usage")
                        if isinstance(tu, dict):  # cumulative; last wins
                            tokens = tu.get("total_tokens", tokens)
                if o.get("type") == "session_meta":
                    sid = pl.get("id")
                    cwd = pl.get("cwd", "") or ""
                mraw = _codex_msg_text(o)
                if mraw and not is_wrapper_msg(mraw):
                    body = clean_text(mraw)
                    if not first:
                        first = body
                    last = body
                    bodies.append(body)
                if title is None:
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
                    if raw and not is_wrapper_msg(raw):
                        t = clean_title(raw)
                        if t != "(no preview)":
                            title = t
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
        "tokens": tokens,
        "title": title or "(no preview)",
        "first": clip_mid(first),
        "last": clip_mid(last),
        "body": clip_body(" ".join(bodies)),
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
        # First + last text part per session, in transcript order.
        first_last: dict[str, list[str]] = {}
        bodies: dict[str, list[str]] = {}
        for sid, data in con.execute(
            "SELECT session_id, data FROM part WHERE data LIKE '%\"type\":\"text\"%' "
            "ORDER BY session_id, time_created, id"
        ):
            try:
                d = json.loads(data)
            except Exception:
                continue
            if d.get("type") != "text":
                continue
            mraw = d.get("text", "")
            if not mraw or is_wrapper_msg(mraw):
                continue
            body = clean_text(mraw)
            fl = first_last.setdefault(sid, ["", ""])
            if not fl[0]:
                fl[0] = body
            fl[1] = body
            bodies.setdefault(sid, []).append(body)
        for sid, directory, title, t_updated, t_in, t_out, t_reason in con.execute(
            "SELECT id, directory, title, time_updated, "
            "tokens_input, tokens_output, tokens_reasoning FROM session"
        ):
            fl = first_last.get(sid, ["", ""])
            out.append(
                {
                    "provider": "opencode",
                    "id": sid,
                    "repo": directory or str(HOME),
                    "time": (t_updated or 0) / 1000.0,
                    "tokens": (t_in or 0) + (t_out or 0) + (t_reason or 0),
                    "title": clip(title or "(untitled)"),
                    "first": clip_mid(fl[0]),
                    "last": clip_mid(fl[1]),
                    "body": clip_body(" ".join(bodies.get(sid, []))),
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


def assign_icons(sessions: list[dict]) -> dict:
    """Map repo path -> Nerd Font icon, cached and de-duplicated.

    Derive only for repos not already cached (sessions arrive newest-first, so
    recent repos win the best glyph). Persist on change so steady-state runs
    just read the small cache and stay instant.
    """
    try:
        cache = json.loads(REPO_ICON_PATH.read_text())
    except Exception:
        cache = {}
    if sesh_icons is None:
        return cache
    used = set(cache.values())
    changed = False
    for s in sessions:
        repo = s.get("repo")
        if not repo or repo in cache:
            continue
        icon = sesh_icons.derive(Path(repo).name or repo, used, limit=1) or FOLDER_GLYPH
        cache[repo] = icon
        used.add(icon)
        changed = True
    if changed:
        try:
            REPO_ICON_PATH.parent.mkdir(parents=True, exist_ok=True)
            REPO_ICON_PATH.write_text(json.dumps(cache))
        except Exception:
            pass
    return cache


def build_sessions() -> list[dict]:
    """Aggregate, sort newest-first, cap, and apply generated summaries.

    Shared by every consumer (fzf renderer, --json emitter). Returns records
    with raw fields: provider, id, repo, time (epoch), tokens, title, resume.
    """
    load_cache()
    sessions = []
    for fn in (collect_claude, collect_codex, collect_opencode):
        try:
            sessions += fn()
        except Exception:
            pass
    save_cache()

    sessions.sort(key=lambda s: s["time"], reverse=True)

    # Dedupe by (provider, id), keeping the newest. Codex emits a separate
    # rollout-*.jsonl per resume/fork that reuses the same session_meta.id,
    # so the same id can appear more than once. Sorted newest-first above, so
    # the first occurrence is the one to keep.
    seen: set[tuple[str, str]] = set()
    deduped = []
    for s in sessions:
        key = (s["provider"], s["id"])
        if key in seen:
            continue
        seen.add(key)
        deduped.append(s)
    sessions = deduped[:LIMIT]

    # Prefer a generated summary when available (claude/codex first-message
    # titles are noisy; opencode already has a clean db title).
    try:
        sums = json.loads(SUMMARY_PATH.read_text())
    except Exception:
        sums = {}
    for s in sessions:
        if s["provider"] in ("claude", "codex"):
            ent = sums.get(s["id"])
            if (
                ent
                and ent.get("context_version") == SUMMARY_CONTEXT_VERSION
                and ent.get("summary")
            ):
                s["title"] = ent["summary"]
    return sessions


def emit_json(sessions: list[dict], query: str = "") -> None:
    """Clean structured output for non-terminal consumers (e.g. Raycast).

    No ANSI, no Nerd Font glyphs — raw values the consumer formats itself.

    `query` (case-insensitive) restricts output to sessions whose full
    conversation `body` matches, and attaches a `match` snippet around the
    first hit. The heavy `body` text itself is never shipped — it stays
    server-side so the consumer (Raycast) never holds 100s of MB in memory.
    """
    q = (query or "").strip().lower()
    rows = []
    for s in sessions:
        match = ""
        if q:
            body = s.get("body", "")
            # Match conversation text first (snippet-worthy); fall back to
            # metadata (repo/title/provider) so search keeps its old reach.
            i = body.lower().find(q)
            if i >= 0:
                match = clip_mid(body[max(0, i - 60) : i + len(q) + 60], 160)
            else:
                repo_name = (Path(s["repo"]).name or "") if s.get("repo") else ""
                meta = f"{s.get('title', '')} {repo_name} {s.get('provider', '')}".lower()
                if q not in meta:
                    continue
        rows.append(
            {
                "provider": s["provider"],
                "id": s["id"],
                "repo": s["repo"],
                "repoName": (Path(s["repo"]).name or "?") if s["repo"] else "?",
                "time": s["time"],
                "tokens": int(s.get("tokens", 0)),
                "title": s["title"],
                "path": s.get("path", ""),  # transcript file; lets --show skip on-disk resolution
                "first": s.get("first", ""),
                "last": s.get("last", ""),
                "match": match,
                "resume": s["resume"],
            }
        )
    json.dump(rows, sys.stdout)


# --------------------------------------------------------------------------- #
# fzf preview pane. Mirrors the Raycast detail view: a row of metadata pills,
# the session title, then "First message" / "Last message" cards. fzf calls
# this per-highlighted row with the hidden JSON field 3 emitted by emit_fzf.
# --------------------------------------------------------------------------- #
RESET = "\033[0m"
BOLD = "\033[1m"
DIM = "\033[2m"


def _pill(text: str, fg: str = "") -> str:
    """Dark rounded-ish chip: gray background, optional colored text."""
    return f"\033[48;2;45;45;45m{fg} {text} {RESET}"


def _card(text: str, width: int) -> str:
    """Wrap text inside a padded gray card spanning the preview width."""
    inner = max(8, width - 4)
    lines = textwrap.wrap(text or "(empty)", inner) or ["(empty)"]
    bg = "\033[48;2;38;38;38m"
    return "\n".join(f"{bg}  {ln:<{inner}}  {RESET}" for ln in lines)


def render_preview(data: dict) -> str:
    width = int(os.environ.get("FZF_PREVIEW_COLUMNS") or 60)
    tok = int(data.get("tokens", 0))
    prov = data.get("provider", "")
    repo = data.get("repo", "") or ""
    repo_name = Path(repo).name or "?"
    prov_fg = _hex_fg(_PASTEL.get(prov, _PASTEL["opencode"]))

    sep = f" {DIM}•{RESET} "
    pills = sep.join(
        [
            _pill(rel(data.get("time", 0))),
            _pill(f"{humanize(tok)} {bucket_glyph(tok)}", token_color(tok)),
            _pill(prov, prov_fg),
            _pill(repo_name, repo_color(repo)),
        ]
    )

    title = " ".join((data.get("title") or "(no preview)").split())
    title_lines = textwrap.wrap(title, max(8, width - 1)) or [title]

    out = [pills, ""]
    out += [f"{BOLD}{ln}{RESET}" for ln in title_lines]
    out += ["", f"{BOLD}First message{RESET}", _card(data.get("first", ""), width)]
    out += ["", f"{BOLD}Last message{RESET}", _card(data.get("last", ""), width)]
    return "\n".join(out)


def emit_fzf(sessions: list[dict]) -> None:
    repo_icon = assign_icons(sessions)

    # ANSI 256-color codes matched to the provider emoji hues. fzf needs
    # --ansi to render these. Pad raw strings *before* wrapping in color so
    # escape bytes never throw off column widths.
    RESET = "\033[0m"
    DIM = "\033[2m"
    PROV = {
        "claude": _hex_fg(_PASTEL["claude"]),  # brand orange #E27150
        "codex": _hex_fg(_PASTEL["codex"]),  # brand blue #82A3FF
        "opencode": _hex_fg(_PASTEL["opencode"]),  # brand gray #B7B1B1
    }
    REPO_W = 15
    for s in sessions:
        repo = (Path(s["repo"]).name or "?") if s["repo"] else "?"
        if len(repo) > REPO_W:
            repo = repo[: REPO_W - 1] + "…"
        tok = s.get("tokens", 0)
        size = f"{humanize(tok):>4} {bucket_glyph(tok)}"
        color = PROV.get(s["provider"], "")
        age = f"{DIM}{rel(s['time']):>3}{RESET}"
        prov = f"{color}{s['provider']:<8}{RESET}"
        icon = repo_icon.get(s["repo"], FOLDER_GLYPH)
        # Single glyph, tinted the per-repo color.
        rcolor = repo_color(s["repo"])
        icon_f = f"{rcolor}{icon}{RESET}"
        repo_c = f"{rcolor}{repo:<{REPO_W}}{RESET}"
        # Fixed-width visible column (fzf renders this as one field); the
        # resume payload rides along as a hidden tab-delimited field.
        size_c = f"{token_color(tok)}{size}{RESET}"
        display = f"{age} {size_c} {prov} {icon_f} {repo_c} {s['title']}"
        prev = json.dumps(
            {
                "time": s["time"],
                "tokens": tok,
                "provider": s["provider"],
                "repo": s["repo"],
                "title": s["title"],
                "first": s.get("first", ""),
                "last": s.get("last", ""),
            }
        )
        print(f"{display}\t{json.dumps(s['resume'])}\t{prev}")


# --------------------------------------------------------------------------- #
# Single-session full transcript: ordered [{role, text}] of real conversational
# turns (wrappers/tool-output dropped, like first/last). Powers the Raycast
# message-list view via `--show <provider:id>`. Unlike the previews, text is
# emitted with injected blocks compacted (newlines/code otherwise preserved).
# --------------------------------------------------------------------------- #
def iter_jsonl(path: str):
    """Yield parsed objects from a .jsonl file, skipping unreadable lines."""
    try:
        with open(path, "r", errors="ignore") as fh:
            for line in fh:
                try:
                    yield json.loads(line)
                except Exception:
                    continue
    except OSError:
        return


def claude_messages(path: str) -> list[dict]:
    out: list[dict] = []
    for o in iter_jsonl(path):
        if o.get("type") not in ("user", "assistant"):
            continue
        raw = _claude_msg_text(o)
        if not raw or is_wrapper_msg(raw):
            continue
        out.append({"role": o["type"], "text": _compact_injected_context(raw).strip()})
    return out


def claude_path_for(sid: str) -> str | None:
    hits = glob.glob(str(HOME / ".claude" / "projects" / "*" / f"{sid}.jsonl"))
    return max(hits, key=lambda f: Path(f).stat().st_mtime) if hits else None


def _codex_role(o: dict) -> str:
    pl = o.get("payload") if isinstance(o.get("payload"), dict) else {}
    if o.get("type") == "event_msg":
        if pl.get("type") == "user_message":
            return "user"
        if pl.get("type") == "agent_message":
            return "assistant"
    return "user" if pl.get("role") == "user" else "assistant"


def codex_messages(path: str) -> list[dict]:
    out: list[dict] = []
    for o in iter_jsonl(path):
        raw = _codex_msg_text(o)
        if not raw or is_wrapper_msg(raw):
            continue
        out.append({"role": _codex_role(o), "text": _compact_injected_context(raw).strip()})
    return out


def codex_path_for(sid: str) -> str | None:
    """Resolve a codex session id to its newest rollout file. Fallback only:
    callers normally pass the path the list already knows. The id lives in
    session_meta (the header line), not the filename, and is reused across
    forks/resumes — newest mtime matches build_sessions' dedupe."""
    best, best_mt = None, -1.0
    root = HOME / ".codex" / "sessions"
    for f in glob.glob(str(root / "**" / "rollout-*.jsonl"), recursive=True):
        for o in iter_jsonl(f):
            if o.get("type") == "session_meta" and (o.get("payload") or {}).get("id") == sid:
                try:
                    mt = Path(f).stat().st_mtime
                except OSError:
                    mt = -1.0
                if mt > best_mt:
                    best, best_mt = f, mt
            break  # session_meta is the header; only the first line matters
    return best


def opencode_messages(sid: str) -> list[dict]:
    db = HOME / ".local" / "share" / "opencode" / "opencode.db"
    if not db.exists():
        return []
    out: list[dict] = []
    try:
        con = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
        roles: dict[str, str] = {}
        for mid, data in con.execute("SELECT id, data FROM message WHERE session_id = ?", (sid,)):
            try:
                roles[mid] = json.loads(data).get("role")
            except Exception:
                continue
        for mid, data in con.execute(
            "SELECT message_id, data FROM part WHERE session_id = ? "
            "AND data LIKE '%\"type\":\"text\"%' ORDER BY time_created, id",
            (sid,),
        ):
            try:
                d = json.loads(data)
            except Exception:
                continue
            if d.get("type") != "text":
                continue
            raw = d.get("text", "")
            if not raw or is_wrapper_msg(raw):
                continue
            role = roles.get(mid)
            out.append(
                {
                    "role": role if role in ("user", "assistant") else "assistant",
                    "text": _compact_injected_context(raw).strip(),
                }
            )
        con.close()
    except Exception:
        pass
    return out


def show_messages(provider: str, sid: str, path: str = "") -> None:
    """Emit one session's ordered [{role, text}] as JSON. `path` (the transcript
    file the caller already knows) skips on-disk resolution; opencode ignores it
    (db-backed). Unknown provider / missing id is a contract error, not an empty
    conversation — exit nonzero so the consumer shows a failure, not "No messages"."""
    if not sid or provider not in ("claude", "codex", "opencode"):
        sys.stderr.write("usage: --show <provider:id> [--path <file>]\n")
        sys.exit(1)
    if provider == "claude":
        path = path or claude_path_for(sid) or ""
        msgs = claude_messages(path) if path else []
    elif provider == "codex":
        path = path or codex_path_for(sid) or ""
        msgs = codex_messages(path) if path else []
    else:  # opencode
        msgs = opencode_messages(sid)
    json.dump(msgs, sys.stdout)


def main() -> None:
    args = sys.argv[1:]
    if "--preview" in args:  # fzf preview pane; skip the full session build
        i = args.index("--preview")
        raw = args[i + 1] if i + 1 < len(args) else "{}"
        try:
            data = json.loads(raw)
        except Exception:
            data = {}
        sys.stdout.write(render_preview(data))
        return
    if "--show" in args:  # one session's full transcript; skip the session build
        i = args.index("--show")
        key = args[i + 1] if i + 1 < len(args) else ""
        provider, _, sid = key.partition(":")
        path = ""
        if "--path" in args:
            j = args.index("--path")
            path = args[j + 1] if j + 1 < len(args) else ""
        show_messages(provider, sid, path)
        return
    sessions = build_sessions()
    if "--search" in args:
        i = args.index("--search")
        query = args[i + 1] if i + 1 < len(args) else ""
        emit_json(sessions, query)
    elif "--json" in args:
        emit_json(sessions)
    else:
        emit_fzf(sessions)


if __name__ == "__main__":
    try:
        main()
        sys.stdout.flush()
    except BrokenPipeError:
        os.dup2(os.open(os.devnull, os.O_WRONLY), sys.stdout.fileno())
        sys.exit(0)
