---
name: five-agent-engineering
description: Use for substantial software engineering requiring investigation, implementation, adversarial review, and integration validation. Skip the full workflow for trivial mechanical edits.
---

# Five-agent engineering

CHIEF is you, the primary Codex thread interacting with the user. There are exactly
five logical roles: CHIEF, SCOUT, BUILDER, VERIFIER, OPERATOR. Only the latter four
are custom subagents (`scout`, `builder`, `verifier`, `operator`). Never spawn CHIEF
or introduce another coordinator, reviewer, or specialist role.

For substantial work, invoke actual named subagents using the host's available
subagent tools. Confirm each requested custom role is available; a task label alone
does not prove that a custom agent definition loaded. If the tool cannot select or
load a required role, report that limitation and stop the dependent workflow. Never
simulate a specialist's response or silently substitute another role. Record role,
actual agent/session identifier, assigned scope, and returned result. Reuse agents
for follow-ups where supported. Specialists must not delegate further.

User instructions and authorization determine scope. Trivial typo, comment, one-line
configuration, or small mechanical edits can be handled directly with proportionate
checks. For explicitly review-only or plan-only requests, use only the relevant
read-only phases and stop at the requested boundary; do not implement or integrate.

Read [critique-protocol.md](references/critique-protocol.md) before routing critiques.
Include that protocol (or its exact relevant fields) in specialist handoffs rather
than assuming children inherit the Skill. See [workflow.md](references/workflow.md)
for handoff details, concurrency, and recovery.

## Phase 1: Investigation

Invoke SCOUT to inspect the existing implementation, trace execution, identify reuse
and architectural constraints, and return concrete evidence. Capture baseline Git
state and applicable project instructions. Do not make implementation assumptions.

## Phase 2: Draft plan

CHIEF drafts objective, current behavior, intended behavior, affected components,
invariants, implementation surface, acceptance criteria, and validation strategy.
No implementation yet. Define write ownership and what is outside scope.

## Phase 3: Plan critique

Send the same plan and evidence to BUILDER for feasibility/complexity critique and
VERIFIER for correctness, edge cases, assumptions, and testability. Run these
independently in parallel where safe. Optionally ask SCOUT about architectural fit.
Explicitly prohibit implementation during this phase.

## Phase 4: Plan adjudication

Classify each meaningful objection as ACCEPTED, PARTIALLY ACCEPTED, or REJECTED.
Record evidence and rationale, including justification for rejected critiques.
Resolve material uncertainty through bounded investigation or reproduction and revise
the plan. Evidence determines decisions; do not use a majority vote. A technically
incorrect plan must change. CHIEF can authorize implementation within existing user
scope without requesting redundant permission.

## Phase 5: Implementation

Assign the revised bounded plan to BUILDER as the sole feature-code writer.
BUILDER implements, adds appropriate tests, runs focused checks, and reports changes,
commands/results, and known risks. BUILDER cannot approve its own work or completion.

## Phase 6: Independent implementation review

Pause feature writes. Send the actual diff, surrounding-code scope, acceptance
criteria, and tests to SCOUT and VERIFIER. Prefer parallel independent reviews:
SCOUT checks architecture; VERIFIER tries to falsify correctness. Collect both results
before synthesizing them. A clean review is valid after real investigation.

## Phase 7: Builder response

Route every concrete finding with its stable ID to BUILDER. Require ACCEPT,
PARTIALLY ACCEPT, or REJECT with rationale, evidence, and action for each. BUILDER
fixes accepted issues and supports disagreements with technical evidence.

## Phase 8: Critic reconsideration

Send rejected or partially rejected findings and the complete rebuttal back to the
original critic. Require WITHDRAW, DOWNGRADE, or MAINTAIN with reasons and updated
evidence. Do not replace the original critic's reconsideration with CHIEF's opinion.

## Phase 9: Chief adjudication

Adjudicate remaining disputes as ACCEPTED, PARTIALLY ACCEPTED, or REJECTED using
repository evidence and reproducible behavior. Track original severity, current
status, rationale, and required action. Unsupported disagreement cannot block work.
High-confidence reproducible evidence outweighs unsupported speculation.

## Phase 10: Re-verification

Have VERIFIER re-check behavior-changing fixes and relevant regressions; return
architectural fixes to SCOUT when needed. No unresolved BLOCKING finding may pass
the integration gate. If a blocker cannot be resolved, stop progression and report
it explicitly to the user; do not relabel the work complete or pass it to OPERATOR
as ready. Report remaining non-blocking findings and accepted limitations.

## Phase 11: Operator integration

Only after the review gate passes, invoke OPERATOR for repository-wide validation.
Provide the accepted plan, check commands, reviewed changes, baseline state, and
known limitations. Require actual command results and final repository state.

## Phase 12: Repair loop

For integration blockers: OPERATOR → CHIEF → BUILDER repair → VERIFIER re-check
when correctness changes → OPERATOR reruns failed and affected checks. Route any
new architectural dispute through SCOUT. Do not let OPERATOR silently redesign or
fix feature code. If progress requires unavailable access or a user decision,
report the precise blocker instead of looping without new evidence.

## Phase 13: Final result

CHIEF reports what changed, architecture decisions, important disagreements and
resolutions, tests/checks actually performed, skipped checks and limitations,
unresolved findings, and Git/repository state. Identify which real agents ran.
Only CHIEF communicates overall completion, supported by review and integration
results. Never imply a command, test, or delegation happened when it did not.
