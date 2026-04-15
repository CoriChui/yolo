#!/usr/bin/env bash
# test-hook-post-bash.sh — tests for the snapshot-based PostToolUse Bash hook.
# Verifies: (a) only delta changes are acted on, not pre-existing dirty state;
# (b) report-only by default, no destructive mutations;
# (c) YOLO_POST_BASH_REVERT=1 enables opt-in revert.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRE_HOOK="$SCRIPT_DIR/hook-pre-bash.sh"
POST_HOOK="$SCRIPT_DIR/hook-post-bash.sh"

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

assert_file_present() {
  local label="$1" path="$2"
  if [[ -e "$path" ]]; then
    echo "  PASS: $label (present)"
    PASS=$(( PASS + 1 ))
  else
    echo "  FAIL: $label — file missing"
    FAIL=$(( FAIL + 1 ))
  fi
}

assert_file_absent() {
  local label="$1" path="$2"
  if [[ ! -e "$path" ]]; then
    echo "  PASS: $label (absent)"
    PASS=$(( PASS + 1 ))
  else
    echo "  FAIL: $label — file still present"
    FAIL=$(( FAIL + 1 ))
  fi
}

TMPDIR_TEST="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_TEST" /tmp/yolo-snap-$$.txt' EXIT

# ── Fixture ────────────────────────────────────────────────────────
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

# The hook uses PPID of the hook subprocess as the snapshot key. When we
# invoke via the test shell, PPID is our $$ (the test process).
SNAP_PPID="$$"
export SNAP_FILE="/tmp/yolo-snap-${SNAP_PPID}.txt"
# Clean any stale snapshot
rm -f "$SNAP_FILE"

# Helper: run pre-hook to snapshot, then run the simulated command (via the
# shell — not a Bash tool call), then run post-hook and capture its exit.
simulate_bash_call() {
  local cmd_script="$1"
  # Pre-hook snapshot
  set +e
  printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$cmd_script" \
    | CLAUDE_PROJECT_DIR="$REPO" "$PRE_HOOK" >/dev/null 2>&1
  set -e
  # Run the simulated command in the repo (but only its effect on files)
  eval "$cmd_script"
  # Post-hook check
  set +e
  printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$cmd_script" \
    | CLAUDE_PROJECT_DIR="$REPO" "$POST_HOOK" >/dev/null 2>&1
  local rc=$?
  set -e
  printf '%s' "$rc"
}

# ── Pre-existing dirty state is IGNORED (the bug fix) ──────────────
echo "=== pre-existing dirty state ignored ==="
# Seed the worktree with pre-existing dirty state BEFORE taking a snapshot
echo "pre-existing-dirty" > "$REPO/src/other.ts"
# Now run pre+post with a NO-OP command
rc=$(simulate_bash_call "true")
assert_exit "no-op command + pre-existing dirt → exit 0" "0" "$rc"
assert_file_content_eq "pre-existing dirty file NOT reverted" "$REPO/src/other.ts" "pre-existing-dirty"

# ── Out-of-scope change produced BY the command is reported ────────
echo "=== out-of-scope delta reported (no revert by default) ==="
# Reset to clean baseline for this scenario
git -C "$REPO" checkout -q -- .
rc=$(simulate_bash_call "echo produced > $REPO/src/hijack.ts")
assert_exit "out-of-scope delta reports (exit 2)" "2" "$rc"
assert_file_present "file NOT reverted (report-only default)" "$REPO/src/hijack.ts"
rm -f "$REPO/src/hijack.ts"

# ── In-scope change produced BY the command passes through ─────────
echo "=== in-scope delta allowed ==="
git -C "$REPO" checkout -q -- .
rc=$(simulate_bash_call "echo updated > $REPO/src/login.ts")
assert_exit "in-scope delta passes (exit 0)" "0" "$rc"
assert_file_content_eq "in-scope content preserved" "$REPO/src/login.ts" "updated"
git -C "$REPO" checkout -q -- .

# ── YOLO_POST_BASH_REVERT=1 performs the revert ───────────────────
echo "=== opt-in revert via YOLO_POST_BASH_REVERT=1 ==="
rm -f "$SNAP_FILE"
# Pre-hook snapshot
printf '{"tool_name":"Bash","tool_input":{"command":"echo x > f"}}' \
  | CLAUDE_PROJECT_DIR="$REPO" "$PRE_HOOK" >/dev/null 2>&1 || true
# Produce an out-of-scope change
echo "hijack" > "$REPO/src/other.ts"
# Post-hook with revert enabled
set +e
printf '{"tool_name":"Bash","tool_input":{"command":"echo x > f"}}' \
  | CLAUDE_PROJECT_DIR="$REPO" YOLO_POST_BASH_REVERT=1 "$POST_HOOK" >/dev/null 2>&1
rc=$?
set -e
assert_exit "revert-mode exits 2" "2" "$rc"
assert_file_content_eq "out-of-scope file reverted when opt-in" "$REPO/src/other.ts" "original"

# ── YOLO_BYPASS=1 skips everything ────────────────────────────────
echo "=== YOLO_BYPASS=1 skips enforcement ==="
rm -f "$SNAP_FILE"
printf '{"tool_name":"Bash","tool_input":{"command":"echo x > f"}}' \
  | CLAUDE_PROJECT_DIR="$REPO" "$PRE_HOOK" >/dev/null 2>&1 || true
echo "still-hijack" > "$REPO/src/other.ts"
set +e
printf '{"tool_name":"Bash","tool_input":{"command":"cmd"}}' \
  | CLAUDE_PROJECT_DIR="$REPO" YOLO_BYPASS=1 "$POST_HOOK" >/dev/null 2>&1
rc=$?
set -e
assert_exit "bypass returns 0" "0" "$rc"
assert_file_content_eq "bypass leaves file alone" "$REPO/src/other.ts" "still-hijack"
git -C "$REPO" checkout -q -- .

# ── No snapshot file → skip (fail-safe) ──────────────────────────
echo "=== missing snapshot → skip (no revert) ==="
rm -f "$SNAP_FILE"
echo "hijack-no-snap" > "$REPO/src/other.ts"
set +e
printf '{"tool_name":"Bash","tool_input":{"command":"cmd"}}' \
  | CLAUDE_PROJECT_DIR="$REPO" "$POST_HOOK" >/dev/null 2>&1
rc=$?
set -e
assert_exit "no snapshot → exit 0 (skip)" "0" "$rc"
assert_file_content_eq "file preserved when no snapshot exists" "$REPO/src/other.ts" "hijack-no-snap"
git -C "$REPO" checkout -q -- .

# ── No active feature (on main) → skip ────────────────────────────
echo "=== on main: no enforcement ==="
git -C "$REPO" checkout -q main
rm -f "$SNAP_FILE"
printf '{"tool_name":"Bash","tool_input":{"command":"cmd"}}' \
  | CLAUDE_PROJECT_DIR="$REPO" "$PRE_HOOK" >/dev/null 2>&1 || true
echo "anything" > "$REPO/anywhere.txt"
set +e
printf '{"tool_name":"Bash","tool_input":{"command":"cmd"}}' \
  | CLAUDE_PROJECT_DIR="$REPO" "$POST_HOOK" >/dev/null 2>&1
rc=$?
set -e
assert_exit "no active feature exits 0" "0" "$rc"
rm -f "$REPO/anywhere.txt"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
if (( FAIL > 0 )); then
  exit 1
fi
