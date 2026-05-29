#!/usr/bin/env python3
"""Deterministic Nerd Font icons for repo directories (no AI).

Given a directory name, split it into constituent words (kebab/snake →
camelCase → wordninja), match each word to a Nerd Font glyph, and return up
to two glyphs. Matching priority: a hand-curated dev-term map, then a
whole-word index built from glyphnames.json, then a distinct fallback pool.

Pure function of the name + the set of already-used icons (for dedup), so
results are stable across runs. Glyph data loads lazily on first derive.
"""

from __future__ import annotations

import json
import re
from pathlib import Path

HERE = Path(__file__).resolve().parent
GLYPHS_PATH = HERE / "data" / "glyphnames.json"

# Glyph sets ranked by how good a logo/icon they make. Tech logos first.
_SET_RANK = {
    "dev": 0,   # devicons: react, python, docker, rust...
    "seti": 1,  # file-type / language logos
    "linux": 2,  # distro logos
    "fae": 3,
    "oct": 4,   # octicons
    "md": 5,    # material design: huge noun coverage
    "fa": 6,    # font awesome
    "cod": 7,   # vscode codicons
    "weather": 8,
}

# word -> glyph NAME (resolved to a char at load; dropped if name missing).
# Curated because common words rarely match a glyph's cryptic name 1:1, and
# tech terms deserve their real logo over a generic material icon.
_CURATED = {
    # languages / runtimes
    "js": "dev-javascript", "javascript": "dev-javascript",
    "ts": "seti-typescript", "typescript": "seti-typescript",
    "node": "dev-nodejs_small", "nodejs": "dev-nodejs_small",
    "py": "dev-python", "python": "dev-python",
    "rust": "dev-rust", "go": "seti-go2", "golang": "seti-go2",
    "ruby": "dev-ruby", "java": "dev-java", "php": "dev-php",
    "html": "dev-html5", "css": "dev-css3", "sass": "dev-sass",
    "scss": "dev-sass", "swift": "dev-swift", "kotlin": "seti-kotlin",
    "c": "seti-c", "cpp": "seti-cpp", "lua": "seti-lua",
    "bash": "dev-bash", "shell": "md-console", "zsh": "dev-terminal",
    "sh": "md-console", "json": "seti-json", "markdown": "dev-markdown",
    "md": "dev-markdown",
    # frameworks / libs
    "react": "dev-react", "vue": "md-vuejs", "vuejs": "md-vuejs",
    "angular": "dev-angular", "svelte": "seti-svelte", "next": "md-react",
    "nextjs": "md-react", "express": "dev-nodejs_small",
    "tailwind": "md-tailwind", "vite": "md-flash",
    # platforms / infra
    "docker": "dev-docker", "kubernetes": "md-kubernetes", "k8s": "md-kubernetes",
    "aws": "dev-amazonwebservices", "amazon": "dev-amazonwebservices",
    "gcp": "dev-googlecloud", "google": "fa-google",
    "azure": "md-microsoft_azure", "firebase": "dev-firebase",
    "git": "dev-git", "github": "dev-github_badge", "gitlab": "dev-gitlab",
    "vercel": "dev-vercel", "netlify": "md-web",
    "hubspot": "md-hubspot", "bigquery": "md-google",
    # domains / concepts
    "api": "md-api", "web": "md-web", "site": "md-web", "website": "md-web",
    "app": "md-application", "server": "md-server", "backend": "md-server",
    "frontend": "md-monitor", "client": "md-monitor",
    "db": "md-database", "database": "md-database", "sql": "md-database",
    "registry": "md-database",
    "test": "md-test_tube", "tests": "md-test_tube", "testing": "md-test_tube",
    "prototype": "md-flask", "demo": "md-flask", "playground": "md-toy_brick",
    "sandbox": "md-toy_brick", "example": "md-flask_outline",
    "docs": "md-file_document", "doc": "md-file_document",
    "script": "md-script_text", "scripts": "md-script_text",
    "scroll": "md-script_text", "config": "md-cog", "settings": "md-cog",
    "setup": "md-cog", "wizard": "md-auto_fix", "tool": "md-tools",
    "tools": "md-tools", "workflow": "md-sitemap", "workflows": "md-sitemap",
    "automation": "md-robot_industrial", "automations": "md-robot_industrial",
    "cron": "md-clock_outline", "task": "md-checkbox_marked",
    "tasks": "md-checkbox_marked", "tracker": "md-radar",
    "issue": "md-bug", "bug": "md-bug",
    # ai / data
    "ai": "md-brain", "ml": "md-brain", "agent": "md-robot",
    "agents": "md-robot", "bot": "md-robot_happy", "llm": "md-brain",
    "embedding": "md-vector_polyline", "embeddings": "md-vector_polyline",
    "ocr": "md-text_recognition", "image": "md-image", "img": "md-image",
    "images": "md-image", "photo": "md-camera", "stt": "md-microphone",
    "voice": "md-microphone", "voicemail": "md-voicemail", "audio": "md-music",
    "chat": "md-chat", "overlay": "md-layers", "kaleidoscope": "md-shape",
    # personal / misc
    "portfolio": "md-briefcase", "career": "md-briefcase",
    "resume": "md-file_account", "job": "md-briefcase", "jobs": "md-briefcase",
    "interview": "md-account_tie", "tutoring": "md-school",
    "skill": "md-lightbulb_on", "skills": "md-lightbulb_on",
    "gmail": "md-gmail", "mail": "md-email", "email": "md-email",
    "calendar": "md-calendar", "day": "md-calendar_today",
    "hotkey": "md-keyboard", "key": "md-key", "keychain": "md-key_chain",
    "dotfiles": "md-cog_outline", "home": "md-home", "dev": "md-code_braces",
    "starter": "md-rocket_launch", "template": "md-file_outline",
    "component": "md-puzzle", "components": "md-puzzle",
    "saas": "md-cloud", "cloud": "md-cloud", "fullstack": "md-layers_triple",
    "hours": "md-clock_outline", "hacky": "md-hammer_wrench",
    "ceo": "md-account_tie", "char": "md-account", "character": "md-account",
    "creator": "md-palette", "validator": "md-check_decagram",
    "pi": "md-raspberry_pi", "probe": "md-magnify",
}

