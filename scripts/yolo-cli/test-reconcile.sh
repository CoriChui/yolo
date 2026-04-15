#!/usr/bin/env bash
#
# test-reconcile.sh — End-to-end test for reconcile.sh
#
# Creates a git repo in /tmp/yolo-spike-test with known state,
# runs reconciliation, and verifies correctness.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RECONCILE="$SCRIPT_DIR/reconcile.sh"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT
PASS=0
FAIL=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

assert_contains() {
  local label="$1"
  local haystack="$2"
  local needle="$3"
  if echo "$haystack" | grep -qF "$needle"; then
    echo -e "  ${GREEN}PASS${NC}: $label"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC}: $label"
    echo "    Expected to find: $needle"
    echo "    In output:"
    echo "$haystack" | head -5 | sed 's/^/    /'
    FAIL=$((FAIL + 1))
  fi
}

assert_not_contains() {
  local label="$1"
  local haystack="$2"
  local needle="$3"
  if ! echo "$haystack" | grep -qF "$needle"; then
    echo -e "  ${GREEN}PASS${NC}: $label"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC}: $label"
    echo "    Expected NOT to find: $needle"
    FAIL=$((FAIL + 1))
  fi
}

assert_file_contains() {
  local label="$1"
  local file="$2"
  local needle="$3"
  if grep -qF "$needle" "$file"; then
    echo -e "  ${GREEN}PASS${NC}: $label"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC}: $label"
    echo "    Expected file to contain: $needle"
    FAIL=$((FAIL + 1))
  fi
}

assert_file_not_contains() {
  local label="$1"
  local file="$2"
  local needle="$3"
  if ! grep -qF "$needle" "$file"; then
    echo -e "  ${GREEN}PASS${NC}: $label"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC}: $label"
    echo "    Expected file NOT to contain: $needle"
    FAIL=$((FAIL + 1))
  fi
}

# ============================================================
# Setup: create test git repo
# ============================================================
echo -e "${YELLOW}=== Setting up test repo at $TEST_DIR ===${NC}"
mkdir -p "$TEST_DIR"
cd "$TEST_DIR"

git init -b main
git config user.email "test@test.com"
git config user.name "Test"

# Initial commit on main
echo "# Test Project" > README.md
mkdir -p .planning/features
git add -A
git commit -m "Initial commit"

# Create feature branch
git checkout -b feature/dark-mode

# Make task-1 commit
echo "/* task 1: design tokens */" > tokens.css
git add tokens.css
git commit -m "[task-1] Create design tokens as CSS custom properties"

# Make task-2 commit
echo "// task 2: theme context" > ThemeContext.js
git add ThemeContext.js
git commit -m "[task-2] Add ThemeContext and toggle component"

# Make task-3 commit
echo "/* task 3: replace colors */" > colors.css
git add colors.css
git commit -m "[task-3] Replace hardcoded Tailwind colors with var() references"

# task-4 is NOT committed (in progress)

# Capture commit hashes
HASH1=$(git log --oneline --grep='\[task-1\]' --format='%h')
HASH2=$(git log --oneline --grep='\[task-2\]' --format='%h')
HASH3=$(git log --oneline --grep='\[task-3\]' --format='%h')

echo "  Commits created:"
echo "    task-1: $HASH1"
echo "    task-2: $HASH2"
echo "    task-3: $HASH3"
echo "    task-4: (not committed)"

# ============================================================
# Test 1: Detect drift — wrong checkboxes
# ============================================================
echo ""
echo -e "${YELLOW}=== Test 1: Detect drift (intentionally wrong checkboxes) ===${NC}"

# Create feature file with INTENTIONALLY WRONG state:
# - task-1: unchecked (WRONG — has commit)
# - task-2: checked with wrong hash (DRIFT)
# - task-3: unchecked (WRONG — has commit)
# - task-4: checked (WRONG — no commit)
cat > "$TEST_DIR/.planning/features/dark-mode.md" << 'FEATURE'
---
goal: Add dark mode support with CSS variables
branch: feature/dark-mode
created: 2026-04-10
---

