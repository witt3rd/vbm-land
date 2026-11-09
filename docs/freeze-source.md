# Design: an external freeze source (not built)

> History (0.7.0): nothing runs after the push in vbm-land any more (no CI, no watchdog); this note is kept as the design record it was.

Update (0.5.0): `bin/land-red` no longer exists. Landing does not read CI; the freeze marker is read by `land-direct` itself and a freeze is only ever a person's (0.7.0 then removed the revert tool too: a red main is whoever sees it with `git revert`). The Tier 2 trigger below is gone. The hook design is kept as written: it would run in `land-direct`'s freeze check.

Status: design only. Written so that a repository with its own watchdog (one that decides "landing must stop" somewhere vbm-land cannot see, such as a label on a tracking issue) can adopt
vbm-land later without losing that behaviour and without a second red definition.

## What exists

Landing stops for a fix-or-revert-only regime from two sources today, both read by `bin/land-red` (exit 14 "frozen"):

1. the **freeze marker** `<git common dir>/vbm-land/freeze` (`land-direct --freeze REASON --owner NAME --for 6h`, owner and expiry required; `--thaw`, expiry, or a landed fix clears it);
2. the **Tier 2 trigger** (`LAND_TIER2_JOB`): a real failure of that job in the latest completed run writes a marker owned by `land-red` (24 h), a green run lifts it.

## The gap

A watchdog that keeps its state elsewhere (an issue label, a ticket, a file on a server) cannot write the marker (it runs in CI, not in the clone) and should not have to. Today the only way to honour it would be a
repository-specific red command, which is exactly what must not exist: **red has one definition** (`land-red`: the Tier 1 job of the latest push run failed).

## Proposal: `.land/land.d/freeze`, a hook that can only add a freeze

An optional repository-owned executable, taken from `origin/<base>` like every hook, run by `land-red` right before the marker check, bounded by `LAND_STEP_TIMEOUT`, in the scratch worktree:

| Exit | Meaning | `land-red` |
|---|---|---|
| 0 | not frozen | continues (the hook can never lift a freeze, never turn red green, never skip a check) |
| 14 | frozen; the first stdout line is the reason | exit 14, the reason is printed with the hook's name |
| anything else, or a timeout | the hook cannot tell | exit 20: not knowable, not landing (not knowing is not green) |

Properties that keep the design honest:

- **Restricts only.** The hook's only power is to stop landing. A fix or a revert still lands on a frozen base (the lander's existing rule), so a stuck hook cannot lock out the repair.
- **One definition of red.** The red check is untouched; a hook that says "frozen" is a freeze, a different state with a different exit code (14, not 10).
- **Main's copy.** The hook is read from main, so a change cannot remove the freeze it is blocked by; it is in the protected set like every hook.
- **No expiry in vbm-land.** The source of truth is elsewhere; the hook's answer is read at every landing. (A hook that wants an expiry implements it; the marker's owner and expiry rule applies to what vbm-land itself writes.)
- **Visible.** `land-direct --status` prints the hook's current answer; the metrics line records the result `held` as for any freeze.

## What it enables

A repository that freezes on a label of a tracking issue ships `.land/land.d/freeze` as: ask `gh` for the label, print its reason, exit 14, else 0. Its own tooling keeps the labels and reverts what makes main red (vbm-land does not own
reverting); nothing in vbm-land knows the repository.

## Slice (when a consumer needs it)

| # | Slice | Done when |
|---|---|---|
| F1 | The `freeze` hook in `land-red` and `land-direct --status`; README section; tests with the real hook runner and negative cases (exit 14 stops, exit 0 passes, exit 3 and a timeout are exit 20, a fix still lands, a change cannot replace the hook, the hook cannot make a red main green) and a mutation entry | the suite passes and each refusal is shown to fail without its guard |

## Questions for the owner

- Is a freeze that is read at every landing from a place vbm-land cannot see acceptable, given that it only ever restricts? (The alternative is porting the watchdog and the revert into vbm-land: a larger slice, an owner-and-expiry model for labels.)
