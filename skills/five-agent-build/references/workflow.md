# Handoffs and concurrency

CHIEF supplies the objective, phase, project instructions, relevant paths, evidence,
acceptance criteria, allowed write scope, and expected output. Include the critique
protocol for reviews; children may not inherit the Skill. Reviewers inspect actual
code and receive the same evidence before seeing each other's conclusions.

Track the plan version, agent IDs, write owner, findings, and review/integration status
in the conversation. Recheck Git state after a pause; reviews apply to the inspected diff.

Parallelize independent plan critiques and Scout/Verifier reviews. Keep one feature-code
writer: Builder. Pause writes during review and Operator validation. Serialize checks
that share mutable fixtures, caches, or generated outputs. Reuse specialist sessions
for rebuttals and follow-ups; serialize when the host has fewer available slots.

Route findings and rebuttals through CHIEF:

```text
Scout → Chief → Builder
Builder → Chief → Verifier
Verifier → Chief → Builder
```

Both clients use the same roles and phases. Read-heavy agents can run checks while
leaving feature code unchanged. Operator reports generated changes rather than hiding
them. Use the client's existing permissions and report what actually ran.

Review-only work ends after reconciliation; plan-only work ends after adjudication.
Implementation completes after review and required integration checks pass. If a
repair needs unavailable evidence, access, or a decision, report the specific gap.
