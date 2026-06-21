# Acceptance: Foundation git round-trip

Proves the git-as-truth conventions (`.claude/yolo/conventions.md`) derive correct
status. Run top-to-bottom in a scratch repo; every command's expected output is shown.

```sh
set -e
TMP=$(mktemp -d); cd "$TMP"
git init -q -b main
git config user.email t@t.test; git config user.name test
git commit -q --allow-empty -m "init"

# 1) planned: brief exists, no branch
mkdir -p workspace/features/export-csv
printf -- '---\nslug: export-csv\ngoal: export data as csv\nsuccess_criteria: ["downloads a .csv"]\nmilestone: null\ndepends_on: []\nintake_refs: []\ncreated_at: 2026-06-21T00:00:00Z\n---\n# Export CSV\n' > workspace/features/export-csv/brief.md
git add . && git commit -q -m "brief: export-csv"
git branch --list feature/export-csv | grep -q . && echo "BRANCH" || echo "planned"     # -> planned

# 2) in-progress: branch with a task commit carrying a trailer
git switch -q -c feature/export-csv
echo "col,val" > export.csv
git add export.csv
git commit -q -m "feat: add csv export" --trailer "YOLO-Task: add-csv-export"
git switch -q main
git branch --merged main | grep -qx '  feature/export-csv' && echo "done" || echo "in-progress"   # -> in-progress
git log main..feature/export-csv --format='%(trailers:key=YOLO-Task,valueonly)' | sed '/^$/d'      # -> add-csv-export

# 3) verify: trailer + verification.md
git switch -q feature/export-csv
echo "verified: criteria met" > workspace/features/export-csv/verification.md
git add workspace/features/export-csv/verification.md
git commit -q -m "verify: export-csv" --trailer "YOLO-Verified: true"
git log main..feature/export-csv --format='%(trailers:key=YOLO-Verified,valueonly)' | grep -qx true && echo "verified"   # -> verified

# 4) done: merge to base
git switch -q main
git merge -q --no-ff feature/export-csv -m "merge: feature/export-csv"
git branch --merged main | grep -q 'feature/export-csv' && echo "done" || echo "NOT-DONE"   # -> done

cd / && rm -rf "$TMP"
```

Expected printed lines, in order: `planned`, `in-progress`, `add-csv-export`,
`verified`, `done`.
