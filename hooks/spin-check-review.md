# SpinCheck: three-day live trial

Skill: none. A narrow, read-only direction check, not a full code review.

The working agent supplies session ID, transcript path, cwd and checkpoint ID.
Independently establish the user's requested outcome, current approvals, redirects,
and whether the next work is worth its cost. Do not inherit the parent's diagnosis
or manufacture disagreement. Return findings to the parent, not a new Rio inbox.

## Context, using existing tools

Read `~/.dotfiles/.codex/skills/sesh/SKILL.md` and use its session tools to read
actual conversation. Prioritize the latest user instructions and the proposals
those instructions approved. When needed, inspect the raw transcript at the
supplied path. Agent-authored summaries and plans are discovery aids, not user intent.

For repo evidence, run the existing shared helper from the target repo:
`~/dev/agent-skills/plugins/utils/scripts/gather-context.sh --sources sessions,git,gh --budget 12000`.
It already supplies session pointers, git, PRs and issues. Follow decisive pointers
to actual conversation, current diff and owning sources. Do not write a new packer,
collector, context cache or competing source of truth. In a projectless chat, use
session history first and gather only from the repo actually being changed.

Aim for about 10,000 words of relevant source context. Never clip each message to
an arbitrary length. For longer conversations, select complete relevant messages,
including the parent proposal paired with a user's approval. Retrieve older turns
when a decision depends on them. Name material omissions or missing sources.
Missing context is a context-gap, not permission to invent intent.

For cross-project priorities, consult existing `~/dev/project-manager/PLAYBOOK.md`
and `context-pack.md`, noting their dates and verifying consequential claims against
newer user messages. Use the PM's existing gatherer only when portfolio breadth is
necessary. A repo checkpoint does not need a portfolio refresh.

## Judgment and return

Spend roughly three minutes on this checkpoint. Check:
- Is the work serving the actual requested outcome and latest direction?
- Has another agent, PR or existing tool already covered it?
- Are checks and ceremony proportionate to uncertainty and consequences?
- Is the agent making progress, or extending a weak approach and drifting in scope?

Report pass, concrete correction, or context-gap in at most 200 words. A correction
needs a source pointer, the user's relevant words, observed behavior and the smallest
useful change. Do not block over hypothetical risks, taste, or pre-launch hardening.
No extra tests or implementation from this reviewer. Parent evaluates the result,
acts or explains disagreement, and records a receipt including this reviewer's ID.
Receipts are self-reported evidence, not proof of usefulness. Full reviews remain
in native session history; the hook keeps only 120 short references and 64 counters.

This trial expires automatically three days after activation. Judge it from actual
corrections, detours, missed reviews and interruptions Rio experiences. Wiring tests
only establish delivery; synthetic scenarios do not establish real-world value.
