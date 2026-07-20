#!/usr/bin/env node
// UserPromptSubmit hook — machine-agnostic home-path normalizer.
//
// When a message references a file path under SOME machine's home dir that is
// not this machine's (e.g. /Users/rioedwards/... pasted into a session running
// as /Users/rioredwards, or vice-versa), inject a note giving the equivalent
// path under THIS machine's $HOME. Runs per-machine, so it always resolves to
// wherever the session currently is — not hardcoded to any one host or user.
// Main use: pasting a screenshot path copied on one Mac into a Claude session
// on the other; the file lives at the same $HOME-relative spot on both (iCloud).
//
// Resolution is by EXISTENCE, not by a fixed extension:
//   - filenames may contain spaces (screenshots do),
//   - the pasted path may omit the extension (e.g. CleanShot "...@2x"),
//   - the path may be followed by trailing words ("read <path> and ...").
// So from each /Users|home/<user>/ start we take the rest of the line, then
// find the LONGEST prefix that resolves to a real local file — trying the
// literal path and the path with a known media extension appended. Existence
// gating also means an unrelated /Users/someone-else/... path is left untouched.
//
// UserPromptSubmit hooks CANNOT rewrite the prompt text, only inject context,
// so this is advisory: Claude is TOLD the correct path and opens that instead.
//
// When the path is under a KNOWN machine's home but no local equivalent exists
// (dir not iCloud-synced, e.g. ~/Downloads), stay loud instead of silent:
// inject a note that this is the other Mac's real username — not a typo — with
// ssh/scp hints to check/fetch it there.
// Fail-safe: any error exits 0 with no output; never blocks a prompt.

try {
  const fs = require('fs');
  let raw = '';
  try { raw = fs.readFileSync(0, 'utf8'); } catch { process.exit(0); }

  // Hook stdin is JSON with a `prompt` field; fall back to raw text if not JSON.
  let prompt = '';
  try { prompt = JSON.parse(raw).prompt || ''; } catch { prompt = raw; }
  if (!prompt) process.exit(0);

  const HOME = process.env.HOME || '';
  if (!HOME) process.exit(0);

  // Rio's two machines: home-dir username -> ssh alias (see MACHINE_SETUP.md).
  const MACHINES = { rioredwards: 'mini', rioedwards: 'macbook' };
  const localUser = HOME.split('/').pop();

  // Extensions to probe when the literal path doesn't exist on disk.
  const EXTS = ['', '.png', '.jpg', '.jpeg', '.gif', '.heic', '.heif', '.webp',
                '.tif', '.tiff', '.bmp', '.mov', '.mp4', '.m4a', '.pdf'];
  const exists = p => { try { return fs.statSync(p).isFile(); } catch { return false; } };

  // Each candidate = a home-path start plus everything to end of line / quote.
  const startRe = /\/(?:Users|home)\/[^/\n'"`]+\/[^\n'"`]*/g;
  const prefixRe = /^(\/(?:Users|home)\/[^/]+)(\/.*)$/;

  const seen = new Set();
  const maps = [];
  const misses = [];
  let m;
  while ((m = startRe.exec(prompt)) !== null) {
    const candidate = m[0].replace(/\s+$/, '');   // drop trailing whitespace
    const pm = prefixRe.exec(candidate);
    if (!pm) continue;
    const foreignPrefix = pm[1];                  // e.g. /Users/rioedwards
    const tailFull = pm[2];                       // e.g. /Library/.../CleanShot ... @2x

    // Longest-prefix existence probe: trim trailing space-delimited tokens so a
    // real filename with internal spaces wins over the same path plus stray
    // trailing words. At each length, also try appending a known extension.
    const tokens = tailFull.split(' ');
    let hit = null;
    for (let i = tokens.length; i >= 1 && !hit; i--) {
      const tailCand = tokens.slice(0, i).join(' ');
      const localBase = HOME + tailCand;
      for (const ext of EXTS) {
        if (exists(localBase + ext)) {
          hit = { orig: foreignPrefix + tailCand, target: localBase + ext };
          break;
        }
      }
    }
    if (hit) {
      if (hit.orig === hit.target) continue;       // already this machine's path
      if (seen.has(hit.orig)) continue;
      seen.add(hit.orig);
      maps.push(hit);
      continue;
    }

    // No local equivalent. If the prefix is the OTHER known machine's home,
    // report loudly rather than letting an agent call the username a typo.
    // Path end is approximate (no existence probe possible) — whole tail kept.
    const foreignUser = foreignPrefix.split('/').pop();
    const alias = MACHINES[foreignUser];
    if (!alias || foreignUser === localUser) continue;
    // Heuristic path end: cut after the last token ending in a file extension
    // (drops trailing prose like "... .log plz"); else keep the whole tail.
    let tail = tailFull;
    for (let i = tokens.length; i >= 1; i--) {
      if (/\.[A-Za-z0-9]{1,5}$/.test(tokens[i - 1])) {
        tail = tokens.slice(0, i).join(' ');
        break;
      }
    }
    const orig = foreignPrefix + tail;
    if (seen.has(orig)) continue;
    seen.add(orig);
    misses.push({ orig, local: HOME + tail, alias });
  }

  if (maps.length === 0 && misses.length === 0) process.exit(0);

  const parts = [`Home-path normalization (this machine's $HOME is ${HOME}):`];
  if (maps.length > 0) {
    const lines = maps.map(x => `  ${x.orig}\n    -> ${x.target}`).join('\n');
    parts.push(
      `The message references path(s) under another machine's home dir. Read/use ` +
      `the equivalent path(s) on this machine instead:\n${lines}`);
  }
  for (const x of misses) {
    parts.push(
      `The path ${x.orig} is under the other Mac's home dir (ssh alias: ${x.alias}). ` +
      `That username is REAL, not a typo. No local equivalent exists at ` +
      `${x.local} — the directory may not be cloud-synced (~/Downloads is not). ` +
      `Check the other machine first, then fetch if needed:\n` +
      `  ssh ${x.alias} ls -la '${x.orig}'\n` +
      `  scp '${x.alias}:${x.orig}' '${x.local}'\n` +
      `(Path end is approximate if the message had trailing words after it.)`);
  }
  const context = parts.join('\n\n');

  process.stdout.write(JSON.stringify({
    hookSpecificOutput: {
      hookEventName: 'UserPromptSubmit',
      additionalContext: context,
    },
  }));
  process.exit(0);
} catch {
  process.exit(0);
}
