# Does cross-model review catch real bugs? (2026-10-30)

**Question.** Is `devguard review` worth running, and can a diff-based rule decide when?

**Method.** Seven commits from this kit, each rebuilt as an isolated two-commit repo (parent tree, then
the commit) so the reviewer could not see later fixes, old reports or later history. Each was
reviewed once by `claude` and once by `agy` (Gemini) with `devguard review` in read-only plan mode.
Findings were matched by hand against 11 bugs known to exist in those commits.

| Bug | Commit | Claude | Gemini |
|---|---|---|---|
| K1 `run()` swallowed exit codes | 031ad5e | yes | no |
| K2 sync race lost appended events | 031ad5e | yes | no |
| K3 worktree hook check | 031ad5e | no | yes |
| K4 folder-name identity merges repos | 031ad5e | no | no |
| K6 doctor --fix claimed success | 3439fd3 | no | yes* |
| K7 `--with` endless loop | ad01d3e | yes | yes* |
| K8 bad `--base` ignored | ad01d3e | yes | yes* |
| K10 backfill ids seen as divergence | 4182d66 | yes | yes* |
| K11 iCloud placeholders dropped | 4182d66 | yes | yes* |
| K12 eval tracebacks | f267642 | yes | yes* |
| K13 compare without denominators | f267642 | yes | yes* |
| **Found** | | **8/11** | **8/11** |

\* Gemini first reported these bugs earlier that day, so its score on them is biased upward. On the
four bugs neither reviewer had seen before (K1-K4): Claude 2/4, Gemini 1/4, both together 3/4.
Together the two vendors found 10/11; each found bugs the other missed.

**Controls.** 4599bdb, assumed clean, drew the same two MAJOR findings from both reviewers; one was
verified real (`python3 -c` in the gate imports a repo's own `signal.py`). The rules-only commit
3f0887a got 0 findings from Gemini and 4 debatable design remarks from Claude.

**Diff-based trigger.** A heuristic (data writes, concurrency, input parsing, error handling,
security words, size) flagged every commit that touched code and skipped only the rules-only one,
so it adds nothing over "review every code change". Not built.

**Cost.** Claude 49-173 s per review; Gemini 71-610 s (610 s for a 100 KB diff).

**Limits.** One run per commit and reviewer (model output varies between runs); 11 known bugs, all
written by one model; not every finding was checked, so precision is estimated from samples.

**Decision.** Review every code change with the other vendor before pushing; use both vendors for
changes that touch persisted data or sync. No automatic trigger.

The experiment also exposed: report files colliding when two reviews start in the same second,
bold findings not counted, untracked files missing from reviews, a multi-line command breaking the
`agent-verify` header, the gate's `python3 -c` module shadowing, and sync checks reading dataless
iCloud files. All fixed with tests in the same change as this note.
