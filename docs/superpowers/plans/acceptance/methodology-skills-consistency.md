# Acceptance: Methodology skills consistency

Confirms all five skills are well-formed and agree on the Plan 1 contracts. Run from repo root.

```sh
set -e
fail=0
for s in yolo-research yolo-plan yolo-verify yolo-finish yolo-feature; do
  f=".claude/skills/$s/SKILL.md"
  test -f "$f" || { echo "MISSING $f"; fail=1; continue; }
  head -1 "$f" | grep -qx -- '---' || { echo "NO-FRONTMATTER $s"; fail=1; }
  grep -q "name: $s" "$f" || { echo "NAME-MISMATCH $s"; fail=1; }
done
grep -q 'YOLO-Task: <id>' .claude/skills/yolo-plan/SKILL.md || { echo "plan missing task trailer"; fail=1; }
grep -q 'YOLO-Verified: true' .claude/skills/yolo-verify/SKILL.md || { echo "verify missing verified trailer"; fail=1; }
grep -q 'workspace/features/<slug>/brief.md' .claude/skills/yolo-feature/SKILL.md || { echo "feature missing brief path"; fail=1; }
python3 -c "import yaml; r=yaml.safe_load(open('.claude/yolo/templates/config.yaml'))['risk']; assert {'sensitive_paths','max_diff_lines','max_diff_files'} <= set(r)" || { echo "config/finish drift"; fail=1; }
test "$fail" = 0 && echo "ALL-CONSISTENT" || { echo "INCONSISTENT"; exit 1; }
```

Expected final line: `ALL-CONSISTENT`.
