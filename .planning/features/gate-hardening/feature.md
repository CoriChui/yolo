---
goal: Close the gate bypasses found by the post-shipment red-team review of git-as-truth by fixing JSON parsing, path scope normalization, gate coverage holes, audit trail, and docs/test quality.
branch: feature/gate-hardening
worktree: /Users/konstantintsoy/Desktop/web/yolo
created: 2026-04-15
test_commands: ["bash scripts/yolo-cli/test-lib.sh", "bash scripts/yolo-cli/test-commit.sh", "bash scripts/yolo-cli/test-reconcile.sh", "bash scripts/yolo-cli/test-hook-pre-bash.sh", "bash scripts/yolo-cli/test-hook-pre-write.sh", "bash scripts/yolo-cli/test-hook-post-bash.sh", "bash scripts/yolo-cli/test-active-feature.sh"]
lint_commands: ["bash -n scripts/yolo-cli/lib.sh", "bash -n scripts/yolo-cli/hook-pre-bash.sh", "bash -n scripts/yolo-cli/hook-pre-write.sh", "bash -n scripts/yolo-cli/hook-post-bash.sh", "bash -n scripts/yolo-cli/active-feature.sh"]
---

## Criteria
- [ ] Both PreToolUse hooks use `jq` to parse JSON on stdin and fail closed on parse error, so escaped quotes inside commands or file paths cannot hide redirects from the gate.
- [ ] `is_path_in_scope` normalizes target paths via realpath, rejects anything outside the repo root, does prefix-only matching, and tolerates quoted or spaced entries without glob expansion.
- [ ] A new PostToolUse Bash hook inspects `git status --porcelain` after every Bash call, reverts out-of-scope modifications, and blocks with a clear message — catching inline interpreters, `dd`, `awk`, base64-decoded commands, fd redirects, branch-switch disables, and feature-file deletion bypasses.
- [ ] `.claude/settings.json` matchers cover `Task` and `mcp__*` file-writing tools in addition to Edit/Write/MultiEdit/NotebookEdit.
- [ ] Every gate block and every `YOLO_BYPASS=1` bypass appends a timestamped line to `.planning/.audit.log`.
- [ ] Status-line phase lookups are cached per HEAD SHA so idle paints no longer walk 50 commits.
- [ ] Docs and existing tests use `--apply` canonically; test fixtures isolate `GIT_CONFIG_GLOBAL`; new tests assert block-message content and cover quoted paths, chained commands, and nested feature slugs.

## Context

The `git-as-truth` feature shipped a syntactic gate layered over a Turing-complete
shell with regex-based parsing, which four post-ship reviewers (architect, red
team, code quality, test auditor) found to be bypassable in over a dozen concrete
ways. The critical bypasses cluster into four families:

1. **Broken JSON parsing** — `grep -o '"command":"[^"]*"'` stops at the first
   escaped quote. A command like `bash -c "printf \"x\" > src/hijack.ts"` hides
   the redirect from the gate.

2. **Loose path scope matching** — the bidirectional suffix match in
   `is_path_in_scope` lets absolute paths *outside the repo* pass when they happen
   to end with an in-scope filename. No realpath normalization exists.

3. **Coverage holes** — gates only match Bash and Edit/Write; `Task`,
   `WebFetch`, and `mcp__*` filesystem tools bypass entirely. Inline interpreters
   (`python -c`, `node -e`), `dd`, `awk`, fd redirects, and base64-decoded
   commands leave no textual trace for the regex to catch.

4. **State manipulation** — `git switch main` disables the gate on subsequent
   edits; deleting the feature file triggers the graceful-allow path.

Syntactic gating over shell cannot win this race. This feature adds a
**PostToolUse Bash diff check** that inspects the working tree *after* every
Bash call using `git status --porcelain`, reverts out-of-scope changes, and
exits 2. That single mechanism closes families 3 and 4 entirely — it doesn't
matter how the write was produced; if it landed in a file not in the plan
scope, it is undone. Families 1 and 2 are closed by proper JSON parsing and
realpath-based scope comparison. The remaining tasks add audit trail,
caching, and test/doc polish.

## Plan

