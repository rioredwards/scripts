#!/usr/bin/env node
// UserPromptSubmit hook — machine-portable home-path normalizer.
//
// When a message references a file path under Rio's home dir on the OTHER Mac
// (/Users/rioedwards on the MacBook, /Users/rioredwards on the Mini), inject a
// note giving the equivalent path on THIS machine ($HOME). Main use: pasting a
// screenshot path copied on the MacBook into a Claude session on the Mini.
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

  // Match absolute paths under either Mac's home for user rio(r)edwards. Allow
  // spaces in the filename (screenshots have them) by anchoring on a file
  // extension rather than terminating at whitespace. Non-greedy to the first ext.
  const re = /\/Users\/rior?edwards\/[^\n'"`]*?\.(?:png|jpe?g|gif|heic|heif|webp|tiff?|bmp|mov|mp4|m4a|pdf)/gi;

  const seen = new Set();
  const maps = [];
  let m;
  while ((m = re.exec(prompt)) !== null) {
    const orig = m[0];
    const target = HOME + orig.replace(/^\/Users\/rior?edwards/, '');
    if (orig === target) continue;   // already this machine's path
    if (seen.has(orig)) continue;
    seen.add(orig);
    maps.push({ orig, target });
  }

  if (maps.length === 0) process.exit(0);

  const lines = maps.map(x => `  ${x.orig}\n    -> ${x.target}`).join('\n');
  const context =
    `Home-path normalization (this machine's $HOME is ${HOME}):\n` +
    `The message references path(s) under the OTHER Mac's home dir. Read/use ` +
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
