# SpinCheck: three-day live trial

Skill: none. A narrow, read-only direction check, not a full code review.

The working agent supplies session ID, transcript path, cwd and checkpoint ID.
Independently establish the user's outcome, approvals, redirects and whether the
next work is worth its cost. Do not inherit the parent's diagnosis or manufacture
disagreement. Return findings to the parent, not a new Rio inbox.

## Context, using existing tools

Use the existing gatherer from the repository actually being changed. For a
projectless chat, locate that repository from the current task or tool context;
label omitted repositories when work spans several:

```sh
~/dev/agent-skills/plugins/utils/scripts/gather-context.sh \
  --session <provider:id> --token-budget 8500 --sources sessions,git,gh
```

This command reads actual messages, repository context and saved PM sources,
then bounds the complete rendered text, including source labels and clipping
markers, to 8,500 estimated tokens. Keep these instructions and supplied pointers
within the remaining 1,500 of the 10,000 custom-context allowance. Automatic agent
instructions are outside this allowance. The output names its estimator; this is
not an exact model-token claim.

Current conversation spends its roughly 5,000-token allowance first. For a short
chat, select relevant sessions using `session-handoff search`, then add repeatable
`--related <provider:id>` flags. Actual related messages fill only spare conversation
space. Summaries locate sources; they do not replace user messages. Read
`~/.dotfiles/.codex/skills/sesh/SKILL.md` for discovery commands. Prioritize newer
user corrections and preserve proposal/approval pairs; agent plans are not decisions.

Select useful recent raw tool calls from the supplied transcript and add repeatable
`--tool-call <ID>` flags. The command pairs selected calls and results for Codex and
Claude; unavailable pairs are labeled gaps. Omit waits, skill reads and duplicate
telemetry. No selected tool IDs means an explicit tool-evidence gap, not coverage.

Re-run the same bounded command with selected IDs for the final review context.
Windows and clipped sources are partial reads. If a decisive older turn is missing,
replace lower-value context within the allowance; unresolved decisive evidence
means context-gap. Saved PM sources include dates and need verification against
newer messages or owning sources. No full PM refresh, new collector or cache.

## Judgment and return

Spend roughly three minutes. Check outcome alignment, duplicate/existing work,
proportionate ceremony, progress, weak approaches and scope drift.

Return pass, concrete correction, or context-gap in at most 200 words. Corrections
cite source, user words, observed behavior and smallest useful change. No blocking
on hypothetical risks, taste or pre-launch hardening. No extra tests/implementation.
Parent acts or explains disagreement and records a receipt with reviewer ID.
Receipts are self-reported, not usefulness proof. Full reviews remain in native
history; the hook retains 120 short references and 64 counters.

Trial expires automatically three days after activation. Judge actual corrections,
detours, missed reviews and interruptions. Wiring tests prove delivery, not value.