## Criteria
- [ ] Theme toggle switches between light and dark
- [ ] CSS variables drive all color values

## Context
Existing app uses hardcoded colors in Tailwind classes.

## Plan
1. [ ] Create design tokens as CSS custom properties
2. [x] Add ThemeContext + toggle component — aaaaaaa
3. [ ] Replace hardcoded Tailwind colors with var() references
4. [x] Add localStorage persistence + SSR-safe init script

## Verification
FEATURE

OUTPUT1=$("$RECONCILE" "$TEST_DIR/.planning/features/dark-mode.md" "feature/dark-mode" --repo "$TEST_DIR" 2>&1) || EXIT1=$?
echo "$OUTPUT1"
echo ""

# Assertions
assert_contains "Detects task-1 should be checked" "$OUTPUT1" "task-1 is UNCHECKED in file but has commit"
assert_contains "Detects task-2 hash drift" "$OUTPUT1" "task-2 hash in file"
assert_contains "Detects task-3 should be checked" "$OUTPUT1" "task-3 is UNCHECKED in file but has commit"
assert_contains "Detects task-4 should be unchecked" "$OUTPUT1" "task-4 is CHECKED in file but has NO matching commit"
assert_contains "Current step is do" "$OUTPUT1" "do (3/4 tasks completed)"
assert_contains "Reports drift count" "$OUTPUT1" "Total drift items:"

# ============================================================
# Test 2: Fix mode — update the feature file
# ============================================================
echo ""
echo -e "${YELLOW}=== Test 2: Fix mode ===${NC}"

# Re-create the broken feature file
cat > "$TEST_DIR/.planning/features/dark-mode.md" << 'FEATURE'
---
goal: Add dark mode support with CSS variables
branch: feature/dark-mode
created: 2026-04-10
---

## Criteria
- [ ] Theme toggle switches between light and dark
- [ ] CSS variables drive all color values

## Context
Existing app uses hardcoded colors in Tailwind classes.

## Plan
1. [ ] Create design tokens as CSS custom properties
2. [x] Add ThemeContext + toggle component — aaaaaaa
3. [ ] Replace hardcoded Tailwind colors with var() references
4. [x] Add localStorage persistence + SSR-safe init script

## Verification

## Notes
Some notes here.
FEATURE

OUTPUT2=$("$RECONCILE" "$TEST_DIR/.planning/features/dark-mode.md" "feature/dark-mode" --fix --repo "$TEST_DIR" 2>&1)
echo "$OUTPUT2"
echo ""

# Verify the file was updated correctly
FIXED_FILE="$TEST_DIR/.planning/features/dark-mode.md"
echo "  Fixed file contents (## Plan section):"
sed -n '/^## Plan/,/^## /p' "$FIXED_FILE" | head -10
echo ""

assert_file_contains "task-1 now checked with hash" "$FIXED_FILE" "1. [x] Create design tokens"
assert_file_contains "task-1 has correct hash" "$FIXED_FILE" "$HASH1"
assert_file_contains "task-2 still checked" "$FIXED_FILE" "2. [x] Add ThemeContext"
assert_file_contains "task-2 has correct hash" "$FIXED_FILE" "$HASH2"
assert_file_contains "task-3 now checked with hash" "$FIXED_FILE" "3. [x] Replace hardcoded"
assert_file_contains "task-3 has correct hash" "$FIXED_FILE" "$HASH3"
assert_file_contains "task-4 now unchecked" "$FIXED_FILE" "4. [ ] Add localStorage"
assert_file_not_contains "task-4 has no hash" "$FIXED_FILE" "4. [x]"

