---
goal: Make git the sole source of truth for YOLO state; enforce phase/scope invariants at the tool layer via PreToolUse hooks instead of per-prompt reminders.
branch: main
worktree: /Users/konstantintsoy/Desktop/web/yolo
created: 2026-04-15
test_commands: ["bash scripts/yolo-cli/test-lib.sh", "bash scripts/yolo-cli/test-commit.sh", "bash scripts/yolo-cli/test-reconcile.sh", "bash scripts/yolo-cli/test-hook-pre-bash.sh", "bash scripts/yolo-cli/test-hook-pre-write.sh", "bash scripts/yolo-cli/test-active-feature.sh"]
lint_commands: ["bash -n scripts/yolo-cli/commit.sh", "bash -n scripts/yolo-cli/reconcile.sh", "bash -n scripts/yolo-cli/lib.sh", "bash -n scripts/yolo-cli/hook-pre-bash.sh"]
---

## Criteria
- [x] Active feature and phase are derivable from git alone (branch name + latest commit trailer), no `.planning/` state cache consulted at runtime.
- [x] Every commit made via `commit.sh` carries `YOLO-Feature: <slug>` and `YOLO-Phase: <phase>` trailers, deduped under re-runs.
- [x] `PreToolUse` hooks block Edit/Write/MultiEdit/NotebookEdit and Bash write-redirections when no feature is active or edit is out of scope.
- [x] `reconcile.sh` is read-only by default, refuses during rebase/bisect/merge, and requires `--apply` to mutate files.
- [x] Status line shows `yolo: <slug> · <phase>` when a feature is active, silent otherwise.
- [x] All existing tests still pass; new tests cover trailer emission, gate behaviour, and phase derivation.

## Context

The four-pillar goal (traceability, no slash commands, rules enforced on actions,
git in sync) requires collapsing the current two-source state model
(`.planning/` files + git) down to one. Git becomes truth; `.planning/` holds
*content* (feature specs, decision docs, lessons) not *state*.

Current repo state before this feature:
- `commit.sh` emits `[task-N]` / `[fix-N]` / `[wip]` / `[revert]` / `[squash]` prefixes only — no trailers.
- `reconcile.sh` derives task status from `[task-N]` commits (already git-sourced) but writes back to the feature file via `--fix`, making it a mutator.
- `hook-pre-bash.sh` blocks destructive git operations only; write-redirections (`sed -i`, `cat > file`, `cp`, `git checkout -- path`, `git apply`) bypass the Edit/Write hook entirely.
- No PreToolUse hook for Edit/Write; the PostToolUse hook is advisory only.
- No status line integration.
- No single helper that answers "what am I doing?" from git.

After this feature the only runtime state reads are: current branch name, latest
commit trailers, and the plan's declared file scope. Feature files remain
authored content — specs, plans, decisions — but the framework does not consult
them to decide what you are allowed to do.

Prior design analysis and reviewer findings live in the conversation thread
that produced this feature; the architect's "git is the only state" counter-design
is the direct inspiration.

## Plan

1. [ ] Add `get_active_feature`, `get_current_phase`, `parse_trailer`, and `is_path_in_scope` helpers to `lib.sh` so every downstream script derives state from git identically without duplicated parsing logic, plus scope lookup from the active feature file's `files:` annotations
  - files: scripts/yolo-cli/lib.sh, scripts/yolo-cli/test-lib.sh
  - test: bash scripts/yolo-cli/test-lib.sh

2. [ ] Modify `commit.sh` to append `YOLO-Feature: <slug>` and `YOLO-Phase: <phase>` trailers via `git interpret-trailers --if-exists replace` so re-runs and amends do not duplicate, derived from branch name and the reconcile-derived current step
  - files: scripts/yolo-cli/commit.sh, scripts/yolo-cli/test-commit.sh
  - test: bash scripts/yolo-cli/test-commit.sh

