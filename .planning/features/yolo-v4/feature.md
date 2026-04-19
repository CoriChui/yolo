---
goal: Rewrite hooks from bash to Node.js, merge all hardening work, clean orphans
branch: feature/yolo-v4
created: 2026-04-19
---

## Plan
1. [ ] Rewrite all hooks to Node.js replacing bash scope logic with path.resolve and native JSON.parse, wire settings.json, delete orphan workflows/spec/v2, write Node test suite covering symlinks, absolute paths, quoted entries, escaped JSON
  - files: scripts/yolo-cli/node/yolo.js, scripts/yolo-cli/node/hook-pre-write.js, scripts/yolo-cli/node/hook-pre-bash.js, scripts/yolo-cli/node/hook-post-bash.js, scripts/yolo-cli/node/hook-session-start.js, scripts/yolo-cli/node/active-feature.js, scripts/yolo-cli/node/test-yolo.js, .claude/settings.json, .claude/yolo/workflows/status.md, .claude/yolo/workflows/feature.md, .claude/yolo/workflows/init.md, .claude/yolo/workflows/intake.md, .claude/yolo/workflows/release.md, .claude/yolo/spec.md, .claude/yolo/v2/loop.md, .claude/yolo/v2/agents/check.md, .claude/yolo/v2/agents/execute.md, .claude/yolo/agents/execute.md, .claude/yolo/agents/research.md, .claude/yolo/agents/check.md, .claude/yolo/agents/debug.md, .claude/yolo/reference/scripts.md, .claude/commands/yolo/help.md, .claude/commands/yolo/status.md, .claude/commands/yolo/debug.md, docs/getting-started.md, README.md, scripts/yolo-cli/hook-pre-bash.sh, scripts/yolo-cli/hook-pre-write.sh, scripts/yolo-cli/hook-post-bash.sh, scripts/yolo-cli/active-feature.sh, scripts/yolo-cli/hook-session-start.sh, scripts/yolo-cli/lib.sh, scripts/yolo-cli/test-hook-pre-bash.sh, scripts/yolo-cli/test-hook-pre-write.sh, scripts/yolo-cli/test-hook-post-bash.sh, scripts/yolo-cli/test-active-feature.sh, scripts/yolo-cli/test-lib.sh, scripts/yolo-cli/verify-commit.sh, scripts/yolo-cli/test-verify-commit.sh, scripts/yolo-cli/test-validate-plan.sh, scripts/yolo-cli/test-integration.sh, .claude/yolo/loop.md
  - test: node scripts/yolo-cli/node/test-yolo.js

2. [ ] Validate all existing bash tests still pass alongside the new Node hooks, ensuring backward compatibility of commit.sh, reconcile.sh, validate-plan.sh, and run-tests.sh which remain as bash scripts
  - files: scripts/yolo-cli/commit.sh, scripts/yolo-cli/reconcile.sh, scripts/yolo-cli/validate-plan.sh, scripts/yolo-cli/run-tests.sh
  - test: bash scripts/yolo-cli/test-commit.sh
