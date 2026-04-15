#!/usr/bin/env bash
# test-hook-pre-write.sh — tests for hook-pre-write.sh PreToolUse gate.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/hook-pre-write.sh"

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

# ── Fixture: repo with a feature and plan ──────────────────────────
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

2. [ ] Wire login into app
  - files: src/app.ts
  - test: none
FEATURE

echo "seed" > "$REPO/seed.txt"
git -C "$REPO" add .planning seed.txt
git -C "$REPO" commit -q -m "seed + feature"

# Helper: call hook with a tool call JSON and capture exit code.
# The env var must be set on the hook (the piped-into command), not on printf.
call_hook() {
  local tool="$1" path="$2" repo="$3"
  set +e
  printf '{"tool_name":"%s","tool_input":{"file_path":"%s"}}' "$tool" "$path" \
    | CLAUDE_PROJECT_DIR="$repo" "$HOOK" >/dev/null 2>&1
  local rc=$?
  set -e
  printf '%s' "$rc"
}

# ── No active feature (on main) → allow everything ─────────────────
echo "=== on main: gate passes through ==="
rc=$(call_hook "Edit" "src/any-file.ts" "$REPO")
assert_exit "Edit on main allowed (no active feature)" "0" "$rc"

rc=$(call_hook "Write" "/tmp/outside/file.ts" "$REPO")
assert_exit "Write on main allowed anywhere" "0" "$rc"

# ── On feature branch with matching plan ──────────────────────────
git -C "$REPO" checkout -q -b feature/auth

echo "=== on feature/auth: in-scope paths allowed ==="
rc=$(call_hook "Edit" "src/login.ts" "$REPO")
assert_exit "in-scope src/login.ts allowed" "0" "$rc"

rc=$(call_hook "Write" "src/login.test.ts" "$REPO")
assert_exit "in-scope src/login.test.ts allowed" "0" "$rc"

rc=$(call_hook "Edit" "src/app.ts" "$REPO")
assert_exit "in-scope src/app.ts allowed" "0" "$rc"

echo "=== on feature/auth: .planning edits always allowed ==="
rc=$(call_hook "Edit" ".planning/features/auth/feature.md" "$REPO")
assert_exit ".planning/ path allowed" "0" "$rc"

rc=$(call_hook "Write" ".planning/decisions/2026-04-15-login.md" "$REPO")
assert_exit ".planning/decisions allowed" "0" "$rc"

echo "=== on feature/auth: out-of-scope paths blocked ==="
rc=$(call_hook "Edit" "src/unrelated.ts" "$REPO")
assert_exit "out-of-scope src/unrelated.ts blocked (exit 2)" "2" "$rc"

rc=$(call_hook "Write" "src/deep/other.ts" "$REPO")
assert_exit "out-of-scope nested path blocked" "2" "$rc"

# ── YOLO_BYPASS=1 lifts the gate ──────────────────────────────────
echo "=== YOLO_BYPASS=1 lifts the gate ==="
set +e
YOLO_BYPASS=1 printf '{"tool_name":"Edit","tool_input":{"file_path":"src/unrelated.ts"}}' \
  | CLAUDE_PROJECT_DIR="$REPO" YOLO_BYPASS=1 "$HOOK" >/dev/null 2>&1
rc=$?
set -e
assert_exit "YOLO_BYPASS=1 permits out-of-scope edit" "0" "$rc"

# ── NotebookEdit uses notebook_path field ─────────────────────────
echo "=== NotebookEdit with notebook_path ==="
set +e
printf '{"tool_name":"NotebookEdit","tool_input":{"notebook_path":"src/login.ts"}}' \
  | CLAUDE_PROJECT_DIR="$REPO" "$HOOK" >/dev/null 2>&1
rc=$?
set -e
assert_exit "NotebookEdit in-scope allowed" "0" "$rc"

set +e
printf '{"tool_name":"NotebookEdit","tool_input":{"notebook_path":"src/other.ts"}}' \
  | CLAUDE_PROJECT_DIR="$REPO" "$HOOK" >/dev/null 2>&1
rc=$?
set -e
assert_exit "NotebookEdit out-of-scope blocked" "2" "$rc"

# ── Missing feature file → allow (graceful) ───────────────────────
echo "=== active branch but no feature file → allow ==="
git -C "$REPO" checkout -q -b feature/no-plan
rc=$(call_hook "Edit" "src/whatever.ts" "$REPO")
assert_exit "no feature file → allowed (graceful)" "0" "$rc"

# ── Unparseable input → allow (fail-safe) ─────────────────────────
echo "=== unparseable JSON → allow (fail-safe) ==="
set +e
printf '{}' | CLAUDE_PROJECT_DIR="$REPO" "$HOOK" >/dev/null 2>&1
rc=$?
set -e
assert_exit "empty JSON body → allowed (no target to check)" "0" "$rc"

# ── Malformed JSON fails closed ────────────────────────────────────
echo "=== malformed JSON fails closed (exit 2) ==="
set +e
printf '{not valid json' | CLAUDE_PROJECT_DIR="$REPO" "$HOOK" >/dev/null 2>&1
rc=$?
set -e
assert_exit "malformed JSON → block" "2" "$rc"

# ── file_path with embedded escaped quote survives parsing ─────────
echo "=== escaped-quote in file_path parsed correctly ==="
# JSON: {"tool_name":"Edit","tool_input":{"file_path":"src/\"quoted\".ts"}}
# That path is not in scope; should block.
set +e
printf '{"tool_name":"Edit","tool_input":{"file_path":"src/\"quoted\".ts"}}' \
  | CLAUDE_PROJECT_DIR="$REPO" "$HOOK" >/dev/null 2>&1
rc=$?
set -e
assert_exit "escaped-quote path out-of-scope blocked" "2" "$rc"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
if (( FAIL > 0 )); then
  exit 1
fi