# Distinct fallback pool (glyph NAMES) for dirs with no word match. Varied
# objects/animals/symbols; resolved to chars at load.
_POOL_NAMES = [
    "md-cat", "md-dog", "md-owl", "md-penguin", "md-rabbit", "md-panda",
    "md-fish", "md-ladybug", "md-butterfly", "md-bee", "md-snail",
    "md-cactus", "md-flower", "md-tree", "md-pine_tree", "md-mushroom",
    "md-leaf", "md-sprout", "md-clover", "md-cake", "md-coffee",
    "md-pizza", "md-ice_cream", "md-cookie", "md-fruit_cherries",
    "md-guitar_acoustic", "md-piano", "md-trumpet", "md-saxophone",
    "fa-drum", "md-rocket", "md-airplane", "md-sail_boat", "md-bicycle",
    "md-train", "md-balloon", "md-gift", "md-diamond_stone", "md-anchor",
    "md-compass", "md-map", "md-castle", "md-ferris_wheel", "md-umbrella",
    "md-snowflake", "md-fire", "md-water", "md-weather_sunny", "md-star",
    "md-heart", "md-lightning_bolt", "md-puzzle", "md-dice_5",
]

_CAMEL = re.compile(r"(?<=[a-z0-9])(?=[A-Z])|(?<=[A-Z])(?=[A-Z][a-z])")
_HEXISH = re.compile(r"^(?=.*\d)[0-9a-f]{4,}$")  # hashes like 97861e

# Lazily-populated module state.
_INDEX: dict[str, str] = {}  # word -> glyph char (curated + glyphname tokens)
_POOL: list[str] = []
_LOADED = False


def _load() -> None:
    """Build the word→char index + pool from glyphnames.json (once)."""
    global _LOADED
    if _LOADED:
        return
    _LOADED = True
    try:
        glyphs = json.loads(GLYPHS_PATH.read_text())
    except Exception:
        return

    def char_of(name: str) -> str | None:
        ent = glyphs.get(name)
        return ent.get("char") if isinstance(ent, dict) else None

    # Whole-word index from glyph names: token -> char, best set/specificity.
    best: dict[str, tuple[int, int]] = {}  # word -> (rank, ntokens)
    for name, ent in glyphs.items():
        if name == "METADATA" or "-" not in name or not isinstance(ent, dict):
            continue
        prefix, rest = name.split("-", 1)
        rank = _SET_RANK.get(prefix)
        if rank is None:
            continue
        toks = rest.split("_")
        for w in toks:
            if len(w) < 2:
                continue
            score = (rank, len(toks))
            if w not in best or score < best[w]:
                best[w] = score
                _INDEX[w] = ent["char"]

    # Curated overrides win over the generic index.
    for w, gname in _CURATED.items():
        c = char_of(gname)
        if c:
            _INDEX[w] = c

    for gname in _POOL_NAMES:
        c = char_of(gname)
        if c:
            _POOL.append(c)


def split_words(name: str) -> list[str]:
    """dir name → lowercase constituent words (kebab/snake + camelCase)."""
    words: list[str] = []
    for part in re.split(r"[-_\s.]+", name):
        if not part:
            continue
        for w in _CAMEL.split(part):
            w = w.lower()
            if w and not w.isdigit() and not _HEXISH.match(w):
                words.append(w)
    return words


def _lookup(w: str) -> str | None:
    """Glyph char for a word, trying the plural→singular form too."""
    if w in _INDEX:
        return _INDEX[w]
    if w.endswith("s") and w[:-1] in _INDEX:
        return _INDEX[w[:-1]]
    return None


def _match_chars(words: list[str], limit: int = 2) -> list[str]:
    chars: list[str] = []
    for w in words:
        c = _lookup(w)
        if c and c not in chars:
            chars.append(c)
            if len(chars) >= limit:
                break
    return chars


def derive(name: str, used: set[str], limit: int = 2) -> str | None:
    """Return an icon string (1-2 glyphs) for `name`, unique vs `used`."""
    _load()
    if not _INDEX:  # glyph data missing
        return None

    words = split_words(name)
    chars = _match_chars(words, limit)

    # No direct hit: try splitting glued single-word names (e.g. "agentskills").
    if not chars:
        try:
            import wordninja

            split = []
            for w in words:
                if len(w) >= 6 and w.isalpha():
                    split += wordninja.split(w)
                else:
                    split.append(w)
            chars = _match_chars(split, limit)
        except Exception:
            pass

    # Pick the first variant whose rendered string is unused.
    candidates = []
    if chars:
        candidates.append("".join(chars[:limit]))  # full multi-glyph
        candidates.append(chars[0])  # single best, if the pair collides
    for c in _POOL:  # distinct fallbacks guarantee uniqueness
        candidates.append(c)

    for cand in candidates:
        if cand and cand not in used:
            return cand
    return chars[0] if chars else (_POOL[0] if _POOL else None)
