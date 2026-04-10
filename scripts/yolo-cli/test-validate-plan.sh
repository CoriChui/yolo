#!/usr/bin/env bash
# test-validate-plan.sh — tests for scripts/yolo-cli/validate-plan.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALIDATE_SH="$SCRIPT_DIR/validate-plan.sh"

PASS=0
FAIL=0

assert_exit_code() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "  PASS: $label"
    PASS=$(( PASS + 1 ))
  else
    echo "  FAIL: $label"
    echo "    expected exit code: $expected"
    echo "    actual exit code:   $actual"
    FAIL=$(( FAIL + 1 ))
  fi
}

assert_contains() {
  local label="$1" needle="$2" haystack="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    echo "  PASS: $label"
    PASS=$(( PASS + 1 ))
  else
    echo "  FAIL: $label"
    echo "    expected to contain: '$needle'"
    echo "    actual:              '$haystack'"
    FAIL=$(( FAIL + 1 ))
  fi
}

# ── Temp workspace ────────────────────────────────────────────────────
TMPDIR_TEST="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_TEST"' EXIT

# ── Test 1: Valid 3-task plan passes (1 test:none is OK since <50%) ───
echo "=== valid 3-task plan passes ==="

VALID_FILE="$TMPDIR_TEST/valid-3.yaml"
cat > "$VALID_FILE" <<'EOF'
---
slug: valid-feature
title: A valid feature with three tasks
status: planned
---
## Criteria
- Must work correctly

## Plan
1. [ ] Implement the authentication module with proper error handling and token refresh logic for all user sessions (test: pnpm test -- auth)
2. [ ] Add the user profile page with avatar upload and comprehensive form validation for all required input fields (test: none — trivial UI)
3. [ ] Write integration tests for the complete login flow covering success failure timeout and all edge cases thoroughly (test: pnpm test -- integration)

## Verification
- Run all tests
EOF

set +e
output=$("$VALIDATE_SH" "$VALID_FILE" 2>&1)
rc=$?
set -e
assert_exit_code "valid 3-task plan exits 0" "0" "$rc"

# ── Test 2: >50% test:none rejected ──────────────────────────────────
echo "=== >50% test:none rejected ==="

TESTNONE_FILE="$TMPDIR_TEST/too-many-testnone.yaml"
cat > "$TESTNONE_FILE" <<'EOF'
---
slug: testnone-feature
title: Feature with too many test none tasks
status: planned
---
## Criteria
- Something

## Plan
1. [ ] Implement the authentication module with proper error handling and token refresh logic for all user sessions (test: none — trivial)
2. [ ] Add the user profile page with avatar upload and comprehensive form validation for all required input fields (test: none — simple)
3. [ ] Write integration tests for the complete login flow covering success failure timeout and all edge cases thoroughly (test: pnpm test -- integration)
EOF

set +e
output=$("$VALIDATE_SH" "$TESTNONE_FILE" 2>&1)
rc=$?
set -e
assert_exit_code ">50% test:none rejected" "1" "$rc"
assert_contains "mentions test:none ratio" "test: none" "$output"

# ── Test 3: Short description rejected (<20 words) ───────────────────
echo "=== short description rejected ==="

SHORT_FILE="$TMPDIR_TEST/short-desc.yaml"
cat > "$SHORT_FILE" <<'EOF'
---
slug: short-desc
title: Feature with short description
status: planned
---
## Criteria
- Something

## Plan
1. [ ] Implement the authentication module with proper error handling and token refresh logic for all user sessions (test: pnpm test)
2. [ ] Fix bug (test: pnpm test)
3. [ ] Write integration tests for the complete login flow covering success failure timeout and all edge cases thoroughly (test: pnpm test)
EOF

set +e
output=$("$VALIDATE_SH" "$SHORT_FILE" 2>&1)
rc=$?
set -e
assert_exit_code "short description rejected" "1" "$rc"
assert_contains "mentions word count" "words" "$output"

# ── Test 4: >12 tasks rejected ───────────────────────────────────────
echo "=== >12 tasks rejected ==="

