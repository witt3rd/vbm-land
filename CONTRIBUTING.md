# Contributing

Thank you for looking. A short, honest note about how this repository works.

## Who lands changes

**Only the owner lands changes on `main`.** The repository lands directly, with its own lander (`scripts/land-direct`): no pull request is ever merged in the GitHub sense. That is the tool's own model (README, section 1), not a lack of interest in your work.

**Outside contributions are welcome**: open an issue, or a pull request from a fork. The owner reads it, and if the change is accepted it lands through the lander as a commit (your authorship is kept where the change is applied as is; otherwise the commit says where it came from). A pull request is therefore a proposal, and may be closed with the change landed separately.

## Pull requests and CI

- CI here runs only on a push to `main` and on manual dispatch, on GitHub-hosted runners. It does not run on pull requests, and it must **never** be run on a self-hosted runner for a pull request from a fork: that would run a stranger's code on a machine of ours. A workflow that names `self-hosted` is refused by `tests/lint.sh` when the repository is public.
- Run the checks yourself: `tests/run.sh` (the lints, then every `tests/test_*.sh`; about half a minute; needs bash 4+, git 2.30+, `flock`, `timeout`, `jq`, `python3`, `ps`, `ssh-keygen`). It is the same gate the lander runs.

## What a good change looks like

- Small: at most about 150 changed lines under `bin/`, `lib/` and `scripts/`, one idea per commit.
- Conventional Commits subjects (`feat(land): ...`, `fix(red): ...`, `docs: ...`, `test: ...`).
- A test for the behaviour; a refusal gets a negative test (nothing reached the remote).
- Files under `bin/`, `lib/` and `scripts/` are gate-defining: a change to them is judged by the relabel-attack suite and by the owner before it lands, so expect more discussion there.
- An interface change (a `land.conf` key, an exit code, the JSON last line, a hook or marker name) needs a CHANGELOG line, and is a minor release if additive and a major one otherwise.
- No private names, hosts or local paths anywhere (`tests/lint.sh` refuses them).
- Releases are made only by the maintainer, signed with the release key ([docs/signing.md](docs/signing.md)). Do not edit `MANIFEST.sha256` by hand: `bin/land-manifest` regenerates it.

## Licence

By submitting a contribution you agree that it is licensed under the Apache License 2.0, as the rest of the project (section 5 of the licence).

## Security

Report vulnerabilities privately: [SECURITY.md](SECURITY.md).
