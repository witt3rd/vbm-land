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

## 9. Seeing what is behind, and updating all of it in one reviewed change

Status: contract, written before the code. It adds two commands to `bin/land-pin` and changes nothing in sections 1
to 8, except the two deletions of section 9.7. A repository vendors three kinds of content, each with its own pin:

| kind | what it is | the pin | what "newer" means |
|---|---|---|---|
| `library` | a signed library at `vendor/NAME/` (sections 3, 4) | `.land/pins.lock`: URL, tag, commit | a tag of the source newer than the pinned tag, by version order |
| `skill` | a third-party agent skill (section 8) | `.land/skills.lock`: source URL and a full commit, per skill | the source's default-branch tip is another commit than the pinned one |
| `tool` | this lander, vendored at `.land/tool/` | `.land/PIN`: source, version, commit | a release tag of the source newer than the pinned version, by version order |

Until now each was moved by hand and nothing told a repository that it was behind (`land-pin online` only checks that a
pin still matches its tag). With many repositories and many vendored things, staying current must be one command to
SEE and one command to CHANGE, and the change must be one that a person reviews like any other.

### 9.1 `land-pin outdated [--json]`

ONLINE and READ-ONLY: it writes nothing in the working tree, the index, the lock files or the git directory of the
repository (it works in a scratch directory of its own, removed on exit, and it works on a dirty tree). It reports on
EVERY pin of EVERY kind and decides nothing from reading text (AGENTS.md: a tool never decides from reading prose).
It talks to nobody but the sources recorded in `.land/pins.lock`, `.land/skills.lock` and `.land/PIN`, with git (the
tool's own source is reached the way `land-check --upstream` reaches it today, `lib/source.sh`). A lock that is
missing is an empty lock; a lock or a PIN that is malformed is exit 2, as everywhere in this document.

**Libraries.** For each lock line: the tags of the source named exactly `vX.Y.Z` (the form the lock accepts; any other
tag is not a version and is ignored), compared NUMERICALLY by their three numbers (`v1.10.0` is newer than `v1.9.0`;
never by string). The newest of them is `newer` when it is newer than the pinned tag, else the library is current. A
pinned tag that the source no longer has is not this command's finding (`online` refuses it); the comparison is by
number all the same. THE SIGNATURE IS NOT VERIFIED AT THIS STEP, and the human form says so on the line: a newer tag
that is unsigned, or signed by a key not in `.land/land.signers`, is reported all the same, and `update` (9.2) is
where `vendor` refuses it.

**Skills, per source** (a source is a URL of the lock; all its skills share one commit). The tip is the commit that the
source's `HEAD` resolves to (its default branch). The source is behind when the tip is another commit than the pinned
one; a tip that differs and changes no locked skill is still behind (the pin would move, and with it the commit the
reviews are recorded against). For a source that is behind, from the two commits (both fetched by their full hash) and
from git's own listing only (`git diff --name-status --no-renames PINNED TIP`, a path in `-z` form), never from reading
a file:
1. for each LOCKED skill, the NAMES of the files that differ inside its directory (`ROOT/SKILL/`, with `ROOT` the
   `root:` of its `SOURCE.md`), each with git's status `A` (added), `D` (deleted) or `M` (modified) and its path
   relative to the skill directory. A rename is a `D` and an `A`. A locked skill that has no directory at the tip is
   reported with `missing_at_tip` and every one of its files as `D`;
2. whether the LICENSE file differs, on a line of its own: the one licence file of section 8.2 (`LICENSE`,
   `LICENSE.md`, `LICENSE.txt` or `COPYING`) at each of the two commits differs in name or in content, or exists at one
   commit and not at the other. A licence change can change what we may do with the source, so it is a line of its own,
   `licence: CHANGED`, never folded into a file list;
3. the skills the source has now that are neither locked nor skipped: the directories under `ROOT/` at the tip that
   hold a `SKILL.md` (git's tree listing) and whose name is neither in the lock nor a bullet under `## Not taken` of
   the source's `SOURCE.md`. These are `undecided`: each needs a take-or-skip decision before an update can proceed,
   exactly as `skill add` demands (8.3). The tool names them and decides nothing about them.

**Skill sources that publish releases** (4). When the source also has tags named `vX.Y.Z` or `X.Y.Z`, the newest by
version order is listed as `release`, with the commit it points at. It is INFORMATION: it changes no exit code, is not
a `newer`, and the pin stays a commit (8.1: a tag moves, a commit does not).

**The tool.** `newer` is the newest release tag `vX.Y.Z` of the source in `.land/PIN` when it is newer than the pinned
`version`, by number. As for a library, the signature is not verified at this step; `land-update` verifies it.

**Exit codes.** 0 nothing is behind (and every source was reached); 1 something is behind; 2 misuse (an unknown option
or argument, a malformed lock or PIN, no `.land/PIN`: the tool is not installed, not inside a git work tree); 3 a
source could not be reached, or the pinned commit of a skill source could not be fetched from it, so that nobody
knows. 1 wins over 3. A source that could not be reached is in the report with `status` `unreachable`; it never
hides the other pins. `release` and a licence that did not change are not behind.

**Typed output.** `--json` prints ONE JSON object on one line and nothing else on stdout:

    {"v":1,"behind":2,"unreachable":0,"pins":[ ...one object per pin... ]}

`v` is the version of this shape: a key added is the same `v`; a key removed or changed in meaning is a new `v`. A
pin is one object per library line, one per LOCKED SKILL (a row of the lock), one per skill SOURCE, and one for the
tool, each with these keys (a key that does not apply is `null`, never absent):

| key | meaning |
|---|---|
| `kind` | `library`, `skill`, `skill-source` or `tool` |
| `name` | the library name; the skill name; the source's slug (8.2); `vbm-land` for the tool |
| `source` | the URL recorded in the lock or the PIN |
| `pinned` | the tag (library, tool) or the full commit (skill, skill-source) |
| `newer` | the newer tag (library, tool) or the tip commit (skill, skill-source); `null` when current or unreachable |
| `status` | `current`, `behind` or `unreachable` |
| `files` | `[{"status":"A\|D\|M","path":"..."}]`, the file names of a `skill` (always `[]` for the other kinds) |

and, for kind `skill-source` only: `license_changed` (bool), `undecided` (the skill names, sorted bytewise), `release`
(`{"tag":...,"rev":...}` or `null`). A `skill` object is `behind` exactly when its source is. `behind` counts the pins
with status `behind`, `unreachable` those with status `unreachable`. Paths are JSON-escaped, so a name with a space,
a quote or a newline survives.

The human form is a RENDERING of this object, not a second source of truth: every fact in it is in the JSON, and a
test that parses both finds the same pins. One line per pin that is not current, the source's own lines indented
under it, and a last line with the counts:

    land-pin: library libx v1.2.0 -> v1.10.0 (the signature is not verified here)
    land-pin: skill source example-org-some-skills 3f9a1c7e5b2d -> 9b7d5f3e1c0a (tip)
      review-notes: M SKILL.md
      review-notes: A references/extra.md
      changelog-style: no file differs
      licence: CHANGED (LICENSE)
      undecided: deploy-helper (neither locked nor skipped: decide before an update)
      release: v2.1.0 (information; the pin stays a commit)
    land-pin: tool vbm-land v0.23.1 -> v0.24.0
    land-pin: outdated: 3 behind, 0 unreachable, 9 pins

### 9.2 `land-pin update [--all] [--only NAME...] [--dry-run]`

Produces ONE change in the working tree and NEVER COMMITS: no commit, no branch, no tag, no stash, no push, and no
change to `HEAD`. Whether the changed files are staged is not part of the contract; the person's own `git add` and
commit are. A bare `update` is `update --all` (`--all` is accepted and changes nothing); an unknown argument is misuse (exit 2). The form `skill update URL COMMIT SKILL...` is unchanged. There is no single-pin update here: one pin is moved by `vendor`, `skill update` or `land-update`, as before. `--dry-run` changes NOTHING (no file, no lock, no ref) and prints ONE line of JSON, the report of `outdated --json` with the added field `would` on every pin: `null` when the update leaves it, else `{"from":PINNED,"to":TARGET,"pending_review":BOOL}` (the tag or commit; for a skill the `files` are the names git lists as changing, and `pending_review` is true: it would return to pending review). It needs no clean tree. It exits 0 when nothing would change and 1 when something would, so a scheduled check can use it; the refusals and the unreachable source of an update are the same exits (1, 3) as without it. `--only NAME...` limits the run to the named pins: a NAME is a
library name, a skill name (it selects its whole source: a source is updated whole, one commit per source, 8.3), or
`vbm-land`; a NAME that is no pin is misuse (exit 2); a named pin that is current is left alone.

It runs the report of 9.1 FIRST, once, in this run, and updates exactly what that report named as behind (the tip
commit is the full 40-hex hash that the report resolved, never a ref that could move between the report and the
update). Then, in this order:
1. **libraries**: for each library behind, `land-pin vendor NAME URL NEWER` (section 4): the signature check, the
   `tree_sha256=` check and the tree-hash check are as they are today, and refuse as they refuse today;
2. **skills**: for each source behind, `land-pin skill update URL TIP SKILL...` naming every locked skill of the
   source, at the tip commit. Every `REVIEWED` of the source resets to `pending` (8.3), including the skill of which no
   file changed: the review was of an earlier commit. The `--license`, `--why` and `--skip` stay (8.3). The review aid
   (8.5) of each skill is printed, the diff of files and the licence line as `skill update` prints them;
3. **the tool**: `land-update NEWER` (a verified release, replacing the whole of `.land/tool/`, as `land-update` does
   today), last, because it replaces the code that is running.

The change writes under `vendor/`, `.land/` and `.agents/skills/` and nowhere else.

**It refuses, and changes nothing,** before it writes anything:
- a dirty tree: any line of `git status --porcelain`, an untracked file included (ignored files are not counted); the
  whole change must be the update, so that it can be reviewed as one;
- a skill source with an UNDECIDED new skill, naming the source and each such skill. The person decides with the
  commands of 8.3 (a `--skip` in `skill update` by hand, or taking it with `skill add`) and runs again; `update --all`
  records no decision of the person's. `--only` may leave the source out so that the rest proceed;
- a locked skill that has no directory at the tip (`skill update` demands that each exists at the new commit),
  naming it;
- a selected source that cannot be reached: exit 3.

**It is atomic.** Each kind is applied whole or not at all, and the whole run is as well: when any step refuses or
fails (a tag with no signature or a signer that is not listed, a `tree_sha256=` that disagrees, a source with no or two
licence files, a release that is not verified, a network failure half way), every kind already applied is put back, so
that after the run `git status --porcelain` prints what it printed before it (nothing, since the tree was clean), and
no file, directory or scratch copy of it is left. The message names the kind and the pin that failed, and the exit code
is 1. The tree was clean at the start, so the restoration is exact; it is made from a snapshot the tool took itself,
never by a `git stash`, a `git reset` or a `git checkout`, which are the repository's.

**It cannot be accepted unread.** After a successful run `land-pin verify` exits 1, and says why for every skill of
every source that moved: `reviewed is pending` (8.3, 3). Nothing in `update --all` records a review. The reviews are
recorded one at a time with `land-pin skill review SKILL --by NAME` after the person has read the aid and the files, so
the change fails the fast gate (and cannot land) until each is reviewed again.

**What it prints at the end,** the list of what to review and the commands to record it, and nothing it decides:
- each library moved, `NAME OLD -> NEW`, and where to read it (`git diff -- vendor/NAME`); a library has no recorded
  review, its trust is the signature and the tree hash;
- each skill, `SKILL OLD -> NEW`, with the command `land-pin skill review SKILL --by NAME`, the licence line of its
  source and the names of the files that differ;
- the tool, `OLD -> NEW`, and where to read it (`.land/tool/`, and `land-update --diff` before the update);
- the commands that finish it: `land-pin verify`, then the repository's own gate, then commit and land the change like
  any other (`land-direct`).

Exit codes: 0 done, or nothing was behind (the tree untouched); 1 refused or failed (the tree as it was; every reason
printed); 2 misuse or a malformed lock; 3 a selected source could not be reached (nothing changed). 1 wins over 3.

### 9.3 How it is used

The scheduled check that exists for the tool (`land-check --upstream`, the 6-hourly job and by hand) also runs
`land-pin outdated` and carries its last line (the counts) in its message, so that a repository that is behind says so in
one place, for every kind. Being behind is shown and is NEVER a gate: Tier 1 stays offline and fast, and `outdated`
belongs with `online` in the slow tier. Exit 3 is the job's "not verified", as for `land-check`. An agent that is told
a repository is behind runs `land-pin update --all` on a clean tree, reads the aids and the diffs, records each review
with `skill review`, runs `verify` and the repository's gate, and lands the change like any other. A person who wants
a part runs `update --all --only NAME...`.

### 9.4 Skill sources that publish releases

Section 9.1 lists the newest release tag of such a source as information. A skill pin is and stays a commit (8.1);
`update --all` moves it to the tip of the default branch, never to a tag. A person who wants a source at its newest
tag runs `skill update URL COMMIT SKILL...` with that tag's commit, by hand.

### 9.5 Non-goals

No automatic review: nothing records a `REVIEWED`, ever; no scoring, ranking or flagging of a change, a skill or a
source; no reading of the text of a skill, a licence, a changelog or a tag message (a licence is compared as a file, and
its change is shown, not judged); no network except git against the recorded sources; no commit, push, branch or pull
request; no choice for the person (an undecided skill, a take or a skip, the order of releases that are not versions);
no update of one pin of a source apart from its siblings (a source is one commit); no fetch of the missing: a
missing vendored copy stays a failure of `verify`.

### 9.6 The negative cases a test must cover (`tests/test_pin_outdated.sh`, each WATCHED to fail)

Every source is a local git repository: no network. Each negative case below is watched to fail by a mutant of the
tool (for instance `outdated` that exits 0 whatever it finds, a string comparison of versions, a listing that reads
the files, an `update` that commits, one that does not roll back), and the test is only kept when the mutant makes it
red.

`outdated`:
- misuse is exit 2: an unknown option, an extra argument, a malformed `.land/pins.lock`, `.land/skills.lock` or
  `.land/PIN` (each field), no `.land/PIN`, outside a git work tree;
- NOTHING behind is exit 0, with `"behind":0` (the case that must be ACCEPTED), and so is a repository with no lock;
- a library: a newer tag is exit 1 with the tag named; `v1.10.0` against a pin `v1.9.0` is behind and `v1.9.0` against
  a pin `v1.10.0` is not (a string comparison fails it); `v1.2`, `v1.2.3-rc1` and `latest` are ignored; the pinned tag
  as the newest is current; an UNSIGNED newer tag and one signed by an unlisted key are still reported (this step
  verifies nothing) and the line says so;
- a skill source: a tip equal to the pin is current; a tip that differs lists a changed, an added and a deleted file
  by name with `M`, `A`, `D`, a renamed file as `D` and `A`, and a path with a space, a quote and a newline intact in
  the JSON; a change in ANOTHER skill's directory is not listed under this one; a change outside every locked skill is
  `behind` with `[]`; a changed `LICENSE`, one renamed to `COPYING`, one added and one removed are each the licence
  line and `license_changed`, and an unchanged one is not; a new skill neither locked nor in `## Not taken` is
  `undecided` and named, one under `## Not taken` is not; a locked skill with no directory at the tip is
  `missing_at_tip`; a source whose tip differs from the pin ONLY in the prose of a `SKILL.md` gives the same kind of
  report as one that differs in code (the tool reads no text); a tag of the source is listed as `release` and, with
  nothing else different, the exit is 0;
- unreachable: a library source, a skill source, the tool's source and a skill source whose pinned commit cannot be
  fetched are each exit 3, shown with `unreachable`, and with another pin behind the exit is 1;
- READ-ONLY: the working tree, the index, the lock files and `.git` (refs, the object count of the repository itself,
  stash) are byte for byte as before the run, on a clean tree and on a dirty one, and no scratch directory remains;
- `--json` is one valid line with `v`, every key of 9.1 in every pin, and the same pins and counts as the human form.

`update` (bare, and `--dry-run`): bare `update` gives the result of `update --all` on the same fixture; an unknown argument is exit 2; a dry run leaves the tree and the lock byte for byte as before and exits 1 when behind, 0 when nothing is.

`update --all`:
- misuse is exit 2: no `--all`, `--only` with no name, a name that is no pin, a malformed lock;
- a dirty tree (a modified tracked file, an untracked file) is refused with the tree unchanged, and an ignored file is
  not a dirty tree (the case that must be ACCEPTED);
- an undecided skill is refused naming the source and the skill, and `--only` of the others proceeds; a locked skill
  gone at the tip is refused naming it; a selected unreachable source is exit 3 and an unselected one is not a reason;
- a newer library tag that is unsigned, signed by an unlisted key, without `tree_sha256=` or with one that disagrees
  with the tree is refused, and so is an unverified release of the tool;
- ATOMIC: a failure in the second kind (a skill source with two licence files) after the libraries were applied, and a
  failure in the third (the tool) after both others were, each leave `git status --porcelain` as it was and no stray
  directory; a failure of a library leaves the skills untouched;
- NEVER COMMITS: `HEAD`, every ref, the stash list and the reflog are as before after a success and after a refusal;
  nothing outside `vendor/`, `.land/` and `.agents/skills/` is written;
- UNREAD CANNOT PASS: after a success `land-pin verify` is exit 1 naming each moved skill as pending (the one with no
  changed file too), and a skill of a source that was not behind is not touched; after `skill review` of each,
  `verify` is exit 0 (the case that must be ACCEPTED);
- the tip it applies is the commit the report named: a source that moves between the report and the update is not
  followed (the lock holds a 40-hex commit, never a ref);
- nothing behind, or `--only` a current pin, is exit 0 with the tree untouched, and a second `update --all` after a
  success finds nothing behind;
- the license, the reasons and the skips of the earlier add are kept by the update.

### 9.7 Build order and what goes

1. `outdated` with its tests (9.6), tests first; the one function that names the newest tag of a source by version
   order lives in `lib/` and is used by `outdated`, by `land-update --check` and by nothing else.
2. `update --all` with its tests, reusing `vendor`, `skill update` and `land-update` as they are, adding no second way
   to write a pin.
3. The deletions that pay for it: the `newer:` line of `land-pin online` (it keeps its findings: a moved, deleted or
   unreachable tag), and the advice line of `land-check --upstream` about a newer release (it keeps the manifest check);
   `outdated` is the one place that says it. The scheduled job (9.3), `README.md`, the skills `update-vbm-land` and
   `vendor-a-library` and the family's hub page follow in the same piece of work; a release.
