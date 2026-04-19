#!/usr/bin/env bash
# test-hook-pre-bash.sh — tests for the PreToolUse Bash hook.
# Covers both (a) destructive git ops and (b) write-redirection scope gate.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/hook-pre-bash.sh"

PASS=0
FAIL=0

assert_exit() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "  PASS: $label"
    PASS=$(( PASS + 1 ))
  else
    echo "  FAIL: $label — expected exit $expected, got $actual"
    FAIL=$(( FAIL + 1 ))
  fi
}

TMPDIR_TEST="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_TEST"' EXIT

# Isolate from user's global git config so signing/hooks don't bleed in.
export HOME="$TMPDIR_TEST"
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_NOSYSTEM=1

# Helper: run hook with a given command and repo
run_hook() {
  local cmd="$1" repo="${2:-$PWD}"
  set +e
  printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$cmd" \
    | CLAUDE_PROJECT_DIR="$repo" "$HOOK" >/dev/null 2>&1
  local rc=$?
  set -e
  printf '%s' "$rc"
}

# ── Destructive git ops still blocked (regression) ─────────────────
echo "=== destructive git ops (regression) ==="
rc=$(run_hook "git push --force")
assert_exit "git push --force blocked" "2" "$rc"
rc=$(run_hook "git reset --hard")
assert_exit "git reset --hard blocked" "2" "$rc"
rc=$(run_hook "git clean -fd")
assert_exit "git clean -f blocked" "2" "$rc"

# ── Benign commands allowed ────────────────────────────────────────
echo "=== benign commands allowed ==="
rc=$(run_hook "ls -la")
assert_exit "ls allowed" "0" "$rc"
rc=$(run_hook "echo hello")
assert_exit "echo allowed" "0" "$rc"
rc=$(run_hook "git status")
assert_exit "git status allowed" "0" "$rc"

# ── Fixture repo with an active feature ────────────────────────────
REPO="$TMPDIR_TEST/repo"
mkdir -p "$REPO/.planning/features/auth"
git -C "$REPO" init -q -b main
git -C "$REPO" config user.email "t@t.t"
git -C "$REPO" config user.name "t"

cat > "$REPO/.planning/features/auth/feature.md" <<'FEATURE'
---
branch: feature/auth
---

## Plan
1. [ ] Add login module
  - files: src/login.ts, src/login.test.ts
  - test: none
FEATURE

echo "seed" > "$REPO/seed.txt"
git -C "$REPO" add .planning seed.txt
git -C "$REPO" commit -q -m "seed"
git -C "$REPO" checkout -q -b feature/auth

# ── Write-redirection: in-scope allowed ────────────────────────────
echo "=== redirect to in-scope path allowed ==="
rc=$(run_hook "echo foo > src/login.ts" "$REPO")
assert_exit "> redirect to in-scope file allowed" "0" "$rc"

rc=$(run_hook "echo bar >> src/login.test.ts" "$REPO")
assert_exit ">> redirect to in-scope file allowed" "0" "$rc"

# ── Write-redirection: out-of-scope blocked ────────────────────────
echo "=== redirect to out-of-scope path blocked ==="
rc=$(run_hook "echo foo > src/hijack.ts" "$REPO")
assert_exit "> redirect to out-of-scope blocked" "2" "$rc"

rc=$(run_hook "echo foo >> src/other.ts" "$REPO")
assert_exit ">> redirect to out-of-scope blocked" "2" "$rc"

# ── .planning writes always allowed ────────────────────────────────
echo "=== .planning writes allowed ==="
rc=$(run_hook "echo x > .planning/features/auth/notes.md" "$REPO")
assert_exit "redirect to .planning allowed" "0" "$rc"

# ── sed -i blocked out-of-scope ────────────────────────────────────
echo "=== sed -i gate ==="
rc=$(run_hook "sed -i '' 's/a/b/' src/hijack.ts" "$REPO")
assert_exit "sed -i on out-of-scope blocked" "2" "$rc"

rc=$(run_hook "sed -i '' 's/a/b/' src/login.ts" "$REPO")
assert_exit "sed -i on in-scope allowed" "0" "$rc"

# ── tee blocked out-of-scope ───────────────────────────────────────
echo "=== tee gate ==="
rc=$(run_hook "echo x | tee src/hijack.ts" "$REPO")
assert_exit "tee to out-of-scope blocked" "2" "$rc"

rc=$(run_hook "echo x | tee src/login.ts" "$REPO")
assert_exit "tee to in-scope allowed" "0" "$rc"

# ── cp / mv destination check ──────────────────────────────────────
echo "=== cp/mv gate ==="
rc=$(run_hook "cp /tmp/a.txt src/hijack.ts" "$REPO")
assert_exit "cp to out-of-scope blocked" "2" "$rc"

rc=$(run_hook "mv /tmp/a.txt src/login.ts" "$REPO")
assert_exit "mv to in-scope allowed" "0" "$rc"

# ── git checkout -- path bypass ───────────────────────────────────
echo "=== git checkout -- path gate ==="
rc=$(run_hook "git checkout HEAD -- src/hijack.ts" "$REPO")
assert_exit "git checkout -- out-of-scope blocked" "2" "$rc"

