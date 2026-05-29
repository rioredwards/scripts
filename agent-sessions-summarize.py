#!/usr/bin/env python3
"""Generate concise titles for Claude/Codex sessions via local Ollama.

Writes id -> {"summary", "msg_count", "model"} into
~/.cache/agent-sessions/summaries.json. The picker (agent-sessions.py) prefers
these over noisy first-message titles. OpenCode is skipped (it has db titles).

Design: feed only the user's turns (first 6 + last 2, truncated) to a local
model. User messages carry the intent; tool dumps are noise. Local = free,
private, offline. Run lazily in the background from the picker, or standalone:

    agent-sessions-summarize.py            # newest 40 missing
    agent-sessions-summarize.py --all      # backfill everything
    agent-sessions-summarize.py --limit 100
    agent-sessions-summarize.py --refresh  # re-summarize grown sessions too
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
MODEL = os.environ.get("AGENT_SESSIONS_MODEL", "qwen2.5-coder:7b")

# Reuse the picker's collectors/cleaner (dashed filename -> import via spec).
_spec = importlib.util.spec_from_file_location("agg", HERE / "agent-sessions.py")
agg = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(agg)

SUMMARY_PATH = agg.SUMMARY_PATH
REPO_EMOJI_PATH = agg.CACHE_DIR / "repo-emojis.json"  # full dir path -> emoji
LOCK_PATH = agg.CACHE_DIR / "summarize.lock"

FIRST_N, LAST_N, MSG_CHARS, TOTAL_CHARS = 6, 2, 300, 2000

PROMPT = (
    "You write terse titles for coding-assistant sessions. "
    "Given the user's messages below, reply with ONLY a title of at most 6 "
    "words. No quotes, no trailing punctuation, no preamble.\n\n"
    "MESSAGES:\n{body}\n\nTITLE:"
)

EMOJI_PROMPT = (
    "Suggest 5 DISTINCT emojis that could represent this coding project, "
    "ranked best first. Be specific to the project, avoid generic 🤖/💻. "
    "Do not use any of these already-taken emojis: {used}. "
    "Reply with ONLY the 5 emojis separated by spaces, nothing else.\n\n"
    "Project folder: {name}\nRecent task titles:\n{titles}\n\nEMOJIS:"
)

# Match a single emoji from noisy model output (symbol/pictograph ranges).
# Excludes variation selectors (️ etc.) so they never match standalone.
EMOJI_RE = re.compile(
    "[\U0001f300-\U0001faff\U00002600-\U000027bf"
    "\U0001f000-\U0001f0ff\U00002b00-\U00002bff]"
)

# Distinct fallback pool: when the model's candidates all collide with
# already-used emojis, draw the first unused one from here so every repo
# stays unique. Ordered varied; generic 🤖/💻 deliberately omitted.
EMOJI_POOL = list(
    "🐶🐱🦊🐻🐼🐨🦁🐯🦄🐙🦋🐝🐞🦀🐢🐧🦉🦜🐳🐝"
    "🍎🍊🍋🍉🍇🍓🍒🥝🥑🍅🌽🥕🍄🌶🧄🍞🧀🍕🌮🍣"
    "⚽🏀🏈🎾🎱🎳🎯🎲🎸🎺🎻🥁🎹🎨🎬🎤🎧📷📹🔭"
    "🌵🌲🌳🌴🌷🌻🌼🌺🍁🍀⭐🌙☀🔥💧🌈⚡❄🌊🪐"
    "🚗🚲🛴✈🚀🛸⛵🚁🏰🗼⛩🎡🎢🎠🧭🗺🧩🎁🎈🪄"
)


# --------------------------------------------------------------------------- #
# Per-provider user-message extraction (intent only; skip tool noise)
# --------------------------------------------------------------------------- #
def claude_user_msgs(path: str) -> list[str]:
    out = []
    try:
        with open(path, "r", errors="ignore") as fh:
            for line in fh:
                try:
                    o = json.loads(line)
                except Exception:
                    continue
                if o.get("type") != "user":
                    continue
                c = o.get("message", {}).get("content")
                raw = ""
                if isinstance(c, str):
                    raw = c
                elif isinstance(c, list):
                    # text parts only; skip tool_result dicts
                    raw = " ".join(
                        p.get("text", "")
                        for p in c
                        if isinstance(p, dict) and p.get("type") == "text"
                    )
                t = agg.clean_title(raw, n=MSG_CHARS)
                if t and t != "(no preview)":
                    out.append(t)
    except Exception:
        pass
    return out


def codex_user_msgs(path: str) -> list[str]:
    out = []
    try:
        with open(path, "r", errors="ignore") as fh:
            for line in fh:
                try:
                    o = json.loads(line)
                except Exception:
                    continue
                pl = o.get("payload", {})
                raw = ""
                if o.get("type") == "event_msg" and pl.get("type") == "user_message":
                    raw = pl.get("message", "")
                elif pl.get("role") == "user":
                    c = pl.get("content")
                    if isinstance(c, list):
                        raw = " ".join(
                            p.get("text", "") for p in c if isinstance(p, dict) and p.get("text")
                        )
                if not raw:
                    continue
                t = agg.clean_title(raw, n=MSG_CHARS)
                if t and t != "(no preview)":
                    out.append(t)
    except Exception:
        pass
    return out


def sample(msgs: list[str]) -> str:
    """First FIRST_N + last LAST_N user messages, total-capped."""
    if not msgs:
        return ""
    if len(msgs) <= FIRST_N + LAST_N:
        picked = msgs
    else:
        picked = msgs[:FIRST_N] + msgs[-LAST_N:]
    body = "\n".join(f"- {m}" for m in picked)
    return body[:TOTAL_CHARS]


def run_model(prompt: str) -> str | None:
    """Raw model call; returns stripped stdout or None."""
    try:
        r = subprocess.run(
            ["ollama", "run", MODEL, prompt],
            capture_output=True,
            text=True,
            timeout=90,
        )
    except Exception:
        return None
    if r.returncode != 0:
        return None
    return (r.stdout or "").strip() or None


def make_title(body: str) -> str | None:
    out = run_model(PROMPT.format(body=body))
    if not out:
        return None
    title = out.splitlines()[0].strip().strip('"').strip().rstrip(".")
    return title[:70] or None


def make_emoji(name: str, titles: list[str], used: set[str]) -> list[str]:
    """Return ranked, de-duplicated emoji candidates (best first)."""
    ctx = "\n".join(f"- {t}" for t in titles[:4])
    out = run_model(
        EMOJI_PROMPT.format(
            name=name, titles=ctx or "(none)", used=" ".join(used) or "(none)"
        )
    )
    if not out:
        return []
    seen, cands = set(), []
    for g in EMOJI_RE.findall(out):  # preserve model's ranking order
        if g not in seen:
            seen.add(g)
            cands.append(g)
    return cands


# --------------------------------------------------------------------------- #
def fill_repo_emojis(sessions: list, sums: dict, refresh: bool) -> None:
    """Assign one emoji per unique repo dir, cached in REPO_EMOJI_PATH."""
    try:
        emap = json.loads(REPO_EMOJI_PATH.read_text())
    except Exception:
        emap = {}

    # Gather a few task titles per dir for context (prefer generated summaries).
    titles_by_dir: dict[str, list[str]] = {}
    for s in sessions:
        repo = s.get("repo")
        if not repo:
            continue
        ent = sums.get(s.get("id"))
        title = (ent and ent.get("summary")) or s.get("title") or ""
        if title and title != "(no preview)":
            titles_by_dir.setdefault(repo, []).append(title)

    # On refresh, reassign everything from scratch so dedupe is global;
    # otherwise keep existing and just avoid their emojis for new dirs.
    if refresh:
        emap = {}
    used = set(emap.values())

    for repo in titles_by_dir:
        if repo in emap:
            continue
        cands = make_emoji(Path(repo).name or repo, titles_by_dir[repo], used)
        # Prefer the model's fit; fall back to the pool to guarantee uniqueness.
        pick = next((c for c in cands + EMOJI_POOL if c not in used), None)
        if not pick:
            continue
        emap[repo] = pick
        used.add(pick)
        REPO_EMOJI_PATH.write_text(json.dumps(emap))  # persist incrementally
        print(f"[emoji] {pick} {Path(repo).name}", file=sys.stderr)


def acquire_lock() -> bool:
    """Single-flight: skip if a fresh lock (<10 min) exists."""
    try:
        LOCK_PATH.parent.mkdir(parents=True, exist_ok=True)
        if LOCK_PATH.exists() and time.time() - LOCK_PATH.stat().st_mtime < 600:
            return False
        LOCK_PATH.write_text(str(os.getpid()))
        return True
    except Exception:
        return True


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--all", action="store_true", help="no limit (backfill)")
    ap.add_argument("--limit", type=int, default=40)
    ap.add_argument("--refresh", action="store_true", help="redo if grown 2x")
    args = ap.parse_args()

    if subprocess.run(["which", "ollama"], capture_output=True).returncode != 0:
        return 0  # no local model; picker falls back to first-message titles
    if not acquire_lock():
        return 0

    try:
        # Collect claude/codex sessions (records carry path + id + count cache).
        agg.load_cache()
        sessions = []
        for fn in (agg.collect_claude, agg.collect_codex):
            try:
                sessions += fn()
            except Exception:
                pass
        agg.save_cache()
        sessions.sort(key=lambda s: s["time"], reverse=True)

        try:
            sums = json.loads(SUMMARY_PATH.read_text())
        except Exception:
            sums = {}

        extract = {"claude": claude_user_msgs, "codex": codex_user_msgs}
        done = 0
        for s in sessions:
            if not args.all and done >= args.limit:
                break
            sid = s["id"]
            ent = sums.get(sid)
            msgs = extract[s["provider"]](s["path"])
            n = len(msgs)
            if ent and not args.refresh:
                continue
            if ent and args.refresh and n < ent.get("msg_count", 0) * 2:
                continue
            body = sample(msgs)
            if not body:
                continue
            title = make_title(body)
            if not title:
                continue
            sums[sid] = {"summary": title, "msg_count": n, "model": MODEL}
            SUMMARY_PATH.write_text(json.dumps(sums))  # persist incrementally
            done += 1
            print(f"[{s['provider']}] {title}", file=sys.stderr)

        # One emoji per unique repo (cached; computed once per new dir).
        # Include opencode dirs too so every row can show an icon.
        try:
            oc = agg.collect_opencode()
        except Exception:
            oc = []
        fill_repo_emojis(sessions + oc, sums, args.refresh)
        return 0
    finally:
        try:
            LOCK_PATH.unlink()
        except Exception:
            pass


if __name__ == "__main__":
    sys.exit(main())
