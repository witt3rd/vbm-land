# Gate mechanism acceptance: one real approval, end to end, on the real tree

A gate mechanism (approvals, protected sets, a ratchet) is judged by its attack list and by a simulation on a scratch remote. Neither runs the **first real approval** through the **real tree**, and
that is where a test that quietly reads the repository's own approvals file fails: the first real record on the tree makes it report "the approval ... was removed without being consumed". So
before a gate mechanism is rolled to any consumer, one real approval goes end to end:

1. In a **scratch clone** of the repository at the candidate tip (never the working tree), commit one real, well-formed approval record into each real approvals file the tree has or names
   (`scripts/gate-edit-approvals.txt`, and the protected approvals file of `LAND_PROTECTED_APPROVALS` if any).
2. Run the repository's **real Tier 1** there (plus the relabel/attack suite when the repository has one apart from Tier 1). It must pass.
3. Only then roll it. A red here is a defect of a test (it read real state) or of the mechanism; fix it first.

`tests/acceptance.sh [REV]` does steps 1 and 2 for this repository (not part of Tier 1: it runs Tier 1 once more, about two minutes).

## The soak (a lander that takes no lock)

`tests/soak.sh [N]` (default 20; by hand, on a machine with room, never in Tier 1) runs the real lander in a scratch world: N worktrees of ONE clone each land one commit at the same instant with a stub Tier 1 of 10-20 s (a repeat attempt re-checks for 1 s, as a repository's delta selection does with `LAND_ATTEMPT`), plus four landing one hot file and one lander killed with `kill -9` mid-validation; then a race for one real approval. It passes when every lander exits 0 and none is "busy", the remote's history is the base plus the landings, linear, with every file present, exactly one hot lander lands and the rest get exit 11, no lock file exists, the approved edit lands once and an unapproved one is refused (12). `tests/acceptance.sh --soak` runs it after the real-approval step on the candidate tree.

Two landers of the same approved edit are not a refusal case: the approval binds the exact diff of the edited file, the first lander consumes the record, and the second is rebased onto the first one's edit, so it carries no gate edit any more and lands only its other changes (two identical commits: the rebase drops the second, "already landed"). The approved edit is applied once; a lander of a different, unapproved edit is refused (12).

## The rule behind it

A test builds its own world: its own scratch repository, approvals file(s), protected list, base and tags. It never reads the real repository's approvals, protected list, baselines, config or tags.
`tests/lint.sh` fails a test file that names those real files by path (`$ROOT/scripts/...approvals`, a bare `scripts/...approvals` read, `git -C $ROOT tag|log|show|...`); `tests/test_harness.sh`
proves the lint can fail. The lint is a cheap net, not a proof: the acceptance step above is the proof.
