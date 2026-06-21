---
name: yolo-finish
description: Use when a feature is implemented and verified, to land it. Default path is PR + CI gate + auto-merge on green; fast-local is the escape hatch. Includes the risk classifier that decides auto-merge vs human review. Triggers on "ship it", "land this", "open a PR", or as the finish step of yolo-feature.
---

# yolo-finish

Land verified work. Match the rigor to the risk.

## Precondition
The branch carries `YOLO-Verified: true` (`.claude/yolo/conventions.md`). If not, run yolo-verify first.

## Choose the path (read `workspace/config.yaml` `finish.mode`)
- **fast-local** (`mode: local`, or user says throwaway/offline): merge locally —
  `git switch <base_branch> && git merge --no-ff feature/<slug> -m "merge: feature/<slug>"`.
  The condensed summary goes in the merge-commit message. No forge.
- **PR** (`mode: pr`, the default): push the branch and open a PR/MR
  (`gh pr create` / `glab mr create`). The PR description IS the summary — generated from
  the brief (what) + plan (how) + diff (the work) + verification (evidence).

## CI gate (PR path; `finish.ci`)
- `auto`: if the repo has CI, require green before merge; if it has none, fall back to the yolo-verify result as the gate.
- `require`: always demand green CI. `off`: never wait on CI.

## Risk classifier (PR path — decides auto-merge vs human review)
Default to auto-merge on green; escalate to human review on ANY trigger; when uncertain, escalate.
Compute against the diff `git diff <base_branch>..feature/<slug>` and `workspace/config.yaml` `risk.*`.

Hard triggers (always stop for the human, even in `ux.mode: auto`):
- yolo-verify did not cleanly pass, or success_criteria were vague.
- Diff touches any `risk.sensitive_paths` glob.
- Deletes/renames a public API or widely-imported symbol.

Soft triggers (escalate when crossed):
- Changed lines > `risk.max_diff_lines` OR changed files > `risk.max_diff_files`.
- A new external dependency added (package-manifest change).
- New logic shipped with no accompanying tests.

Decision:
- CI red/pending → never auto-merge (red stops; pending polls).
- CI green AND no trigger → auto-merge; set the PR body to the summary.
- CI green AND a trigger fires → stop, set the PR body, surface the specific trigger(s), wait for the human.

## Hard gate
Landing on `<base_branch>` (local merge OR PR merge) is the irreversible boundary — always explicitly confirmed. Auto-merge-on-green is the *configured* form of that consent for routine work.

## Cleanup
After a successful merge, delete the branch and remove the worktree if one was created.
