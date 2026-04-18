---
goal: Close seven critical/high findings from the four-agent verification review — orphan cleanup, doc rewrites, feature-file tamper guard, snapshot hardening, and dead hook removal.
branch: feature/hardening-round-2
worktree: /Users/konstantintsoy/Desktop/web/yolo
created: 2026-04-18
test_commands: ["bash scripts/yolo-cli/test-lib.sh", "bash scripts/yolo-cli/test-hook-pre-bash.sh", "bash scripts/yolo-cli/test-hook-pre-write.sh", "bash scripts/yolo-cli/test-hook-post-bash.sh"]
lint_commands: ["bash -n scripts/yolo-cli/lib.sh", "bash -n scripts/yolo-cli/hook-pre-bash.sh", "bash -n scripts/yolo-cli/hook-post-bash.sh"]
---

## Criteria
- [ ] Dead `hook-post-write.sh` wiring removed from settings.json; no PostToolUse hook errors on Edit/Write.
- [ ] Orphan files deleted: spec.md, v2/ directory, workflows/{init,release,intake,feature}.md, agents/{plan,feature-breakdown,decide,verify}.md.
- [ ] docs/getting-started.md, README.md, and status.md rewritten for the autonomous model without references to deleted commands.
- [ ] `.planning/.focus` removed from loop.md; all focus detection uses git branch.
- [ ] Feature-file deletion on a feature branch triggers fail-closed (exit 2) in pre-bash and post-bash hooks.
- [ ] Snapshot file uses mktemp with chmod 600; parallel calls don't race.
- [ ] Pre-write hook allows /tmp/*, /dev/*, /var/tmp/* paths like pre-bash does.

## Plan

1. [ ] Remove dead `hook-post-write.sh` PostToolUse entry from `.claude/settings.json` and add `/tmp/*` whitelist to `hook-pre-write.sh` so Edit/Write to temp files is consistent with Bash behaviour, matching the QA engineer finding about inconsistent `/tmp` policy
  - files: .claude/settings.json, scripts/yolo-cli/hook-pre-write.sh, scripts/yolo-cli/test-hook-pre-write.sh
  - test: bash scripts/yolo-cli/test-hook-pre-write.sh

2. [ ] Delete all orphan files that no remaining command or agent dispatches: `.claude/yolo/spec.md`, `.claude/yolo/v2/` directory, `.claude/yolo/workflows/{init,release,intake,feature}.md`, `.claude/yolo/agents/{plan,feature-breakdown,decide,verify}.md`, so the `.claude/yolo/` tree contains only active agents (research, execute, check) and reference docs
  - files: .claude/yolo/spec.md, .claude/yolo/v2/loop.md, .claude/yolo/v2/agents/check.md, .claude/yolo/v2/agents/execute.md, .claude/yolo/workflows/init.md, .claude/yolo/workflows/release.md, .claude/yolo/workflows/intake.md, .claude/yolo/workflows/feature.md, .claude/yolo/agents/plan.md, .claude/yolo/agents/feature-breakdown.md, .claude/yolo/agents/decide.md, .claude/yolo/agents/verify.md
  - test: none (file-deletion verified by ls)

3. [ ] Rewrite `docs/getting-started.md` and `README.md` to describe the autonomous workflow model where features are driven by branch state and hooks rather than explicit slash commands, removing all references to `/yolo:init`, `/yolo:start`, `/yolo:decide`, `/yolo:release` and the `.planning/.focus` state pointer
  - files: docs/getting-started.md, README.md
  - test: none (documentation, no executable tests)

4. [ ] Rewrite `.claude/commands/yolo/status.md` lines 44-50 to suggest describing intent in chat instead of running the deleted `/yolo:start`, and remove `.planning/.focus` references from `.claude/yolo/loop.md` by replacing focus-read/write with `get_active_feature` slug derivation from the git branch
  - files: .claude/commands/yolo/status.md, .claude/yolo/loop.md
  - test: none (prompt docs, verified by grep for /yolo:start and .focus)

5. [ ] Add feature-file tamper guard in `hook-pre-bash.sh` that blocks any bash command containing `rm` or `mv` targeting `.planning/features/*/feature.md`, and change `hook-post-bash.sh` to fail closed (exit 2) when branch is `feature/*` but the feature file is missing — preventing the attacker from deleting their way past the gate
  - files: scripts/yolo-cli/hook-pre-bash.sh, scripts/yolo-cli/hook-post-bash.sh, scripts/yolo-cli/test-hook-pre-bash.sh, scripts/yolo-cli/test-hook-post-bash.sh
  - test: bash scripts/yolo-cli/test-hook-pre-bash.sh && bash scripts/yolo-cli/test-hook-post-bash.sh

6. [ ] Harden the pre-bash snapshot by using `mktemp` with `chmod 600` instead of a predictable `/tmp/yolo-snap-$PPID.txt` path, passing the snapshot path to the post-hook via a pointer file keyed by the Claude session PID, so parallel tool calls and local attackers cannot poison or race on the snapshot
  - files: scripts/yolo-cli/hook-pre-bash.sh, scripts/yolo-cli/hook-post-bash.sh, scripts/yolo-cli/test-hook-post-bash.sh
  - test: bash scripts/yolo-cli/test-hook-post-bash.sh

## Verification
(Written by check step)
