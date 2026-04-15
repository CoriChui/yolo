---
goal: Make git the sole source of truth for YOLO state; enforce phase/scope invariants at the tool layer via PreToolUse hooks instead of per-prompt reminders.
branch: main
worktree: /Users/konstantintsoy/Desktop/web/yolo
created: 2026-04-15
test_commands: ["bash scripts/yolo-cli/test-lib.sh", "bash scripts/yolo-cli/test-commit.sh", "bash scripts/yolo-cli/test-reconcile.sh", "bash scripts/yolo-cli/test-hook-pre-bash.sh", "bash scripts/yolo-cli/test-hook-pre-write.sh", "bash scripts/yolo-cli/test-active-feature.sh"]
lint_commands: ["bash -n scripts/yolo-cli/commit.sh", "bash -n scripts/yolo-cli/reconcile.sh", "bash -n scripts/yolo-cli/lib.sh", "bash -n scripts/yolo-cli/hook-pre-bash.sh"]
---

## Criteria
- [ ] Active feature and phase are derivable from git alone (branch name + latest commit trailer), no `.planning/` state cache consulted at runtime.
- [ ] Every commit made via `commit.sh` carries `YOLO-Feature: <slug>` and `YOLO-Phase: <phase>` trailers, deduped under re-runs.
- [ ] `PreToolUse` hooks block Edit/Write/MultiEdit/NotebookEdit and Bash write-redirections when no feature is active or edit is out of scope.
- [ ] `reconcile.sh` is read-only by default, refuses during rebase/bisect/merge, and requires `--apply` to mutate files.
- [ ] Status line shows `yolo: <slug> · <phase>` when a feature is active, silent otherwise.
- [ ] All existing tests still pass; new tests cover trailer emission, gate behaviour, and phase derivation.

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
(Written by check step)
