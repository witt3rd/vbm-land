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

## Adopting it

1. Put `.gitleaks.toml` in the repository (a `[extend] useDefault = true` and, for each false positive, an allowlist entry with a comment giving the reason).
2. Pin the scanner in `mise.toml` (gitleaks 8.x).
3. Call `.land/tool/bin/land-secrets` and `.land/tool/bin/land-secrets --selftest` from the repository's Tier 1, and `.land/tool/bin/land-secrets --staged` from its pre-commit hook.

## What it does not do

* It does not pin or vendor a scanner.
* It does not decide what an allowlist may hold: the repository's review does.
* It does not rotate a secret, and it does not rewrite history.