# Verify non-plan sections are preserved
assert_file_contains "Criteria preserved" "$FIXED_FILE" "Theme toggle switches"
assert_file_contains "Context preserved" "$FIXED_FILE" "hardcoded colors"
assert_file_contains "Notes preserved" "$FIXED_FILE" "Some notes here."
assert_file_contains "Frontmatter preserved" "$FIXED_FILE" "goal: Add dark mode"

# ============================================================
# Test 3: All tasks complete — derive "check" step
# ============================================================
echo ""
echo -e "${YELLOW}=== Test 3: All tasks complete, no verification -> check step ===${NC}"

# Add task-4 commit
cd "$TEST_DIR"
echo "// task 4: localStorage" > storage.js
git add storage.js
git commit -m "[task-4] Add localStorage persistence and SSR-safe init"

# Create feature file with all tasks (some wrong, doesn't matter — we check step derivation)
cat > "$TEST_DIR/.planning/features/dark-mode.md" << 'FEATURE'
---
goal: Add dark mode support with CSS variables
branch: feature/dark-mode
created: 2026-04-10
---

## Criteria
- [ ] Theme toggle switches between light and dark

## Context
Context.

## Plan
1. [x] Create design tokens as CSS custom properties
2. [x] Add ThemeContext + toggle component
3. [x] Replace hardcoded Tailwind colors with var() references
4. [ ] Add localStorage persistence + SSR-safe init script

## Verification
FEATURE

OUTPUT3=$("$RECONCILE" "$TEST_DIR/.planning/features/dark-mode.md" "feature/dark-mode" --repo "$TEST_DIR" 2>&1) || true
echo "$OUTPUT3"
echo ""

assert_contains "All tasks done, step is check" "$OUTPUT3" "check (all 4 tasks done, needs verification)"

# ============================================================
# Test 4: All tasks complete + verification present -> ship step
# ============================================================
echo ""
echo -e "${YELLOW}=== Test 4: All tasks + verification -> ship step ===${NC}"

cat > "$TEST_DIR/.planning/features/dark-mode.md" << 'FEATURE'
---
goal: Add dark mode support with CSS variables
branch: feature/dark-mode
created: 2026-04-10
---

## Criteria
- [x] Theme toggle switches between light and dark

## Context
Context.

## Plan
1. [x] Create design tokens as CSS custom properties
2. [x] Add ThemeContext + toggle component
3. [x] Replace hardcoded Tailwind colors with var() references
4. [x] Add localStorage persistence + SSR-safe init script

## Verification
passed: true
All criteria verified:
- Theme toggle works: confirmed via manual test output
- CSS variables: all color values use var() references
FEATURE

OUTPUT4=$("$RECONCILE" "$TEST_DIR/.planning/features/dark-mode.md" "feature/dark-mode" --repo "$TEST_DIR" 2>&1)
echo "$OUTPUT4"
echo ""

assert_contains "Step is ship" "$OUTPUT4" "ship (all tasks done, verified)"

# ============================================================
# Test 5: No commits on branch -> plan step
# ============================================================
echo ""
echo -e "${YELLOW}=== Test 5: No commits -> plan step ===${NC}"

cd "$TEST_DIR"
git checkout main
git checkout -b feature/empty-feature

cat > "$TEST_DIR/.planning/features/empty-feature.md" << 'FEATURE'
---
goal: Some new feature
branch: feature/empty-feature
created: 2026-04-10
---

## Criteria
- [ ] Something works

## Context
Context.

## Plan
1. [ ] Do the first thing
2. [ ] Do the second thing
FEATURE

OUTPUT5=$("$RECONCILE" "$TEST_DIR/.planning/features/empty-feature.md" "feature/empty-feature" --repo "$TEST_DIR" 2>&1)
echo "$OUTPUT5"
echo ""

assert_contains "Step is plan" "$OUTPUT5" "plan (plan exists, no tasks started)"
assert_contains "No drift" "$OUTPUT5" "No drift detected"

# ============================================================
# Test 6: Orphan commits (task-N commits not in plan)
# ============================================================
echo ""
echo -e "${YELLOW}=== Test 6: Orphan commits ===${NC}"

