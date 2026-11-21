# Pins and releases: one contract

Status: accepted 2026-11-11; the tools in this document are built from it, in the order of section 7. It replaces
the divergent per-repository pin scripts and the manual vendoring steps. It reuses what vbm-land already has: the
signers file `.land/land.signers`, tag signature verification (`lib/source.sh`), and `bin/land-release`.

## 1. The tree hash (one definition, used everywhere)

The tree hash of a directory is the SHA-256 of a text built like this:
- every regular file under the directory, EXCEPT anything inside a directory named `.lake` or `.git` AT ANY DEPTH
  (build products and version-control metadata; Lake builds a vendored library, and the libraries vendored inside it,
  in place);
- one line per file, `<sha256 of the file> <path relative to the directory>\n`;
- lines sorted bytewise (C locale), concatenated.
A symlink or a special file anywhere in the tree is an error. A path containing a newline or a backslash is an error
(`sha256sum` escapes both: never a silently different hash); every other path (a space, `#`, `<`, non-ASCII) is hashed
as it is, and the lines are sorted by bytes. The tree hash of a commit is the tree hash of its exported tree.

## 2. Releases

`bin/land-release` is the one release tool for every repository. It makes the annotated, SSH-signed tag
`v<VERSION>` on `origin/main`'s head, and the tag message records `tree_sha256=<tree hash of HEAD>` (vbm-land's own
tag also keeps `manifest_sha256=`, as today). Key custody is as in docs/signing.md: the key never leaves its host.
A tag is never moved or deleted.

## 3. The lock and the vendored copy

A repository vendors each direct dependency at `vendor/NAME/` and lists it in `.land/pins.lock`, one line each,
`#` comments allowed:

    NAME URL TAG REV TREE_SHA256

