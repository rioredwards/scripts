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

  // Extensions to probe when the literal path doesn't exist on disk.
  const EXTS = ['', '.png', '.jpg', '.jpeg', '.gif', '.heic', '.heif', '.webp',
                '.tif', '.tiff', '.bmp', '.mov', '.mp4', '.m4a', '.pdf'];
  const exists = p => { try { return fs.statSync(p).isFile(); } catch { return false; } };

  // Each candidate = a home-path start plus everything to end of line / quote.
  const startRe = /\/(?:Users|home)\/[^/\n'"`]+\/[^\n'"`]*/g;
  const prefixRe = /^(\/(?:Users|home)\/[^/]+)(\/.*)$/;

  const seen = new Set();
  const maps = [];
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
    if (!hit) continue;
    if (hit.orig === hit.target) continue;         // already this machine's path
    if (seen.has(hit.orig)) continue;
    seen.add(hit.orig);
    maps.push(hit);
  }

  if (maps.length === 0) process.exit(0);

  const lines = maps.map(x => `  ${x.orig}\n    -> ${x.target}`).join('\n');
  const context =
    `Home-path normalization (this machine's $HOME is ${HOME}):\n` +
    `The message references path(s) under another machine's home dir. Read/use ` +
    `the equivalent path(s) on this machine instead:\n${lines}`;

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