cd "$TEST_DIR"
git checkout main
git checkout -b feature/orphan-test

echo "orphan" > orphan.txt
git add orphan.txt
git commit -m "[task-1] First task"

echo "orphan2" > orphan2.txt
git add orphan2.txt
git commit -m "[task-5] This task is not in the plan"

cat > "$TEST_DIR/.planning/features/orphan-test.md" << 'FEATURE'
---
goal: Orphan test
branch: feature/orphan-test
created: 2026-04-10
---

## Criteria
- [ ] Something

## Plan
1. [ ] First task
2. [ ] Second task
FEATURE

OUTPUT6=$("$RECONCILE" "$TEST_DIR/.planning/features/orphan-test.md" "feature/orphan-test" --repo "$TEST_DIR" 2>&1) || true
echo "$OUTPUT6"
echo ""

assert_contains "Detects orphan commit" "$OUTPUT6" "ORPHAN: Commit"
assert_contains "Orphan references task-5" "$OUTPUT6" "task-5 which is not in the plan"

# ============================================================
# Test 7: Idempotency — running fix twice produces same result
# ============================================================
echo ""
echo -e "${YELLOW}=== Test 7: Idempotency ===${NC}"

cd "$TEST_DIR"
git checkout feature/dark-mode

# Create a broken file
cat > "$TEST_DIR/.planning/features/dark-mode.md" << 'FEATURE'
---
goal: Add dark mode support with CSS variables
branch: feature/dark-mode
created: 2026-04-10
---

## Criteria
- [ ] Theme toggle

## Plan
1. [ ] Create design tokens as CSS custom properties
2. [ ] Add ThemeContext + toggle component
3. [ ] Replace hardcoded Tailwind colors with var() references
4. [ ] Add localStorage persistence + SSR-safe init script
FEATURE

# First fix
"$RECONCILE" "$TEST_DIR/.planning/features/dark-mode.md" "feature/dark-mode" --fix --repo "$TEST_DIR" > /dev/null 2>&1
CONTENTS_AFTER_FIRST_FIX=$(cat "$TEST_DIR/.planning/features/dark-mode.md")

# Second fix (should be no-op)
OUTPUT7=$("$RECONCILE" "$TEST_DIR/.planning/features/dark-mode.md" "feature/dark-mode" --fix --repo "$TEST_DIR" 2>&1)
CONTENTS_AFTER_SECOND_FIX=$(cat "$TEST_DIR/.planning/features/dark-mode.md")

if [[ "$CONTENTS_AFTER_FIRST_FIX" == "$CONTENTS_AFTER_SECOND_FIX" ]]; then
  echo -e "  ${GREEN}PASS${NC}: Fix is idempotent"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC}: Fix is NOT idempotent — file changed on second run"
  diff <(echo "$CONTENTS_AFTER_FIRST_FIX") <(echo "$CONTENTS_AFTER_SECOND_FIX") | head -10
  FAIL=$((FAIL + 1))
fi

assert_contains "Second run shows no drift" "$OUTPUT7" "No drift detected"

# ============================================================
# Test 8: Branch auto-detection from frontmatter
# ============================================================
echo ""
echo -e "${YELLOW}=== Test 8: Branch auto-detection from frontmatter ===${NC}"

cd "$TEST_DIR"
git checkout feature/dark-mode

# Run reconcile WITHOUT passing the branch name — should auto-detect from frontmatter
OUTPUT8=$("$RECONCILE" "$TEST_DIR/.planning/features/dark-mode.md" --repo "$TEST_DIR" 2>&1)
echo "$OUTPUT8"
echo ""

assert_contains "Auto-detect finds branch" "$OUTPUT8" "feature/dark-mode"
assert_contains "Auto-detect derives correct step" "$OUTPUT8" "check (all 4 tasks done, needs verification)"

