# SpinCheck: three-day live trial

Skill: none. A narrow, read-only direction check, not a full code review.

The working agent supplies session ID, transcript path, cwd and checkpoint ID.
Independently establish the user's outcome, approvals, redirects and whether the
next work is worth its cost. Do not inherit the parent's diagnosis or manufacture
disagreement. Return findings to the parent, not a new Rio inbox.

## Context, using existing tools

Gather on demand: model-mediated selection, not a prebuilt packet or enforced cap.
Use Explore's quick source guidance at
`~/.dotfiles/.codex/skills/explore/ref/explore-core.md`: conversation establishes
intent; code, diff and output establish behavior; saved notes may be stale.

Keep custom context within 10,000 estimated tokens, including these instructions
and source labels; automatic agent instructions are outside. Use session-handoff's
existing estimator/optional tokenizer. Adjustable starting weights: conversation
5,000; cached summaries 600; git/GitHub 1,500; useful tool activity 900; saved PM
context 600; remaining 1,400 for instructions, labels and gaps. Reallocate unused
space; no filler. If assembling a packet, count its final text including labels.

Read `~/.dotfiles/.codex/skills/sesh/SKILL.md`. Current conversation comes first:
use `session-handoff peek <provider:id> --tokens N` or the shared API's 3:2:5
beginning/middle/end window. Within-message token slicing is allowed; retain
clipping/omission markers. Windows are partial reads. No arbitrary per-message caps.

If current chat is short, backfill its conversation allowance with actual messages
from relevant sessions. Model relevance selects them; cached summaries/search only
locate sources. Label session IDs/dates, prioritize newer user corrections, and
preserve proposal/approval pairs. Agent plans are not user decisions. Retrieve
decisive older turns by replacing lower-value context within budget. Missing
decisive evidence means context-gap, never invented intent or a pass.

From the repo being changed, reuse:
`~/dev/agent-skills/plugins/utils/scripts/gather-context.sh --sources sessions,git,gh --budget 12000`.
Its budget is CHARACTERS, not tokens or the review cap. Adjust that allowance when
useful; select within the total token budget. Follow pointers to original messages,
current diff and owning sources. Projectless chats start with session history.
Do not add a packer, collector, cache or dependency.

Inspect the supplied raw transcript for useful recent calls paired with results,
including relevant errors. Skip waits, skill-read noise and duplicate telemetry.
Mark clipped payloads, omissions and unavailable sources.

Use relevant saved `~/dev/project-manager/PLAYBOOK.md` and `context-pack.md`;
label dates and verify consequential claims against newer messages/owning sources.
No portfolio refresh by default; use the existing PM gatherer only if necessary.

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
