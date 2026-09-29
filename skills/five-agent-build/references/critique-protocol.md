# Critique and rebuttal

Critique claims and code, not personalities. Use stable IDs (S-001, B-001, V-001)
and identify the inspected diff. Distinguish facts from inferences. A clean review
is valid after serious attempts to find failures; do not manufacture disagreement.

Each finding contains:

- ID
- SEVERITY: BLOCKING | NON-BLOCKING
- CLAIM: what is wrong
- EVIDENCE: code locations, commands/results, tests, or repository facts
- IMPACT: the affected requirement or invariant
- REPRODUCTION / TEST: expected/actual behavior or static proof; say if not executed
- CONFIDENCE: HIGH | MEDIUM | LOW
- PROPOSED ACTION

Builder answers every finding by ID with STATUS (ACCEPT | PARTIALLY ACCEPT | REJECT),
RATIONALE, EVIDENCE, and ACTION. Partial acceptance separates agreed and disputed parts.

CHIEF sends disputed findings and rebuttals to the original critic for WITHDRAW,
DOWNGRADE, or MAINTAIN with updated evidence. CHIEF adjudicates remaining disputes as
ACCEPTED, PARTIALLY ACCEPTED, or REJECTED, explaining the decision. Evidence wins,
not a majority vote. Unsupported speculation does not block progress.

Track the finding, response, reconsideration, decision, fix, and verification.
Recheck accepted fixes against the original reproduction and relevant regressions.
