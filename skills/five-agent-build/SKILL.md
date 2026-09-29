---
name: five-agent-build
description: Explicitly requested five-agent workflow for investigation, implementation, adversarial review, and integration.
---

# Five-agent build

Run only when explicitly requested, for the current task. CHIEF is the main conversation;
SCOUT, BUILDER, VERIFIER, and OPERATOR are its four named specialists. Use real named
subagents and keep their identifiers. CHIEF coordinates; specialists do not spawn more
agents. Use the host's available subagent tools and report actual results.

Read [critique-protocol.md](references/critique-protocol.md) when routing reviews and
[workflow.md](references/workflow.md) for handoffs and concurrency. Honor review-only
and plan-only requests, and use proportionate checks for small changes.

## Phase 1: Investigation
Invoke SCOUT to trace existing behavior, reuse opportunities, dependencies, and
architectural constraints. Capture applicable project instructions and Git state.

## Phase 2: Draft plan
CHIEF defines the objective, current and intended behavior, affected components,
invariants, implementation scope, acceptance criteria, and validation strategy.

## Phase 3: Plan critique
BUILDER critiques feasibility; VERIFIER critiques correctness and testability.
Run independently in parallel where safe; ask SCOUT about architecture as needed.

## Phase 4: Plan adjudication
CHIEF records ACCEPTED, PARTIALLY ACCEPTED, or REJECTED for meaningful objections,
with evidence and justification. Revise the plan before implementation.

## Phase 5: Implementation
BUILDER implements the bounded plan, adds appropriate tests, runs focused checks,
and reports actual changes and results. It is the sole feature-code writer.

## Phase 6: Independent implementation review
Pause feature writes. SCOUT reviews architectural fit; VERIFIER independently tries
to falsify correctness using the actual diff, surrounding code, and acceptance criteria.

## Phase 7: Builder response
Route every finding by stable ID to BUILDER. Require acceptance or rebuttal with
rationale, evidence, and action. Fix accepted issues.

## Phase 8: Critic reconsideration
Send disputed findings and Builder's rebuttal back to the original critic, who must
WITHDRAW, DOWNGRADE, or MAINTAIN the finding with reasons.

## Phase 9: Chief adjudication
CHIEF resolves remaining disputes using evidence, never majority vote. Record the
decision and required action; unsupported speculation is not a veto.

## Phase 10: Re-verification
VERIFIER rechecks behavior-changing fixes and regressions; SCOUT rechecks architecture
when affected. Resolve blocking findings before final integration.

## Phase 11: Operator integration
OPERATOR validates the reviewed result with repository-level checks and reports Git
state, actual commands/results, and any remaining blockers.

## Phase 12: Repair loop
Integration blockers go through CHIEF to BUILDER, then VERIFIER when behavior changes,
then OPERATOR to rerun affected checks. Report unresolved work clearly.

## Phase 13: Final result
CHIEF reports changes, architectural decisions, important disagreements and resolutions,
checks performed, remaining issues, repository state, and which real agents ran.
