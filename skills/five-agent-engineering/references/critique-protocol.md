# Critique and rebuttal protocol

Target claims and implementations, never personalities. Do not manufacture dissent.
Keep finding IDs stable through repair and reconsideration (S-001, B-001, V-001).
Separate observed facts from inferences and state the inspected revision/diff.

Every critique contains:

```text
ID
<stable ID>
SEVERITY
BLOCKING | NON-BLOCKING
CLAIM
What is allegedly wrong.
EVIDENCE
Concrete code locations, tests, documentation, behavior, commands, or repository facts.
IMPACT
Why it matters and which requirement or invariant is affected.
REPRODUCTION / TEST
Steps, expected/actual results, or a precise static proof; state when not executed.
CONFIDENCE
HIGH | MEDIUM | LOW
PROPOSED ACTION
What should change.
```

BLOCKING means evidence establishes a material requirement/correctness/integration
failure that must be resolved before completion. NON-BLOCKING covers improvements
and minor risks. Severity and confidence are separate. Low-confidence speculation
requires investigation, not an automatic veto. Unsupported disagreement must not
block work; reproducible evidence outweighs unsupported assertions.

Builder answers every concrete finding:

```text
RESPONSE TO FINDING <ID>
STATUS
ACCEPT | PARTIALLY ACCEPT | REJECT
RATIONALE
...
EVIDENCE
...
ACTION
Fix made, proposed test, or reason no change is needed.
```

For partial acceptance, distinguish the accepted part and disputed part explicitly.
CHIEF returns every disputed finding plus the rebuttal to its original critic.
The critic reports WITHDRAW, DOWNGRADE, or MAINTAIN, with evidence and reasons.
If disagreement persists, CHIEF records ACCEPTED, PARTIALLY ACCEPTED, or REJECTED
and a justified disposition. Rejected critiques require technical justification.
No majority voting. No automatic deference to CHIEF, Builder, or senior-sounding text.

Accepted fixes must be checked against the original evidence and relevant regressions.
A finding ledger in the task is sufficient; do not create project files unless useful
and authorized. Track ID, critic, severity, response, reconsideration, adjudication,
fix, and verification. A clean review must name inspected scope, falsification
attempts, and limitations; absence of findings is not proof of universal correctness.