3. [ ] Create `scripts/yolo-cli/active-feature.sh` that prints the active slug and phase to stdout (or exits 1 if no feature active), used by hooks and status line, with pure git-state derivation and no `.planning/` reads beyond scope resolution
  - files: scripts/yolo-cli/active-feature.sh, scripts/yolo-cli/test-active-feature.sh
  - test: bash scripts/yolo-cli/test-active-feature.sh

4. [ ] Create `scripts/yolo-cli/hook-pre-write.sh` as a new PreToolUse hook for Edit/Write/MultiEdit/NotebookEdit that blocks writes when no feature is active and the target lives outside `.planning/`, or when the target is not in the active plan's file scope
  - files: scripts/yolo-cli/hook-pre-write.sh, scripts/yolo-cli/test-hook-pre-write.sh
  - test: bash scripts/yolo-cli/test-hook-pre-write.sh

5. [ ] Extend `hook-pre-bash.sh` to detect write-redirections (`sed -i`, `cat > file`, heredoc to file, `tee` to file, `cp`/`mv` of scoped paths, `git checkout -- path`, `git apply`) and apply the same active-feature scope gate so Bash cannot bypass the Edit/Write hook
  - files: scripts/yolo-cli/hook-pre-bash.sh, scripts/yolo-cli/test-hook-pre-bash.sh
  - test: bash scripts/yolo-cli/test-hook-pre-bash.sh

6. [ ] Refactor `reconcile.sh` to be read-only by default, rename `--fix` to `--apply`, refuse to run during active rebase/bisect/merge (detected via `.git/` marker files), and make repeated read-only runs idempotent with no side effects
  - files: scripts/yolo-cli/reconcile.sh, scripts/yolo-cli/test-reconcile.sh
  - test: bash scripts/yolo-cli/test-reconcile.sh

7. [ ] Wire `.claude/settings.json` to mount `hook-pre-write.sh` under PreToolUse matcher `Edit|Write|MultiEdit|NotebookEdit`, and add a `statusLine` entry that invokes `active-feature.sh` so the active slug and phase are visible without running `/yolo:status`
  - files: .claude/settings.json
  - test: none (configuration change — verified manually by running a Claude Code session and observing status line and gate behavior)

## Verification

passed: true

All seven tasks delivered and tested. Full test suite results from
`bash scripts/yolo-cli/run-tests.sh .planning/features/git-as-truth/feature.md`:

- `test-lib.sh`           → 33/33 passed
- `test-commit.sh`        → 59/59 passed
- `test-reconcile.sh`     → 38/38 passed (includes new unsafe-state refusal)
- `test-hook-pre-bash.sh` → 22/22 passed
- `test-hook-pre-write.sh`→ 14/14 passed
- `test-active-feature.sh`→  9/9  passed

Total: **175/175 tests green**. No regressions in the preexisting 132 tests.

Behaviour verified by direct invocation:
- `bash scripts/yolo-cli/active-feature.sh --format status` exits 1 on `main`
  (no active feature), prints `yolo: <slug> · <phase>` on feature branches.
- `commit.sh task N "..."` emits `YOLO-Feature` and `YOLO-Phase` trailers on
  feature branches; on main emits only `YOLO-Phase` for `squash`-prefixed
  commits (ship phase).
- `reconcile.sh` refuses to run with `MERGE_HEAD` present (exit 1).
  `--apply` accepted as alias for `--fix`; read-only is default.
- `hook-pre-write.sh` and extended `hook-pre-bash.sh` enforce plan scope on
  Edit/Write/MultiEdit/NotebookEdit and on shell redirections, `sed -i`,
  `tee`, `cp`/`mv`, `git checkout -- path`. `YOLO_BYPASS=1` is honored
  as an explicit escape hatch.

Limitations noted for follow-up:
- Bootstrap plan was committed directly to `main` (the framework is being
  built on itself); reconcile's merge-base logic cannot match `[task-N]`
  commits when `branch: main`. Future features will live on `feature/<slug>`
  branches where reconcile works correctly.
- No `commit-msg` hook yet to enforce trailers on direct `git commit` calls;
  commit.sh is the only trailer-emitter. Future work.
- Merge-strategy enforcement (`--no-ff`, ban squash) not yet wired into
  git config or server hooks. Future work.
