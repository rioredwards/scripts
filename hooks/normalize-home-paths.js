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
// Generic + safe: matches any /Users/<user>/ or /home/<user>/ prefix, and only
// remaps when the rewritten path actually EXISTS on this machine (so an
// unrelated /Users/someone-else/... path is left untouched).
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

  // Match absolute paths under any user's home: /Users/<user>/... (macOS) or
  // /home/<user>/... (linux). Username is one non-slash segment. Allow spaces in
  // the filename (screenshots have them) by anchoring on a file extension rather
  // than terminating at whitespace. Non-greedy to the first extension.
  const re = /\/(?:Users|home)\/[^/\n'"`]+\/[^\n'"`]*?\.(?:png|jpe?g|gif|heic|heif|webp|tiff?|bmp|mov|mp4|m4a|pdf)/gi;
  const homePrefixRe = /^\/(?:Users|home)\/[^/]+/;

  const seen = new Set();
  const maps = [];
  let m;
  while ((m = re.exec(prompt)) !== null) {
    const orig = m[0];
    const target = HOME + orig.replace(homePrefixRe, '');
    if (orig === target) continue;        // already this machine's path
    if (seen.has(orig)) continue;
    seen.add(orig);
    // Only remap when the file really exists here — avoids rewriting an
    // unrelated home path that happens to match the shape.
    let exists = false;
    try { exists = fs.existsSync(target); } catch {}
    if (!exists) continue;
    maps.push({ orig, target });
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