1. [ ] Replace `grep -o` JSON extraction in `hook-pre-bash.sh` and `hook-pre-write.sh` with `jq -r` reads of `.tool_input.command` and `.tool_input.file_path`/`.tool_input.notebook_path`, require `jq` as an explicit dependency, and fail closed (exit 2) when JSON parsing fails instead of silently exit 0
  - files: scripts/yolo-cli/hook-pre-bash.sh, scripts/yolo-cli/hook-pre-write.sh, scripts/yolo-cli/test-hook-pre-bash.sh, scripts/yolo-cli/test-hook-pre-write.sh
  - test: bash scripts/yolo-cli/test-hook-pre-bash.sh && bash scripts/yolo-cli/test-hook-pre-write.sh

2. [ ] Rewrite `is_path_in_scope` in `lib.sh` to normalize target and scope entries via a pure-shell realpath emulation rooted at the repo, reject any target whose normalized path is outside the repo root, do prefix-only matching for directory entries, run the entry split with `set -f` active so globs do not expand, and update test-lib.sh with cases for absolute paths, quoted/spaced paths, and nested feature slugs
  - files: scripts/yolo-cli/lib.sh, scripts/yolo-cli/test-lib.sh
  - test: bash scripts/yolo-cli/test-lib.sh

3. [ ] Create `scripts/yolo-cli/hook-post-bash.sh` as a PostToolUse hook that runs `git status --porcelain` after every Bash call, compares each modified/added/deleted path against the active plan's scope via `is_path_in_scope`, reverts out-of-scope changes with `git checkout --` or `git reset`, and exits 2 with an actionable message listing what was reverted
  - files: scripts/yolo-cli/hook-post-bash.sh, scripts/yolo-cli/test-hook-post-bash.sh
  - test: bash scripts/yolo-cli/test-hook-post-bash.sh

4. [ ] Update `.claude/settings.json` to mount `hook-post-bash.sh` under PostToolUse Bash and extend the existing PreToolUse Edit/Write matcher to include `Task` and `mcp__.*` (regex) so sub-agent dispatch and MCP filesystem tools pass through the same scope gate as direct Edit/Write tool calls
  - files: .claude/settings.json
  - test: none (configuration change — verified manually by confirming JSON validity and observing hooks fire in a Claude Code session)

5. [ ] Add an `audit_log` helper to `lib.sh` that appends timestamped JSON-ish lines to `.planning/.audit.log`, invoke it from `hook-pre-bash.sh`, `hook-pre-write.sh`, and `hook-post-bash.sh` on every block and every `YOLO_BYPASS=1` honor, and add test coverage verifying line format and presence under both block and bypass paths
  - files: scripts/yolo-cli/lib.sh, scripts/yolo-cli/hook-pre-bash.sh, scripts/yolo-cli/hook-pre-write.sh, scripts/yolo-cli/hook-post-bash.sh, scripts/yolo-cli/test-lib.sh, scripts/yolo-cli/test-hook-pre-bash.sh, scripts/yolo-cli/test-hook-pre-write.sh
  - test: bash scripts/yolo-cli/test-lib.sh && bash scripts/yolo-cli/test-hook-pre-bash.sh

6. [ ] Cache the output of `get_current_phase` per HEAD SHA by writing to `/tmp/yolo-phase-$USER-<sha>` and reading the cached value when the HEAD SHA is unchanged so status-line paints no longer walk up to 50 commits with 100+ `git interpret-trailers` subprocesses on every refresh
  - files: scripts/yolo-cli/lib.sh, scripts/yolo-cli/active-feature.sh, scripts/yolo-cli/test-active-feature.sh
  - test: bash scripts/yolo-cli/test-active-feature.sh

7. [ ] Sweep the docs to use `--apply` as the canonical reconcile flag while keeping `--fix` as a documented alias, isolate all tests with `GIT_CONFIG_GLOBAL=/dev/null`/`HOME="$TMPDIR_TEST"` to avoid user gpg/sign config interference, add stderr content assertions to hook tests so block-message regressions are caught, and add test cases for quoted paths, chained commands with `&&`, and nested feature slugs like `feature/foo/bar`
  - files: .claude/yolo/loop.md, .claude/yolo/reference/scripts.md, docs/getting-started.md, scripts/yolo-cli/test-hook-pre-write.sh, scripts/yolo-cli/test-hook-pre-bash.sh, scripts/yolo-cli/test-active-feature.sh, scripts/yolo-cli/test-lib.sh
  - test: bash scripts/yolo-cli/test-hook-pre-bash.sh && bash scripts/yolo-cli/test-hook-pre-write.sh

## Verification
(Written by check step)
