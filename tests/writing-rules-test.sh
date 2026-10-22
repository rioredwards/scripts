#!/bin/sh
# Check the live writing-rule consumers, including podcast prompt assembly.
set -eu
python3 - <<'PY'
from pathlib import Path
import subprocess

home = Path.home()
career = home / 'Career'
shared = home / 'dev/agent-skills/plugins/writing/skills/writing-rules/ref/rules.md'
retired = ('writing-rules-base', 'writing-rules-career')
for name in retired:
    path = career / '.agents/skills' / name
    assert not (path.exists() or path.is_symlink()), f'Competing writing-rule source: {path}'

for path in (career / '.agents').rglob('*.md'):
    text = path.read_text()
    assert not any(name in text for name in retired), f'Retired writing-rule caller: {path}'

prompt = subprocess.run(
    [str(home / 'dev/ai-text-transform/aitt'), 'podcast', '--dry-run',
     'Explain a concrete engineering tradeoff.'],
    input='', text=True, capture_output=True, check=True,
).stdout
assert shared.read_text().strip() in prompt, 'Podcast does not embed the current shared rules'
assert '{{file:' not in prompt, 'Unexpanded podcast reference'
assert not any(name in prompt for name in retired), 'Podcast uses retired writing rules'
for phrase in ('exactly the kind of', 'and honestly', 'Ordinary factual corrections are fine', 'Vary sentence lengths and subjects'):
    assert phrase in prompt, f'Lost approved writing rule: {phrase}'
assert "# Career" not in prompt, 'Career structure leaked into the podcast'
print('PASS: one writing-rule authority; podcast embeds its current rules')
PY
