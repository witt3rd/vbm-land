# Changelog

Interface (the stable part): the `land.conf` keys, the exit codes, the JSON last line, the hook names and the marker file names.
Additive changes to it are minor releases; anything else is major.

## Unreleased (0.3.0-dev)
- Pinned vendoring: `install`, `scripts/land/PIN`, `MANIFEST.sha256`, `bin/land-check` (offline and `--upstream`), `bin/land-update`, `bin/land-audit`, `bin/land-manifest`; the lander refuses (exit 12) a change that makes the vendored copy differ from its pin.
- `templates/`: starter `land.conf`, agent-instructions block, CI workflow.

- `bin/land-direct`: configurable lander (lock with lease, hold and freeze markers, land-time checks, regeneration of generated files, hooks, bounded steps, metrics log).
- `bin/land-red`: one red definition with the modes `push`, `push+dispatch`, `off`, an infrastructure classifier and the freeze marker.
- `scripts/bootstrap-land`: minimal lander, the recovery path.
- Test suite with a negative test per refusal.
