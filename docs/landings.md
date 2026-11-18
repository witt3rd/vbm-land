# The landings record and `land-metrics`

Several scorecards ask for the seconds Tier 1 took, the time from a commit to its landing on main, and how often Tier 1 refused. The lander measures them itself and keeps them, so a project reads its own numbers instead of writing `unmeasured`.

## The file

Every run of `land-direct` that ends in a result its JSON last line reports (landed, tier1, refused, conflict, moved, held, error, validated, checked, ...) appends ONE line to

    $(git rev-parse --git-common-dir)/vbm-land/landings.jsonl

That is inside the git directory: outside the work tree, so it never dirties a repository and never lands. It is per clone (it is lost with the clone). The hold, freeze and `--status` operations are not landings and write nothing.

```
{"v":1,"at":1790000000,"sha":"<40 hex>","base":"<40 hex>","commits":2,"tier1_seconds":31,"result":"landed","exit":0,"first_commit_at":1789999000}
```

| field | meaning |
|---|---|
| `v` | the format version, always `1` here; a reader skips a line it does not know |
| `at` | UTC seconds (epoch) when the run ended |
| `sha` | the commit that landed or was tested, as in the summary line; `null` where none was reached |
| `base` | the commit of `<remote>/<base>` the last attempt validated against; `null` before any attempt |
| `commits` | how many commits the run handed over; `null` if it stopped before counting |
| `tier1_seconds` | seconds Tier 1 took on the last attempt; `null` when it did not run (a refusal before it, or one that failed); `0` when the change was inert or reused |
| `result` | the summary line's result: `landed`, `validated`, `checked`, `tier1`, `refused`, `conflict`, `moved`, `held`, `error`, ... |
| `exit` | the exit code, as in the summary line |
| `first_commit_at` | UTC seconds of the AUTHOR time of the oldest commit handed over (the clock of "commit to main" starts when the work was committed); `null` if unknown |
| `validation` | present only as in the summary line: `inert` or `reused` (Tier 1 was not run) |

The facts are those of the summary line; the two times are added. A write that fails (an unwritable directory, a full disk) is ignored: it never changes the landing's result, its exit code or its output. Appending is one `O_APPEND` write, so landers running at once do not interleave lines. The record is not the metrics log (`metrics.jsonl`, `LAND_DIRECT_LOG`), which keeps attempts and the failing step for debugging; the landings record is the stable, typed one.

## `land-metrics`

`land-metrics [FILE]` (vendored as `.land/tool/bin/land-metrics`) reads the file (default: the one above) and prints one `name value` line each, integers only:

| name | value |
|---|---|
| `landings` | landing attempts recorded: every line but `checked` and `validated` (the two dry steps, so a validate-then-push pair counts once) |
| `landed` | lines whose result is `landed` |
| `refused-tier1` | lines whose result is `tier1` (Tier 1 refused the change) |
| `tier1-seconds-p50`, `tier1-seconds-p90` | percentiles of `tier1_seconds` over the `landed` lines in which Tier 1 ran (no `validation` key) |
| `commit-to-main-seconds-p50`, `commit-to-main-seconds-p90` | percentiles of `at - first_commit_at` over the `landed` lines with a numeric `first_commit_at` (a negative difference, from a skewed clock, counts as 0) |

**Percentile rule: nearest rank.** Sort the n values ascending; the p-th percentile is the value at 1-based rank `ceil(p * n / 100)`. There is no interpolation, so the result is one of the recorded values. For n = 10 the p50 is the 5th value and the p90 the 9th; for n = 4 the p50 is the 2nd and the p90 the 4th; for n = 1 both are that value.

**`unmeasured`, never 0.** A missing file prints every measure as `unmeasured`. A file that exists prints counts (0 is a true count there) and prints a percentile as `unmeasured` when no line gives a value for it. The commit-to-main time is from the author time of the oldest commit, so it includes the time the work waited before the lander ran; a commit made long ago and landed late shows that.

A line that does not begin `{"v":1,` is skipped.
