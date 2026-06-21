# Acceptance: Post-demolition integrity

Run from repo root. Proves the v2 surface is gone and the v-next surface is intact.

```sh
set -e
fail=0
# v2 surface is gone:
for p in .claude/yolo/spec.md .claude/yolo/agents .claude/yolo/workflows .claude/commands/yolo; do
  test -e "$p" && { echo "STILL-PRESENT $p"; fail=1; }
done
# v-next surface is present:
for s in yolo-research yolo-plan yolo-verify yolo-finish yolo-feature \
         yolo-status yolo-roadmap yolo-intake yolo-decide yolo-init; do
  test -f ".claude/skills/$s/SKILL.md" || { echo "MISSING-SKILL $s"; fail=1; }
done
test -f .claude/yolo/conventions.md || { echo "MISSING conventions.md"; fail=1; }
grep -q 'YOLO:routing-block start' CLAUDE.md || { echo "routing block gone"; fail=1; }
# no dangling live references to deleted paths:
grep -rqE 'yolo/spec\.md|yolo/agents/|yolo/workflows/|commands/yolo/' \
  .claude/skills .claude/yolo/conventions.md .claude/yolo/templates CLAUDE.md 2>/dev/null \
  && { echo "DANGLING-REF"; fail=1; } || true
test "$fail" = 0 && echo "INTEGRITY-OK" || { echo "INTEGRITY-FAIL"; exit 1; }
```

Expected final line: `INTEGRITY-OK`.
