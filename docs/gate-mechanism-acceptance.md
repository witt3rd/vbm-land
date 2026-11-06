# Gate mechanism acceptance: one real approval, end to end, on the real tree

A gate mechanism (approvals, protected sets, a ratchet) is judged by its attack list and by a simulation on a scratch remote. Neither runs the **first real approval** through the **real tree**, and
that is where a test that quietly reads the repository's own approvals file fails: the first real record on the tree makes it report "the approval ... was removed without being consumed". So
before a gate mechanism is rolled to any consumer, one real approval goes end to end:

1. In a **scratch clone** of the repository at the candidate tip (never the working tree), commit one real, well-formed approval record into each real approvals file the tree has or names
   (`scripts/gate-edit-approvals.txt`, and the protected approvals file of `LAND_PROTECTED_APPROVALS` if any).
2. Run the repository's **real Tier 1** there (plus the relabel/attack suite when the repository has one apart from Tier 1). It must pass.
3. Only then roll it. A red here is a defect of a test (it read real state) or of the mechanism; fix it first.

`tests/acceptance.sh [REV]` does steps 1 and 2 for this repository (not part of Tier 1: it runs Tier 1 once more, about two minutes).

## The rule behind it

A test builds its own world: its own scratch repository, approvals file(s), protected list, base and tags. It never reads the real repository's approvals, protected list, baselines, config or tags.
`tests/lint.sh` fails a test file that names those real files by path (`$ROOT/scripts/...approvals`, a bare `scripts/...approvals` read, `git -C $ROOT tag|log|show|...`); `tests/test_harness.sh`
proves the lint can fail. The lint is a cheap net, not a proof: the acceptance step above is the proof.