`TAG` is `vX.Y.Z`, `REV` 40 hex (the tag's commit), `TREE_SHA256` 64 hex. The lock is read strictly: a wrong field
count, a bad hex string, a duplicate name, a name that is not `[a-z0-9][a-z0-9_-]*` is an error (exit 2). The lock is
a protected path of the consumer: a change to it is the loosening an attacker would make.

## 4. Commands (`bin/land-pin`)

- `land-pin tree DIR`: print the tree hash of DIR.
- `land-pin vendor NAME URL TAG`: the ONLY way to add or move a pin. It fetches the tag, REFUSES unless the tag is
  signed by a key in `.land/land.signers` and its message has `tree_sha256=`, exports the tagged commit to
  `vendor/NAME/`, recomputes the tree hash and REFUSES unless it equals the recorded one, then writes the lock line.
  A bump is this command and one commit.
- `land-pin verify`: offline, fast; run by every repository's fast gate. Exit 0 only when ALL of:
  1. every lock line has `vendor/NAME/` and its tree hash equals the lock's;
  2. every directory directly under `vendor/` has a lock line (an unlocked vendored library is refused);
  3. every copy of a library found anywhere in the vendored tree, at any depth (a nested `vendor/*/vendor/NAME`),
     has the same tree hash as every other copy of it, and as the lock when the lock names it (ONE version of each
     package in the closure).
  Exit 1 with every reason when anything is wrong; exit 2 on a malformed lock.
- `land-pin online`: the slow tier. For every lock line, `git ls-remote URL refs/tags/TAG^{}` must equal REV (a moved
  or deleted tag is a finding); newer tags are reported, never applied.
- `land-pin list`: the names, one per line (for the trust ledger).

There is no fetch-on-missing mode: a missing vendored copy is a failure, never a download.

## 5. What each command must refuse (these are the negative tests, `tests/test_pin.sh`)

Edited, added, deleted vendored file; a symlink; an unlocked `vendor/` directory; a lock line with no directory; a
flipped lock hash; a malformed lock (each field, a duplicate, an unsafe name); a nested copy that differs (the
diamond); `vendor` on an unsigned tag, a tag signed by an unknown key, a tag whose message lacks `tree_sha256=` or
disagrees with the exported tree. And one thing it must ACCEPT: build products under `.lake/` inside a vendored
directory (Lake builds a path dependency in place).

## 6. Consequences

- A repository that carries its own pin script and lock deletes them. The `spec_hash` with per-consumer path lists
  and the module-root field go away: a vendored library is trusted whole and never patched.
- A release cut before this contract by hand has no `tree_sha256=` in its message, so `vendor` refuses it. Tags are
  immutable: the library gets a new version from `land-release`; the old tag stays unused.
- A fast gate that did not run the pin check (a lock read only by a scorer) now runs `land-pin verify`.

## 7. Build order (each a small change, tests first, each landing green)

1. `lib/verify.sh` (then `lib/treehash.sh`, merged into it by the one-verifier change), `land-pin tree` and `land-pin verify`, with the negative tests for them.
2. `land-pin vendor`, with its negative tests (unsigned, unknown key, missing or disagreeing `tree_sha256=`).
3. `land-pin online` and `list`; `land-release` records `tree_sha256=` and no longer requires vbm-land's own manifest
   for another repository; the skills and the README updated; a release.

## 8. Skills: vendoring a third-party agent skill set

Status: contract, written before the code (slice 1 of 2). Slice 2 builds `land-pin skill ...` and its negative tests
(section 8.8), in the same tool and with the same tree hash (section 1). Nothing in this section changes sections 1
to 7.

An agent skill is a directory with a `SKILL.md` (frontmatter with a `name` and a `description`) and any reference
files: the open Agent Skills convention. A repository vendors one by copying it from a third-party repository into
`.agents/skills/<skill>/`.

### 8.1 The trust model

A skill is TEXT AN AGENT OBEYS, so a skill set is a supply-chain surface of its own kind. It is not a library
(section 3): its source does not sign releases with a key this repository holds, so the signature step of
`land-pin vendor` cannot apply and is not faked. Instead:

- A skill set is pinned by its SOURCE URL and a FULL 40-hex COMMIT (a tag or a branch moves; a commit does not), and
  each skill directory by its TREE HASH, the one defined in section 1.
- Trust comes from a RECORDED REVIEW (who read the skill, and when) plus the pin. A skill with no recorded review is
  not trusted, and the gate says so. An update is a new pin AND a new review: the old review does not carry over.
- The lock is a protected path of the consumer, as `.land/pins.lock` is (section 3): a change to it, or to the
  recorded review, is the loosening an attacker would make.

What this does NOT give: no signature (nobody we can check vouches for the source); no guarantee that a reviewed skill
is safe (a review is a person's reading, and it is recorded, not proved); and the tool runs nothing from a skill, ever
(section 8.6). What it does give: a copy that cannot change unseen, a name for who accepted it, and a diff to read when
it moves.

### 8.2 Layout

    .agents/skills/<skill>/                       the unchanged copy, one directory per skill
    .agents/skills/THIRD-PARTY/<source-slug>/     one provenance directory per source
        SOURCE.md                                 where it came from, and what was taken and left
        LICENSE                                   the source's own licence file, byte for byte
    .land/skills.lock                             the lock

`THIRD-PARTY` is reserved: it is not a skill and never has a lock row. The SOURCE-SLUG is the URL without its scheme,
without a trailing `/` or `.git`, lowercased, every run of characters outside `[a-z0-9]` replaced by one `-`
(`https://example.org/some/skills.git` gives `example-org-some-skills`).

`SOURCE.md` has this shape; the tool writes it and reads back only the `key: value` lines and the bullets under the
two headings, never the prose after a bullet's colon:

    # Source: example-org-some-skills
    url: https://example.org/some/skills
    commit: 3f9a1c7e5b2d4086a1c3e5f70912b4d6c8e0a2f4
    license: MIT
    root: skills

    ## Taken
    - review-notes: why this one is taken
    - changelog-style: why this one is taken

    ## Not taken
    - deploy-helper: why it is deliberately left out

`LICENSE` is copied unchanged from the root of the commit. The tool accepts exactly one file there named `LICENSE`,
`LICENSE.md`, `LICENSE.txt` or `COPYING`; none, or more than one, is a refusal (a source with no licence file is not
vendored, and the tool never chooses between two).

The lock `.land/skills.lock`, one line per skill, `#` comments and blank lines allowed, single spaces:

    SOURCE_URL COMMIT SKILL TREE_SHA256 LICENSE_SPDX REVIEWED

`COMMIT` is 40 hex, `TREE_SHA256` 64 hex (the tree hash of `.agents/skills/<skill>/`), `SKILL` is `[a-z0-9][a-z0-9-]*`
and unique in the lock, `LICENSE_SPDX` is one token with no space (an SPDX identifier, given by the person: the tool
never reads a licence text to decide it), `REVIEWED` is `pending` or `DATE:REVIEWER`, a date `YYYY-MM-DD` and a
reviewer name with no space and no colon. The lock is read strictly like `.land/pins.lock`: a wrong field count, a bad
hex string, a bad name, a duplicate skill or a bad `REVIEWED` is an error (exit 2). All the skills of one source share
one commit.

### 8.3 Commands (`bin/land-pin skill`)

Exit codes for every `skill` command: 0 done; 1 refused (every reason printed, and a refusal changes nothing: the
tree, the lock and `THIRD-PARTY` are as they were); 2 usage, or a malformed lock.

The source's skills live in a directory of the commit, `skills/` unless `--root PATH` says otherwise: `PATH/<skill>/`.

- `land-pin skill add URL COMMIT SKILL... --license SPDX --why SKILL=TEXT... [--skip SKILL=TEXT...] [--root PATH]`:
  the ONLY way to add a skill. It fetches exactly that commit with git, and REFUSES: a COMMIT that is not 40 hex
  characters (never a ref, a tag or an abbreviation); a commit that cannot be fetched; a skill directory missing from
  the commit; a skill directory with no `SKILL.md`, or whose frontmatter lacks `name` or `description` (a non-empty
  value; a `>` or `|` block counts when an indented line follows) or whose `name` is not the directory name; a
  symlink or special file in the tree; a source with no licence file; a SKILL already locked or already present at
  `.agents/skills/<skill>/`; a missing `--why` for a taken skill; and any skill directory of the source (a directory
  under the root with a `SKILL.md`) that is neither taken nor given a `--skip` reason. Then it copies the directories
  unchanged, writes the rows with `pending`, writes `SOURCE.md` and `LICENSE`, prints the review aid (section 8.5),
  and exits 0. The `--why` and `--skip` texts are the person's: the tool records them verbatim and judges none.
- `land-pin skill review SKILL --by REVIEWER`: records `DATE:REVIEWER` (today's date, UTC) in the row. It REFUSES an
  unknown skill, a reviewer name with a space or a colon, and a skill whose tree hash no longer matches the lock (what
  was read is not what is there). Without `--by` it prints the review aid for SKILL and records nothing.
- `land-pin skill adopt URL COMMIT SKILL... --license SPDX --why SKILL=TEXT... [--skip ...] [--root PATH]`: for a
  copy ALREADY in the tree. It fetches the commit and verifies that each local directory equals the commit's
  directory byte for byte (the same file set as the tree hash, section 1); a difference is REFUSED naming the first
  differing path, in bytewise order (a file only on one side, or with different content). All the refusals of `add`
  that do not concern the copy apply. It then writes the rows (`pending`), `SOURCE.md` and `LICENSE` WITHOUT copying
  anything, and prints the review aid.
- `land-pin skill update URL COMMIT SKILL...`: re-vendors from a newer commit. It names EVERY skill locked for that
  URL (one commit per source; a partial list is refused), and each must exist at the new commit. It prints the diff of
  files added, removed and changed per skill, replaces the directories whole (a file dropped upstream disappears),
  rewrites the rows and `SOURCE.md` and `LICENSE`, resets `REVIEWED` to `pending`, prints the review aid, and exits 0.
  The checks of `add` apply to the new commit; a changed licence file is shown in the diff and is part of the review.
  The `--license`, `--why` and `--skip` of the earlier add stay unless given again.
- `land-pin skill list`: prints the lock rows as they are, one per line; exit 0.
- `land-pin skill verify`: offline and fast; `land-pin verify` runs it as well, so it is a step of every fast gate.
  It exits 0 only when none of the following holds, and otherwise exits 1 with every reason printed, each naming the
  skill or the file:
  1. a locked skill's tree hash differs from its row (an edited, added or deleted file, or a drift), or its directory
     is missing; a symlink or special file is named by path (the tree hash refuses it);
  2. a directory under `.agents/skills/` that the lock does not list is named by a `## Taken` bullet of a
     `THIRD-PARTY/*/SOURCE.md` (it claims a third-party origin and has no pin);
  3. a row is `pending` (added and not yet reviewed);
  4. `SOURCE.md` or `LICENSE` is missing for a locked skill's source, or `SOURCE.md` disagrees with the rows
     (`url`, `commit` or `license` differ, or a locked skill is not in its `## Taken`).
  Skills that belong to the tool itself (the payload's `skills/*`) and skills the repository wrote are not in the lock,
  claim no third-party origin and are not judged.

### 8.4 What a person does

`add` (or `adopt`), read the review aid and the skill, `review SKILL --by NAME`, commit the tree, the lock and
`THIRD-PARTY` together. The fast gate fails between the first and the second step, which is the point.

### 8.5 The review aid

The review aid is a READING AID. The tool decides NOTHING from it: it does not score, classify, rank or flag, and no
exit code depends on what it prints (AGENTS.md: a tool never decides from reading prose). A person, or the owner's
agent, reads it and records the review. For each skill it prints, in this order:

1. the FILE LIST: every file of the skill with its size in bytes, sorted bytewise;
2. EVERY fenced code block whose info string begins with a shell word, exactly `bash`, `sh`, `shell`, `zsh` or
   `console`, in any file of the skill, with its file and the line of its opening fence, verbatim. A fence is a line of
   three or more backquotes or tildes (up to three spaces of indent), closed by the same character at least as long; a
   block never closed runs to the end of the file and is printed as such;
3. EVERY URL HOST with its count: for each `scheme://host` in any file, the lowercased host (up to the next `/`, `:`,
   `?`, `#`, quote, bracket or space) and how many times it occurs, sorted by host.

It prints these and nothing else. A block in another language, or a command written in prose, is not printed: the file
list is there so that a person opens what the aid does not show.

### 8.6 What this does not do

It does not run anything from a skill (no script, no command from a code block, no hook), and does not check a
signature (there is none to check). It does not judge safety: a recorded review is a person's statement, not a
proof, and `verify` passing means only "this is the reviewed copy of that pinned commit". It does not read a skill to
decide anything. It cannot see a change in the source after the pin: that is the next `update`, with its diff. It does
not compare `LICENSE` or `SOURCE.md` with the source after the copy (the lock hashes the skill directories only);
they are in the commit and their change is reviewed there.

### 8.7 A worked example

After `land-pin skill add https://example.org/some/skills 3f9a1c7e5b2d4086a1c3e5f70912b4d6c8e0a2f4 review-notes changelog-style --license MIT --why review-notes=... --why changelog-style=... --skip deploy-helper=...`
the lock holds:

    # .land/skills.lock
    https://example.org/some/skills 3f9a1c7e5b2d4086a1c3e5f70912b4d6c8e0a2f4 review-notes 7692c3ad3540bb803c020b3aee66cd8887123234ea0c6e7143c0add73ff431ed MIT pending
    https://example.org/some/skills 3f9a1c7e5b2d4086a1c3e5f70912b4d6c8e0a2f4 changelog-style 3fc4ccfe745870e2c0d99f71f30ff0656c8dedd41cc1d7d3d376b0dbe685e2f3 MIT pending

`land-pin skill verify` (and `land-pin verify`) now fails, exit 1:

    land-pin: BAD review-notes: reviewed is pending (added and not yet reviewed)
    land-pin: BAD changelog-style: reviewed is pending (added and not yet reviewed)

After `land-pin skill review review-notes --by reviewer-one` and the same for `changelog-style`, the lock reads:

    https://example.org/some/skills 3f9a1c7e5b2d4086a1c3e5f70912b4d6c8e0a2f4 review-notes 7692c3ad3540bb803c020b3aee66cd8887123234ea0c6e7143c0add73ff431ed MIT 2026-11-20:reviewer-one
    https://example.org/some/skills 3f9a1c7e5b2d4086a1c3e5f70912b4d6c8e0a2f4 changelog-style 3fc4ccfe745870e2c0d99f71f30ff0656c8dedd41cc1d7d3d376b0dbe685e2f3 MIT 2026-11-20:reviewer-one

and `verify` exits 0. If someone then edits a line of `.agents/skills/review-notes/SKILL.md`, and copies in a skill
`.agents/skills/extra-skill/` that `THIRD-PARTY/example-org-some-skills/SOURCE.md` lists under `## Taken` but the lock
does not:

    land-pin: BAD review-notes: the tree hash is 8b5b9db0c13db24256c829aa364aa90c6d2eba318b9232a4ab9313b954d3555f, the lock says 7692c3ad3540bb803c020b3aee66cd8887123234ea0c6e7143c0add73ff431ed (an edited, added or deleted file)
    land-pin: BAD extra-skill: .agents/skills/extra-skill claims a third-party origin (THIRD-PARTY/example-org-some-skills/SOURCE.md) and is not in the lock

and the exit code is 1. A later `land-pin skill update https://example.org/some/skills 9b7d5f3e1c0a8264e6c4a2f0d8b6e4c2a0f81357 review-notes changelog-style`
prints the files added, removed and changed, rewrites both rows with the new commit and hash and `pending`, and the
gate fails again until each skill is reviewed again.

### 8.8 What each command must refuse (the negative tests of slice 2, each watched to fail)

`add`: a short or non-hex commit, a ref; a skill with no `SKILL.md`; frontmatter lacking `name` or `description`; a
`name` that differs from the directory; a symlink in the skill; a source with no licence file or two; a skill already
locked or present; a source skill neither taken nor skipped. `adopt`: a local copy with an extra, a missing and a
changed file (the first differing path named). `review`: an unknown skill; a changed skill; a bad reviewer. `update`:
a partial list. `verify`: an edited, added and deleted file; a missing directory; an unlisted directory with a
`THIRD-PARTY` entry; a `pending` row; a missing `SOURCE.md` and a missing `LICENSE`; a `SOURCE.md` that disagrees with
the rows; a malformed lock (each field, a duplicate, a bad `REVIEWED`, exit 2). And two things it must ACCEPT: a
tool-owned skill and a repository-written skill, neither in the lock. Slice 2 also adds the lock's name to
`lib/paths.sh`, and `land-pin verify` runs `skill verify` after the library checks.
