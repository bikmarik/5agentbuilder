# Handoffs, concurrency, and recovery

## Handoff packet

CHIEF gives each specialist the objective, phase, applicable project instructions,
relevant files/paths, evidence, acceptance criteria, allowed actions, explicit write
boundary, and expected output. Provide the critique protocol for review/rebuttal work.
After implementation include the actual diff or instructions to inspect it, baseline
Git state, and command results. Summaries do not replace access to surrounding code.
Give independent reviewers identical facts before sharing each other's conclusions.

Keep task state in CHIEF: plan version, agent IDs, write owner, finding ledger,
review gate, integration status, and next action. A paused/resumed session should
recheck Git state before continuing; stale reviews do not certify a changed diff.

## Concurrency

- SCOUT: read-only investigation and architectural review.
- VERIFIER: read-only correctness review; write-requiring tests may need an isolated
  environment or an authorized run routed through CHIEF.
- BUILDER: only feature-code writer; plan critique is read-only.
- OPERATOR: integration checks after review; local generated outputs may be written.

Parallelize Builder feasibility and Verifier plan critique, Scout and Verifier
implementation review, and independent read-only investigations within these roles.
Never overlap feature writes with review of an unstable diff. Do not overlap checks
that mutate shared caches, fixtures, databases, or generated files. Pause Builder
while Operator validates. Inspect tool-generated tracked-file changes explicitly.

Exactly one logical Builder exists. If a future separate workflow uses multiple
writers, it needs isolated Git worktrees; this workflow does not add Builder-2.
Use at most one active instance per specialist role. Reuse/resume an existing agent
where possible. When concurrency slots are scarce, serialize independent critiques;
close inactive sessions if the host supports it and preserve their evidence. Do not
invent a sixth role to work around limits. If the original critic cannot be resumed
or re-invoked with its evidence, report that reconsideration is incomplete.

## Routing and permissions

All critiques and rebuttals go through CHIEF:

```text
Scout → Chief → Builder
Builder → Chief → Verifier
Verifier → Chief → Builder
```

Direct free-form subagent communication is host-dependent and unnecessary here.
Use the actual tools exposed by the host, not imagined tool names or fake transcripts.
A role label on a generic agent does not establish custom-agent configuration loading.
If named role selection is unavailable, explain the limitation before dependent work.

Read-only sandbox defaults are defense in depth. Parent runtime permissions may
override defaults, and connector permissions are separate. Read-only roles still
must not modify project files or invoke external write actions. Never bypass a
restriction merely to obtain a passing check. Follow the user's existing authorization;
this workflow grants no authority to deploy, publish, commit, delete user work, or
apply production migrations. Report unavailable tools or checks accurately.

## Exit conditions

For a review-only task stop after independent reviews and CHIEF reconciliation.
For a plan-only smoke test stop after plan adjudication. For implementation, require
resolved blocking findings and passing required integration checks. If new evidence
cannot advance a repair/rebuttal loop, state the missing access, evidence, or decision
and report incomplete work. Never manufacture agreement or repeat the same arguments
until a reviewer gives in.

## Claude Code adaptation

Claude Code reads the four Markdown definitions and runs the same phases through
its named Agent tool. Its Scout and Verifier allow only Read, Grep, and Glob; they
must route shell-based reproductions through CHIEF rather than claiming execution.
Builder has shell and file-edit tools. Operator has shell for integration checks;
that tool can write, so its no-feature-edit rule remains a behavioral restriction.
Both clients require explicit user invocation of the Skill. Neither entrypoint
creates another CHIEF agent or enables nested delegation.