BIG_FILE="$TMPDIR_TEST/too-many-tasks.yaml"
cat > "$BIG_FILE" <<'EOF'
---
slug: big-feature
title: Feature with too many tasks
status: planned
---
## Plan
1. [ ] Implement the first module with proper error handling and token refresh logic and validation for all cases (test: pnpm test)
2. [ ] Implement the second module with proper error handling and token refresh logic and validation for all cases (test: pnpm test)
3. [ ] Implement the third module with proper error handling and token refresh logic and validation for all cases (test: pnpm test)
4. [ ] Implement the fourth module with proper error handling and token refresh logic and validation for all cases (test: pnpm test)
5. [ ] Implement the fifth module with proper error handling and token refresh logic and validation for all cases (test: pnpm test)
6. [ ] Implement the sixth module with proper error handling and token refresh logic and validation for all cases (test: pnpm test)
7. [ ] Implement the seventh module with proper error handling and token refresh logic and validation for all cases (test: pnpm test)
8. [ ] Implement the eighth module with proper error handling and token refresh logic and validation for all cases (test: pnpm test)
9. [ ] Implement the ninth module with proper error handling and token refresh logic and validation for all cases (test: pnpm test)
10. [ ] Implement the tenth module with proper error handling and token refresh logic and validation for all cases (test: pnpm test)
11. [ ] Implement the eleventh module with proper error handling and token refresh logic and validation for all cases (test: pnpm test)
12. [ ] Implement the twelfth module with proper error handling and token refresh logic and validation for all cases (test: pnpm test)
13. [ ] Implement the thirteenth module with proper error handling and token refresh logic and validation for all cases (test: pnpm test)
EOF

set +e
output=$("$VALIDATE_SH" "$BIG_FILE" 2>&1)
rc=$?
set -e
assert_exit_code ">12 tasks rejected" "1" "$rc"
assert_contains "mentions split" "split" "$output"

# ── Test 5: Empty plan (no ## Plan section) rejected ─────────────────
echo "=== empty plan rejected ==="

EMPTY_FILE="$TMPDIR_TEST/no-plan.yaml"
cat > "$EMPTY_FILE" <<'EOF'
---
slug: empty-feature
title: Feature with no plan
status: planned
---
## Criteria
- Something
EOF

set +e
output=$("$VALIDATE_SH" "$EMPTY_FILE" 2>&1)
rc=$?
set -e
assert_exit_code "empty plan rejected" "1" "$rc"
assert_contains "mentions plan section" "Plan" "$output"

# ── Test 6: Valid 12-task plan passes (boundary case) ─────────────────
echo "=== valid 12-task plan passes (boundary) ==="

BOUNDARY_FILE="$TMPDIR_TEST/boundary-12.yaml"
cat > "$BOUNDARY_FILE" <<'EOF'
---
slug: boundary-feature
title: Feature with exactly twelve tasks at the boundary limit
status: planned
---
## Plan
1. [ ] Implement the first module with proper error handling and token refresh logic and validation for all cases (test: pnpm test)
2. [ ] Implement the second module with proper error handling and token refresh logic and validation for all cases (test: pnpm test)
3. [ ] Implement the third module with proper error handling and token refresh logic and validation for all cases (test: pnpm test)
4. [ ] Implement the fourth module with proper error handling and token refresh logic and validation for all cases (test: pnpm test)
5. [ ] Implement the fifth module with proper error handling and token refresh logic and validation for all cases (test: none — trivial)
6. [ ] Implement the sixth module with proper error handling and token refresh logic and validation for all cases (test: pnpm test)
7. [ ] Implement the seventh module with proper error handling and token refresh logic and validation for all cases (test: pnpm test)
8. [ ] Implement the eighth module with proper error handling and token refresh logic and validation for all cases (test: pnpm test)
9. [ ] Implement the ninth module with proper error handling and token refresh logic and validation for all cases (test: none — trivial)
10. [ ] Implement the tenth module with proper error handling and token refresh logic and validation for all cases (test: pnpm test)
11. [ ] Implement the eleventh module with proper error handling and token refresh logic and validation for all cases (test: pnpm test)
12. [ ] Implement the twelfth module with proper error handling and token refresh logic and validation for all cases (test: pnpm test)
EOF

set +e
output=$("$VALIDATE_SH" "$BOUNDARY_FILE" 2>&1)
rc=$?
set -e
assert_exit_code "valid 12-task plan exits 0" "0" "$rc"

# ── Summary ───────────────────────────────────────────────────────────
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="

if (( FAIL > 0 )); then
  exit 1
fi
