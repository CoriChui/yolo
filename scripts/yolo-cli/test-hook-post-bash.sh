#!/usr/bin/env bash
# test-hook-post-bash.sh — tests for the PostToolUse Bash diff enforcement.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/hook-post-bash.sh"

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

assert_file_absent() {
  local label="$1" path="$2"
  if [[ ! -e "$path" ]]; then
    echo "  PASS: $label (file absent)"
    PASS=$(( PASS + 1 ))
  else
    echo "  FAIL: $label — file still present at $path"
    FAIL=$(( FAIL + 1 ))
  fi
}

assert_file_content_eq() {
  local label="$1" path="$2" expected="$3"
  local actual
  actual="$(cat "$path" 2>/dev/null || true)"
  if [[ "$expected" == "$actual" ]]; then
    echo "  PASS: $label"
    PASS=$(( PASS + 1 ))
  else
    echo "  FAIL: $label — expected '$expected', got '$actual'"
    FAIL=$(( FAIL + 1 ))
  fi
}

TMPDIR_TEST="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_TEST"' EXIT

# ── Fixture: repo + feature + feature branch ──────────────────────
REPO="$TMPDIR_TEST/repo"
mkdir -p "$REPO/.planning/features/auth" "$REPO/src"
git -C "$REPO" init -q -b main
git -C "$REPO" config user.email "t@t.t"
git -C "$REPO" config user.name "t"

cat > "$REPO/.planning/features/auth/feature.md" <<'FEATURE'
---
branch: feature/auth
---

## Plan
1. [ ] Add login module
  - files: src/login.ts
  - test: none
FEATURE

echo "original" > "$REPO/src/login.ts"
echo "original" > "$REPO/src/other.ts"
git -C "$REPO" add .planning src
git -C "$REPO" commit -q -m "seed"
git -C "$REPO" checkout -q -b feature/auth

run_hook() {
  set +e
  printf '{"tool_name":"Bash","tool_input":{"command":"some cmd"}}' \
    | CLAUDE_PROJECT_DIR="$REPO" "$HOOK" >/dev/null 2>&1
  local rc=$?
  set -e
  printf '%s' "$rc"
}

# ── No changes → exit 0 ────────────────────────────────────────────
echo "=== clean worktree ==="
rc=$(run_hook)
assert_exit "clean worktree exits 0" "0" "$rc"

# ── In-scope modification preserved ───────────────────────────────
echo "=== in-scope modification preserved ==="
echo "updated" > "$REPO/src/login.ts"
rc=$(run_hook)
assert_exit "in-scope modification exits 0" "0" "$rc"
assert_file_content_eq "in-scope file content preserved" "$REPO/src/login.ts" "updated"

# Clean up
git -C "$REPO" checkout -q -- .

# ── Out-of-scope modification reverted ─────────────────────────────
echo "=== out-of-scope modification reverted ==="
echo "hijack" > "$REPO/src/other.ts"
rc=$(run_hook)
assert_exit "out-of-scope modification blocks (exit 2)" "2" "$rc"
assert_file_content_eq "out-of-scope file restored to HEAD" "$REPO/src/other.ts" "original"

# ── Out-of-scope new file removed ─────────────────────────────────
echo "=== out-of-scope new file removed ==="
echo "hijack" > "$REPO/src/hijack.ts"
rc=$(run_hook)
assert_exit "out-of-scope new file blocks (exit 2)" "2" "$rc"
assert_file_absent "out-of-scope new file removed" "$REPO/src/hijack.ts"

# ── Out-of-scope deletion restored ────────────────────────────────
echo "=== out-of-scope deletion restored ==="
rm "$REPO/src/other.ts"
rc=$(run_hook)
assert_exit "out-of-scope deletion blocks (exit 2)" "2" "$rc"
assert_file_content_eq "out-of-scope deleted file restored" "$REPO/src/other.ts" "original"

# ── Mixed: in-scope + out-of-scope changes ────────────────────────
echo "=== mixed in-scope + out-of-scope ==="
echo "legit-update" > "$REPO/src/login.ts"
echo "hijack" > "$REPO/src/other.ts"
rc=$(run_hook)
assert_exit "mixed changes block (exit 2)" "2" "$rc"
assert_file_content_eq "in-scope change preserved" "$REPO/src/login.ts" "legit-update"
assert_file_content_eq "out-of-scope change reverted" "$REPO/src/other.ts" "original"

# ── .planning edits always preserved ──────────────────────────────
git -C "$REPO" checkout -q -- .
echo "=== .planning/ edits preserved ==="
mkdir -p "$REPO/.planning/decisions"
echo "decision" > "$REPO/.planning/decisions/note.md"
rc=$(run_hook)
assert_exit ".planning edits not reverted" "0" "$rc"
if [[ -f "$REPO/.planning/decisions/note.md" ]]; then
  echo "  PASS: .planning file preserved"
  PASS=$(( PASS + 1 ))
else
  echo "  FAIL: .planning file was reverted"
  FAIL=$(( FAIL + 1 ))
fi

# ── No active feature (on main) → exit 0 ──────────────────────────
echo "=== on main: no enforcement ==="
git -C "$REPO" checkout -q main
echo "anything" > "$REPO/anywhere.txt"
rc=$(run_hook)
assert_exit "no active feature exits 0" "0" "$rc"
rm -f "$REPO/anywhere.txt"

# ── YOLO_BYPASS=1 skips enforcement ───────────────────────────────
git -C "$REPO" checkout -q feature/auth
echo "=== YOLO_BYPASS=1 skips enforcement ==="
echo "hijack" > "$REPO/src/other.ts"
set +e
printf '{"tool_name":"Bash","tool_input":{"command":"cmd"}}' \
  | CLAUDE_PROJECT_DIR="$REPO" YOLO_BYPASS=1 "$HOOK" >/dev/null 2>&1
rc=$?
set -e
assert_exit "bypass returns 0 without reverting" "0" "$rc"
assert_file_content_eq "bypass preserved out-of-scope change" "$REPO/src/other.ts" "hijack"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
if (( FAIL > 0 )); then
  exit 1
fi