# ============================================================
# Test 9: Performance — measure timing
# ============================================================
echo ""
echo -e "${YELLOW}=== Test 9: Performance ===${NC}"

# Extract elapsed time from the report
ELAPSED=$(echo "$OUTPUT1" | grep "Elapsed:" | awk '{print $2}')
echo "  Reconciliation time: $ELAPSED"
# Just report — no assertion on speed for now

# ============================================================
# Test 10: Error — no arguments
# ============================================================
echo ""
echo -e "${YELLOW}=== Test 10: No arguments -> exit 1 with usage ===${NC}"

OUTPUT10=$("$RECONCILE" 2>&1) || EXIT10=$?

assert_contains "Shows usage message" "$OUTPUT10" "Usage: reconcile.sh"

if [[ "${EXIT10:-0}" -eq 1 ]]; then
  echo -e "  ${GREEN}PASS${NC}: Exits with code 1"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC}: Expected exit code 1, got ${EXIT10:-0}"
  FAIL=$((FAIL + 1))
fi

# ============================================================
# Test 11: Error — file not found
# ============================================================
echo ""
echo -e "${YELLOW}=== Test 11: File not found -> exit 1 ===${NC}"

OUTPUT11=$("$RECONCILE" "/tmp/nonexistent-yolo-feature-file-$$.md" "some-branch" 2>&1) || EXIT11=$?

assert_contains "Shows file not found error" "$OUTPUT11" "Feature file not found"

if [[ "${EXIT11:-0}" -eq 1 ]]; then
  echo -e "  ${GREEN}PASS${NC}: Exits with code 1"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC}: Expected exit code 1, got ${EXIT11:-0}"
  FAIL=$((FAIL + 1))
fi

# ============================================================
# Test 12: Error — no branch specified
# ============================================================
echo ""
echo -e "${YELLOW}=== Test 12: No branch in frontmatter and no branch arg -> exit 1 ===${NC}"

# Create a feature file WITHOUT a branch: field in frontmatter
NO_BRANCH_DIR="$(mktemp -d)"
mkdir -p "$NO_BRANCH_DIR/.planning/features"
cat > "$NO_BRANCH_DIR/.planning/features/no-branch.md" << 'FEATURE'
---
goal: A feature with no branch field
created: 2026-04-10
---

## Criteria
- [ ] Something

## Plan
1. [ ] Do something
FEATURE

OUTPUT12=$("$RECONCILE" "$NO_BRANCH_DIR/.planning/features/no-branch.md" 2>&1) || EXIT12=$?
rm -rf "$NO_BRANCH_DIR"

assert_contains "Shows no branch error" "$OUTPUT12" "No branch specified"

if [[ "${EXIT12:-0}" -eq 1 ]]; then
  echo -e "  ${GREEN}PASS${NC}: Exits with code 1"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC}: Expected exit code 1, got ${EXIT12:-0}"
  FAIL=$((FAIL + 1))
fi

# ============================================================
# Test 13: Verification without explicit passed field -> check step
# ============================================================
echo ""
echo -e "${YELLOW}=== Test 13: Verification content but no passed: field -> check (incomplete) ===${NC}"

cd "$TEST_DIR"
git checkout feature/dark-mode

cat > "$TEST_DIR/.planning/features/dark-mode.md" << 'FEATURE'
---
goal: Add dark mode support with CSS variables
branch: feature/dark-mode
created: 2026-04-10
---

## Criteria
- [x] Theme toggle switches between light and dark

## Context
Context.

## Plan
1. [x] Create design tokens as CSS custom properties
2. [x] Add ThemeContext + toggle component
3. [x] Replace hardcoded Tailwind colors with var() references
4. [x] Add localStorage persistence + SSR-safe init script

## Verification
All criteria reviewed:
- Theme toggle works: confirmed via manual testing
- CSS variables: all colors use var() references
FEATURE

