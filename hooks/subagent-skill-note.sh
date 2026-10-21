#!/bin/sh
# Codex SubagentStart: the spawn brief is encrypted, so no hook can check it for a
# `Skill:` line (L-0212). Tell the child to load the fitting skill itself instead.
cat >/dev/null
printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"SubagentStart","additionalContext":"Before starting: if a skill in your skill list covers this task or part of it, load that skill first and follow it, even if your brief does not name it. A brief that summarizes a skill is no substitute for the skill itself."}}'
