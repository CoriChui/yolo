#!/usr/bin/env bash
# hook-post-bash.sh — PostToolUse hook for Bash tool calls.
#
# Delta-based, NON-DESTRUCTIVE by default.
#
# After every Bash tool call completes, compare `git status --porcelain`
# against the snapshot written by hook-pre-bash.sh to isolate the CHANGES
# PRODUCED BY THIS COMMAND (not pre-existing dirty state). For each changed
# path, check scope via is_path_in_scope. If any out-of-scope change was
# produced, report it and exit 2.
#
# Default behavior is REPORT-ONLY. Set YOLO_POST_BASH_REVERT=1 to also
# revert the out-of-scope changes via git checkout / rm. This is opt-in
# because the prior destructive default incorrectly reverted pre-existing
# dirty state (see [fix-3] commit) — keeping report-as-default means the
# hook can never destroy user work it didn't produce.
#
# Bypasses:
#   - YOLO_BYPASS=1 skips the entire check
#   - No active feature → skip (no enforcement on main)
#   - Missing feature file → skip (pre-write hook already blocks the delete)
#
# Input (stdin JSON): Claude Code PostToolUse payload. Parsed via jq.
# Exit 0 = clean (no delta or no active feature).
# Exit 2 = out-of-scope delta produced by this command.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

if ! command -v jq >/dev/null 2>&1; then
  # Fail open on missing jq to avoid wedging sessions.
  exit 0
fi

REPO="${CLAUDE_PROJECT_DIR:-$PWD}"

SLUG="$(get_active_feature "$REPO" 2>/dev/null || true)"
if [[ -z "$SLUG" ]]; then
  exit 0
fi

FEATURE_FILE="$REPO/.planning/features/$SLUG/feature.md"
if [[ ! -f "$FEATURE_FILE" ]]; then
  # Feature file missing on a feature branch = tamper or accidental delete.
  # Fail CLOSED: the absence of the plan means we cannot verify scope, and
  # allowing writes silently was the exact vulnerability this fixes.
  echo "YOLO post-bash: feature file for '$SLUG' is missing — blocking. Restore it or switch to main." >&2
  audit_log "$REPO" "block" "post-bash" "$SLUG" "feature.md missing" ""
  exit 2
fi

if [[ "${YOLO_BYPASS:-0}" == "1" ]]; then
  exit 0
fi

# ── Read pre-command snapshot via pointer file ────────────────────
# The pre-hook writes a unique mktemp-ed snapshot and stores its path in
# a pointer keyed by PPID. We read the pointer, consume the snapshot,
# then clean up both files. This is race-safe across parallel tool calls
# (each pre-hook creates a distinct mktemp-ed file) and poison-resistant
# (chmod 600 + mktemp-random suffix).
SNAP_PTR="/tmp/yolo-snap-ptr-${PPID:-$$}"
if [[ ! -f "$SNAP_PTR" ]]; then
  exit 0
fi
SNAP="$(cat "$SNAP_PTR" 2>/dev/null || true)"
if [[ -z "$SNAP" || ! -f "$SNAP" ]]; then
  rm -f "$SNAP_PTR" 2>/dev/null || true
  exit 0
fi
# Clean up pointer + snapshot after reading (one-shot consumption).
trap 'rm -f "$SNAP" "$SNAP_PTR" 2>/dev/null' EXIT

# ── Compute current status and diff against snapshot ──────────────
CURRENT_STATUS="$(git -C "$REPO" status --porcelain 2>/dev/null || true)"

# Paths whose porcelain line exists in CURRENT but not in SNAP are new
# changes produced by this command. Use grep -Fvxf for fixed-string
# set difference (line-exact match).
DELTA_LINES=""
if [[ -n "$CURRENT_STATUS" ]]; then
  DELTA_LINES="$(printf '%s\n' "$CURRENT_STATUS" | grep -Fvxf "$SNAP" 2>/dev/null || true)"
fi

if [[ -z "$DELTA_LINES" ]]; then
  exit 0
fi

# ── Check each delta path against scope ───────────────────────────
declare -a OUT_OF_SCOPE=()
declare -a DELTA_ACTIONS=()

while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  local_xy="${line:0:2}"
  path_part="${line:3}"
  if [[ "$path_part" == *" -> "* ]]; then
    new_path="${path_part#* -> }"
    paths=("$new_path")
  else
    paths=("$path_part")
  fi
  for p in "${paths[@]}"; do
    p="${p#\"}"; p="${p%\"}"
    if ! is_path_in_scope "$FEATURE_FILE" "$p" "$REPO"; then
      OUT_OF_SCOPE+=("$p")
      case "$local_xy" in
        "??"|"A "|"AM"|"AD") DELTA_ACTIONS+=("untracked:$p") ;;
        "D "|" D")           DELTA_ACTIONS+=("restore:$p") ;;
        *)                   DELTA_ACTIONS+=("checkout:$p") ;;
      esac
    fi
  done
done <<< "$DELTA_LINES"

if (( ${#OUT_OF_SCOPE[@]} == 0 )); then
  exit 0
fi

# ── Optional destructive revert (opt-in) ──────────────────────────
REVERT_PERFORMED=0
if [[ "${YOLO_POST_BASH_REVERT:-0}" == "1" ]]; then
  REVERT_PERFORMED=1
  for action in "${DELTA_ACTIONS[@]}"; do
    kind="${action%%:*}"
    path="${action#*:}"
    case "$kind" in
      untracked)
        [[ -f "$REPO/$path" ]] && rm -f -- "$REPO/$path" 2>/dev/null || true
        git -C "$REPO" rm -f --cached -- "$path" 2>/dev/null || true
        ;;
      checkout|restore)
        git -C "$REPO" checkout HEAD -- "$path" 2>/dev/null || true
        ;;
    esac
  done
fi

# ── Report ────────────────────────────────────────────────────────
{
  if (( REVERT_PERFORMED )); then
    echo "YOLO post-bash: reverted out-of-scope changes produced by this command (feature '$SLUG')."
  else
    echo "YOLO post-bash: detected out-of-scope changes produced by this command (feature '$SLUG')."
    echo "This command wrote to paths outside the plan scope. Changes were NOT reverted (report-only mode)."
  fi
  echo ""
  echo "Out-of-scope paths:"
  for p in "${OUT_OF_SCOPE[@]}"; do
    echo "  - $p"
  done
  echo ""
  echo "Options:"
  echo "  1. Undo the changes manually (git diff / git checkout / rm)"
  echo "  2. Add the paths to the plan's 'files:' annotations if they belong"
  echo "  3. Set YOLO_POST_BASH_REVERT=1 to have the hook auto-revert"
} >&2

for p in "${OUT_OF_SCOPE[@]}"; do
  audit_log "$REPO" "$([[ $REVERT_PERFORMED == 1 ]] && echo revert || echo report)" \
    "post-bash" "$SLUG" "$p" ""
done

exit 2