OUTPUT13=$("$RECONCILE" "$TEST_DIR/.planning/features/dark-mode.md" "feature/dark-mode" --repo "$TEST_DIR" 2>&1) || true
echo "$OUTPUT13"
echo ""

assert_contains "Step is check (verification incomplete)" "$OUTPUT13" "check (verification incomplete — no explicit passed: field)"

# ============================================================
# Unsafe-state refusal: rebase / merge / cherry-pick in progress
# ============================================================
echo ""
echo -e "${YELLOW}=== Unsafe-state refusal ===${NC}"

UNSAFE_REPO="$TEST_DIR/unsafe-repo"
mkdir -p "$UNSAFE_REPO/.planning/features/probe"
git -C "$UNSAFE_REPO" init -q -b main
git -C "$UNSAFE_REPO" config user.email "t@t.t"
git -C "$UNSAFE_REPO" config user.name "t"
cat > "$UNSAFE_REPO/.planning/features/probe/feature.md" <<'FEATURE'
---
branch: feature/probe
---

## Plan
1. [ ] something
  - test: none
  - files: a.txt

2. [ ] another
  - test: none
  - files: b.txt
FEATURE
echo seed > "$UNSAFE_REPO/seed.txt"
git -C "$UNSAFE_REPO" add .planning seed.txt
git -C "$UNSAFE_REPO" commit -q -m seed
git -C "$UNSAFE_REPO" checkout -q -b feature/probe

# Simulate a merge-in-progress by creating MERGE_HEAD marker
UNSAFE_GITDIR="$(git -C "$UNSAFE_REPO" rev-parse --git-dir)"
case "$UNSAFE_GITDIR" in
  /*) ;;
  *) UNSAFE_GITDIR="$UNSAFE_REPO/$UNSAFE_GITDIR" ;;
esac
echo "$(git -C "$UNSAFE_REPO" rev-parse HEAD)" > "$UNSAFE_GITDIR/MERGE_HEAD"

set +e
"$RECONCILE" "$UNSAFE_REPO/.planning/features/probe/feature.md" --repo "$UNSAFE_REPO" >/dev/null 2>&1
rc=$?
set -e
if [[ "$rc" == "1" ]]; then
  echo -e "  ${GREEN}PASS${NC}: reconcile refuses during pending merge"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC}: reconcile did not refuse (exit $rc)"
  FAIL=$((FAIL + 1))
fi

# Clean up MERGE_HEAD — confirm reconcile works again
rm "$UNSAFE_GITDIR/MERGE_HEAD"
set +e
"$RECONCILE" "$UNSAFE_REPO/.planning/features/probe/feature.md" --repo "$UNSAFE_REPO" >/dev/null 2>&1
rc=$?
set -e
if [[ "$rc" == "0" || "$rc" == "2" ]]; then
  echo -e "  ${GREEN}PASS${NC}: reconcile runs once merge marker is cleared"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC}: reconcile failed unexpectedly (exit $rc)"
  FAIL=$((FAIL + 1))
fi

# ── --apply is accepted as alias for --fix ────────────────────────
echo ""
echo -e "${YELLOW}=== --apply alias accepted ===${NC}"
set +e
"$RECONCILE" "$UNSAFE_REPO/.planning/features/probe/feature.md" --repo "$UNSAFE_REPO" --apply >/dev/null 2>&1
rc=$?
set -e
if [[ "$rc" == "0" ]]; then
  echo -e "  ${GREEN}PASS${NC}: --apply accepted (exit 0)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}FAIL${NC}: --apply rejected (exit $rc)"
  FAIL=$((FAIL + 1))
fi

# ============================================================
# Summary
# ============================================================
echo ""
echo "========================================"
echo -e "  Results: ${GREEN}${PASS} passed${NC}, ${RED}${FAIL} failed${NC}"
echo "========================================"

if [[ $FAIL -gt 0 ]]; then
  exit 1
else
  echo -e "  ${GREEN}All tests passed!${NC}"
  exit 0
fi
