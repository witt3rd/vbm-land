# The secret gate: `land-secrets`

The rule "no secrets in any repository" is a gate, not a sentence. `bin/land-secrets` (vendored in `.land/tool/bin/`) runs a secret scanner over the whole history and the working tree of a repository, fails closed, and carries a negative self-test that has been watched to fail.

## The division of work

| | owns |
|---|---|
| the tool | HOW the scanner is run: what is scanned, the exit codes, the negative self-test, the sentence a finding prints |
| the repository | WHICH: its `.gitleaks.toml` and the allowlist in it, with a reason written beside every entry |
| the repository | the scanner itself: it PINS gitleaks 8.x in its `mise.toml` |

The tool never vendors or pins a scanner, and never scans with a default configuration: a repository that runs the gate declares its own.

## Use

```
.land/tool/bin/land-secrets [--selftest] [--staged] [--config FILE] [--runner CMD]
```

Run it from any directory inside the repository; it works from the repository root.

* Default: the WHOLE HISTORY (`gitleaks git`), then the WORKING TREE (`gitleaks dir`), both with `--redact --no-banner --config FILE`. A secret committed once and deleted since is still found: it is still in the history.
* `--staged`: only what is staged (`gitleaks git --pre-commit --staged`), for a pre-commit hook.
* `--config FILE`: the scanner's configuration; default `.gitleaks.toml` at the repository root. A missing file is exit 2.
* `--runner CMD`: the command prefix that runs the scanner (for example `mise exec --`). Without it: the environment variable `LAND_SECRETS_RUNNER`; else `mise exec --` when `mise.toml` exists and `mise` is on PATH; else the bare `gitleaks` on PATH. The scanner's version is the repository's pin, never the tool's.
* `--selftest`: the negative self-test (below). It needs no history, only the configuration.

## Exit codes

| code | meaning |
|---|---|
| 0 | clean |
| 1 | a secret was found (or, with `--selftest`, the gate is blind or reports a clean file). The scanner's redacted report tail is printed, then `a secret is in the history or the tree: rotate it first, then remove it; never allowlist a real one` |
| 2 | the gate could not run: no scanner, no configuration, not inside a repository, an unknown option, or the scanner failed for another reason. FAIL CLOSED: the message says which. A scanner fatal error is told from a finding by its `FTL` line, because gitleaks uses exit 1 for both |

A secret value is never printed: the scanner always runs with `--redact`.

## The findings rule

A secret found in history means **ROTATE IT FIRST, then remove it.** Removing it from the history does not unleak it. Never allowlist a real one. An allowlist entry is a reviewed false positive, with its reason written beside it; what an allowlist may hold is decided by the repository's review, not by this tool.

## The negative self-test: `--selftest`

A gate that cannot fail proves nothing. In a temporary directory (removed on exit) the self-test writes a file holding a token-shaped string and a clean file, and runs the scanner on each with the repository's own configuration. The planted file MUST exit 1 and the clean one MUST exit 0; it prints `ran: secrets-selftest: 2 cases`. A scanner that finds nothing (or a configuration that allowlists the planted shape) fails it with exit 1; a scanner that reports the clean file fails it with exit 1.

The planted token is built at run time from fragments and is never a literal in this repository's source: this repository is scanned by its own gate, and a literal planted secret in a tool that scans for secrets would be found by it. `tests/test_secrets.sh` proves the self-test can fail, with a scanner stub that always exits 0.

## The protected set: the gate's own files

A secret gate that a change can reconfigure is no gate: the change could allowlist its own secret. So `bin/land-direct` protects the gate's files.

* **When:** `.gitleaks.toml` exists at the repository root of the BASE (`origin/main`). The presence of the file is the opt-in, exactly as `.land/lean.conf` turns on the Lean gates. A repository without it is unchanged, byte for byte.
* **What:** `.gitleaks.toml`, `.gitleaksignore` and `.githooks/*`, in addition to whatever `LAND_PROTECTED` names.
* **The rule:** a landing that touches any of them (adds, edits, deletes, or renames away from one) lands only with one conscious `Protected: <reason>` trailer in any of its commits. Without it, `land-direct` stops with exit 12 (refused), names the files, and nothing is pushed. With it, the landing goes on: it is counted as touching the protected set (`LAND_PROTECTED_TOUCHED`, no Tier 1 reuse, no inert skip) and every gate must still pass.
* **Read from the base, never from the change:** a change that deletes `.gitleaks.toml` does not escape the rule in the same landing; the deletion itself touches a protected path and needs the trailer.
* **The opt-in itself:** the first landing that ADDS `.gitleaks.toml` is judged by the base, which has none, so this rule does not refuse it. That landing is a conscious act of the repository's own review; every later change to the file is protected.

The trailer is a conscious act, not an approval: the reason is written once, in the commit, for whoever reviews it. The findings rule above still holds: a trailer is never the way to allowlist a real secret.

## Adopting it

1. Put `.gitleaks.toml` in the repository (a `[extend] useDefault = true` and, for each false positive, an allowlist entry with a comment giving the reason).
2. Pin the scanner in `mise.toml` (gitleaks 8.x).
3. Call `.land/tool/bin/land-secrets` and `.land/tool/bin/land-secrets --selftest` from the repository's Tier 1.
4. Install the pre-commit hook (below).

## The pre-commit hook

`templates/pre-commit-secrets` (in a consumer, `.land/tool/templates/pre-commit-secrets`) is the hook. Per clone:

```
cp .land/tool/templates/pre-commit-secrets .githooks/pre-commit
chmod +x .githooks/pre-commit
git config core.hooksPath .githooks     # once per clone
mise install                            # the repository's pinned scanner
```

The hook changes to the top level and runs `.land/tool/bin/land-secrets --staged`. When that exits non-zero it refuses the commit with exit 1 and says `Nothing was committed. Secrets live in your secret manager, never in a repository.` It fails CLOSED: with the hook installed, a commit is refused when the scanner cannot run (no scanner, no `.land/tool/`).

Say it plainly: the hook is the EARLY warning and a per-clone opt-in (a clone that never set `core.hooksPath`, or a commit with `--no-verify`, skips it). The gate in Tier 1 is the one that cannot be skipped. `.githooks/*` is in the protected set, so a change to the hook needs the `Protected:` trailer.

## What it does not do

* It does not pin or vendor a scanner.
* It does not make the hook binding: the hook is per clone; Tier 1 is the gate.
* It does not decide what an allowlist may hold: the repository's review does.
* It does not rotate a secret, and it does not rewrite history.