rc=$(run_hook "git checkout HEAD -- src/login.ts" "$REPO")
assert_exit "git checkout -- in-scope allowed" "0" "$rc"

# ── On main (no active feature) → redirects allowed ───────────────
echo "=== no active feature: redirects pass through ==="
git -C "$REPO" checkout -q main
rc=$(run_hook "echo x > anywhere.txt" "$REPO")
assert_exit "redirect on main allowed" "0" "$rc"

# ── YOLO_BYPASS=1 allows out-of-scope ─────────────────────────────
git -C "$REPO" checkout -q feature/auth
echo "=== YOLO_BYPASS=1 allows out-of-scope ==="
set +e
printf '{"tool_name":"Bash","tool_input":{"command":"echo x > src/hijack.ts"}}' \
  | CLAUDE_PROJECT_DIR="$REPO" YOLO_BYPASS=1 "$HOOK" >/dev/null 2>&1
rc=$?
set -e
assert_exit "bypass lifts redirect gate" "0" "$rc"

# ── /tmp paths are always allowed ─────────────────────────────────
echo "=== /tmp paths always allowed ==="
rc=$(run_hook "echo x > /tmp/scratch.txt" "$REPO")
assert_exit "redirect to /tmp allowed" "0" "$rc"

# ── Chained commands with && ──────────────────────────────────────
echo "=== chained commands: && with out-of-scope target blocks ==="
rc=$(run_hook "echo a > src/login.ts && echo b > src/hijack.ts" "$REPO")
assert_exit "chained: in-scope then out-of-scope blocks on out-of-scope" "2" "$rc"

rc=$(run_hook "echo a > src/login.ts && echo b > src/login.test.ts" "$REPO")
# src/login.test.ts isn't in the plan scope currently — test-commit.sh is the only test file in plan
# Actually login.test.ts IS in plan (added earlier in this file). Let me check — plan lists src/login.ts only.
# So this should block. But we want to test that BOTH targets are checked.
rc=$(run_hook "echo a > src/login.ts && echo b > src/login.ts" "$REPO")
assert_exit "chained: both in-scope allowed" "0" "$rc"

# ── Block message mentions the command and feature ────────────────
echo "=== block message content ==="
set +e
stderr_out=$(printf '{"tool_name":"Bash","tool_input":{"command":"echo x > src/hijack.ts"}}' \
  | CLAUDE_PROJECT_DIR="$REPO" "$HOOK" 2>&1 >/dev/null)
rc=$?
set -e
assert_exit "block exits 2" "2" "$rc"
if [[ "$stderr_out" == *"src/hijack.ts"* && "$stderr_out" == *"'auth'"* ]]; then
  echo "  PASS: stderr names target and feature"
  PASS=$(( PASS + 1 ))
else
  echo "  FAIL: stderr missing target+feature context: $stderr_out"
  FAIL=$(( FAIL + 1 ))
fi

# ── Malformed JSON fails closed (regression test for C1 bypass) ────
echo "=== malformed JSON fails closed (exit 2) ==="
set +e
printf '{this is not valid json' \
  | CLAUDE_PROJECT_DIR="$REPO" "$HOOK" >/dev/null 2>&1
rc=$?
set -e
assert_exit "malformed JSON → block (not allow)" "2" "$rc"

# ── Escaped-quote command is seen in full (C1 regression) ──────────
# Prior regex would truncate at the first \" and miss the redirect.
echo "=== escaped-quote command is fully parsed ==="
# Build a JSON payload where the command contains escaped quotes before a redirect
PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"bash -c \"printf \\\"x\\\" > src/hijack.ts\""}}'
set +e
printf '%s' "$PAYLOAD" | CLAUDE_PROJECT_DIR="$REPO" "$HOOK" >/dev/null 2>&1
rc=$?
set -e
assert_exit "escaped-quote redirect to out-of-scope blocked (was C1 bypass)" "2" "$rc"

PAYLOAD_OK='{"tool_name":"Bash","tool_input":{"command":"bash -c \"printf \\\"x\\\" > src/login.ts\""}}'
set +e
printf '%s' "$PAYLOAD_OK" | CLAUDE_PROJECT_DIR="$REPO" "$HOOK" >/dev/null 2>&1
rc=$?
set -e
assert_exit "escaped-quote redirect to in-scope allowed" "0" "$rc"

# ── Feature-file tamper protection ────────────────────────────────
echo "=== feature-file tamper blocked ==="
rc=$(run_hook "rm .planning/features/auth/feature.md" "$REPO")
assert_exit "rm feature.md blocked" "2" "$rc"

rc=$(run_hook "mv .planning/features/auth/feature.md /tmp/stash" "$REPO")
assert_exit "mv feature.md blocked" "2" "$rc"

# Non-feature plan file allowed (only feature.md is guarded)
rc=$(run_hook "rm .planning/decisions/note.md" "$REPO")
assert_exit "rm decisions file allowed" "0" "$rc"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
if (( FAIL > 0 )); then
  exit 1
fi
