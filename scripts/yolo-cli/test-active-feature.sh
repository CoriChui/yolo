#!/usr/bin/env bash
# test-active-feature.sh — tests for scripts/yolo-cli/active-feature.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/active-feature.sh"

PASS=0
FAIL=0

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "  PASS: $label"
    PASS=$(( PASS + 1 ))
  else
    echo "  FAIL: $label"
    echo "    expected: '$expected'"
    echo "    actual:   '$actual'"
    FAIL=$(( FAIL + 1 ))
  fi
}

TMPDIR_TEST="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_TEST"' EXIT

# ── Fixture: empty repo on main ────────────────────────────────────
REPO="$TMPDIR_TEST/repo"
mkdir -p "$REPO"
git -C "$REPO" init -q -b main
git -C "$REPO" config user.email "t@t.t"
git -C "$REPO" config user.name "t"
echo "seed" > "$REPO/seed.txt"
git -C "$REPO" add seed.txt
git -C "$REPO" commit -q -m "seed"

echo "=== no active feature (branch: main) ==="
set +e
out=$("$SCRIPT" --repo "$REPO" 2>/dev/null)
rc=$?
set -e
assert_eq "exits 1 on main" "1" "$rc"
assert_eq "no output on main" "" "$out"

# ── On feature branch with no trailered commits: phase = plan ─────
echo "=== feature branch, no trailers → phase plan ==="
git -C "$REPO" checkout -q -b feature/dark-mode
out=$("$SCRIPT" --repo "$REPO" 2>/dev/null)
assert_eq "plain format: slug + plan phase" "dark-mode plan" "$out"

out=$("$SCRIPT" --repo "$REPO" --format status 2>/dev/null)
assert_eq "status format: yolo: slug · plan" "yolo: dark-mode · plan" "$out"

# ── After task commit: phase = do ─────────────────────────────────
echo "=== feature branch, task commit → phase do ==="
echo "x" > "$REPO/a.js"
git -C "$REPO" add a.js
git -C "$REPO" commit -q -m "[task-1] first

YOLO-Feature: dark-mode
YOLO-Phase: do"

out=$("$SCRIPT" --repo "$REPO" 2>/dev/null)
assert_eq "plain format reports do after task commit" "dark-mode do" "$out"

out=$("$SCRIPT" --repo "$REPO" --format status 2>/dev/null)
assert_eq "status format reports do after task commit" "yolo: dark-mode · do" "$out"

# ── Different feature branch ──────────────────────────────────────
echo "=== switching feature branches reflects new slug ==="
git -C "$REPO" checkout -q -b feature/login-flow
out=$("$SCRIPT" --repo "$REPO" 2>/dev/null)
assert_eq "new feature branch reports new slug (phase falls back to plan)" "login-flow plan" "$out"

# ── Switching back to main clears output ──────────────────────────
echo "=== switch back to main → exit 1 ==="
git -C "$REPO" checkout -q main
set +e
out=$("$SCRIPT" --repo "$REPO" 2>/dev/null)
rc=$?
set -e
assert_eq "main branch again exits 1" "1" "$rc"

# ── Phase cache: second call uses cached value ───────────────────
echo "=== get_current_phase cache ==="
# Source lib.sh in a controlled subshell to exercise the cache
source "$SCRIPT_DIR/lib.sh"
git -C "$REPO" checkout -q feature/dark-mode
# Clean any stale cache from previous runs
rm -f /tmp/yolo-phase-${USER:-anon}-*

# First call computes and writes cache
phase1="$(get_current_phase "$REPO")"
head_sha="$(git -C "$REPO" rev-parse --short=12 HEAD)"
# Cache key format: /tmp/yolo-phase-<user>-<sha>-<slug>-<branch>
cache_file="/tmp/yolo-phase-${USER:-anon}-${head_sha}-dark-mode-HEAD"
if [[ -f "$cache_file" ]]; then
  echo "  PASS: cache file created after first call"
  PASS=$(( PASS + 1 ))
else
  echo "  FAIL: cache file not created"
  FAIL=$(( FAIL + 1 ))
fi

# Tamper with cache to prove second call uses it (not recomputation)
echo "sentinel-cached-value" > "$cache_file"
phase2="$(get_current_phase "$REPO")"
assert_eq "second call returns cached value (not recomputed)" "sentinel-cached-value" "$phase2"

# YOLO_NO_PHASE_CACHE=1 bypasses cache
phase3="$(YOLO_NO_PHASE_CACHE=1 get_current_phase "$REPO")"
if [[ "$phase3" != "sentinel-cached-value" ]]; then
  echo "  PASS: YOLO_NO_PHASE_CACHE=1 bypasses cache"
  PASS=$(( PASS + 1 ))
else
  echo "  FAIL: cache not bypassed"
  FAIL=$(( FAIL + 1 ))
fi

# New commit → new SHA → cache miss → fresh compute
echo "more" > "$REPO/a.js"
git -C "$REPO" add a.js
git -C "$REPO" commit -q -m "[task-2] something

YOLO-Feature: dark-mode
YOLO-Phase: check"

phase4="$(get_current_phase "$REPO")"
assert_eq "new commit invalidates cache (fresh value)" "check" "$phase4"

# Cleanup
rm -f /tmp/yolo-phase-${USER:-anon}-*

# ── Invalid --format errors ───────────────────────────────────────
echo "=== invalid --format rejected ==="
set +e
out=$("$SCRIPT" --repo "$REPO" --format bogus 2>&1 >/dev/null)
rc=$?
set -e
assert_eq "invalid --format exits 1" "1" "$rc"

# ── Summary ───────────────────────────────────────────────────────
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
if (( FAIL > 0 )); then
  exit 1
fi
