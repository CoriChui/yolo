# Acceptance: Standalone acts + routing consistency

Run from repo root.

```sh
set -e
fail=0
for s in yolo-status yolo-roadmap yolo-intake yolo-decide yolo-init; do
  f=".claude/skills/$s/SKILL.md"
  test -f "$f" || { echo "MISSING $f"; fail=1; continue; }
  head -1 "$f" | grep -qx -- '---' || { echo "NO-FRONTMATTER $s"; fail=1; }
  grep -q "name: $s" "$f" || { echo "NAME-MISMATCH $s"; fail=1; }
done
grep -q 'git branch --merged' .claude/skills/yolo-status/SKILL.md || { echo "status not deriving"; fail=1; }
grep -q 'workspace/features/<slug>/brief.md' .claude/skills/yolo-roadmap/SKILL.md || { echo "roadmap path"; fail=1; }
grep -q 'workspace/intake/<source>/' .claude/skills/yolo-intake/SKILL.md || { echo "intake shelf path"; fail=1; }
grep -q 'workspace/decisions/<slug>.md' .claude/skills/yolo-decide/SKILL.md || { echo "decide path"; fail=1; }
test -f .claude/yolo/templates/claude-routing-block.md || { echo "routing template missing"; fail=1; }
grep -q 'yolo-feature' .claude/yolo/templates/claude-routing-block.md || { echo "routing not pointing at feature"; fail=1; }
grep -q 'YOLO:routing-block start' CLAUDE.md || { echo "routing block not installed in repo"; fail=1; }
test "$fail" = 0 && echo "ALL-CONSISTENT" || { echo "INCONSISTENT"; exit 1; }
```

Expected final line: `ALL-CONSISTENT`.
