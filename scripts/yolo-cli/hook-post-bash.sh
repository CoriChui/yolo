#!/usr/bin/env bash
# hook-post-bash.sh — PostToolUse hook for Bash tool calls.
#
# Defense-in-depth: after every Bash tool call completes, diff the working
# tree (git status --porcelain) against the active plan's declared scope
# via is_path_in_scope. Any out-of-scope modification, addition, or deletion
# is reverted via `git checkout --` (tracked) or `rm` (untracked). The hook
# exits 2 when reverts were performed so Claude sees that the attempted
# write was undone.
#
# This catches bypasses that syntactic pre-hooks cannot:
#   - Inline interpreters: python -c "open('x','w').write('y')"
#   - dd, awk, ex, install, rsync, patch, ...
#   - Base64-decoded commands
#   - File-descriptor redirects: exec 9> file
#   - Branch switching that disables the pre-hook
#   - Feature-file deletion opening the gate
#
# Input (stdin JSON): Claude Code PostToolUse payload.
# Exit 0 = clean (no out-of-scope writes or no active feature).
# Exit 2 = reverts performed (blocks and informs Claude).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

# jq required for consistent JSON parsing
if ! command -v jq >/dev/null 2>&1; then
  # Fail open on missing jq to avoid wedging sessions; pre-hooks already
  # fail closed on jq-missing, so attackers can't exploit this branch.
  exit 0
fi

REPO="${CLAUDE_PROJECT_DIR:-$PWD}"

SLUG="$(get_active_feature "$REPO" 2>/dev/null || true)"
if [[ -z "$SLUG" ]]; then
  exit 0
fi

FEATURE_FILE="$REPO/.planning/features/$SLUG/feature.md"
if [[ ! -f "$FEATURE_FILE" ]]; then
  # Feature file deleted (bypass attempt) — we can't determine scope, so we
  # can't selectively revert. Log and exit 0; the pre-write hook should have
  # caught the delete itself.
  exit 0
fi

# Explicit bypass honored.
if [[ "${YOLO_BYPASS:-0}" == "1" ]]; then
  exit 0
fi

# Collect working-tree changes. --porcelain v1 lines are 2-char XY + space + path.
# For renames (R), path format is "orig -> new" — we handle that explicitly.
declare -a OUT_OF_SCOPE=()
declare -a REVERT_ACTIONS=()

while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  local_xy="${line:0:2}"
  path_part="${line:3}"
  # Handle rename syntax: "orig -> new"
  if [[ "$path_part" == *" -> "* ]]; then
    orig_path="${path_part% -> *}"
    new_path="${path_part#* -> }"
    paths=("$orig_path" "$new_path")
  else
    paths=("$path_part")
  fi
  for p in "${paths[@]}"; do
    # Unquote porcelain quoted paths
    p="${p#\"}"; p="${p%\"}"
    if ! is_path_in_scope "$FEATURE_FILE" "$p" "$REPO"; then
      OUT_OF_SCOPE+=("$p")
      # Decide how to revert based on XY status.
      # X = index (staged), Y = worktree (unstaged)
      case "$local_xy" in
        "??"|"A "|"AM"|"AD") REVERT_ACTIONS+=("untracked:$p") ;;
        "D "|" D") REVERT_ACTIONS+=("restore:$p") ;;
        *)         REVERT_ACTIONS+=("checkout:$p") ;;
      esac
    fi
  done
done < <(git -C "$REPO" status --porcelain 2>/dev/null || true)

if (( ${#OUT_OF_SCOPE[@]} == 0 )); then
  exit 0
fi

# Perform reverts. Failures to revert are surfaced but don't block the exit 2.
for action in "${REVERT_ACTIONS[@]}"; do
  kind="${action%%:*}"
  path="${action#*:}"
  case "$kind" in
    untracked)
      # New file created out of scope — remove it (carefully).
      if [[ -f "$REPO/$path" ]]; then
        rm -f -- "$REPO/$path" 2>/dev/null || true
      elif [[ -d "$REPO/$path" ]]; then
        rmdir -- "$REPO/$path" 2>/dev/null || true
      fi
      # Drop from index if it was staged
      git -C "$REPO" rm -f --cached -- "$path" 2>/dev/null || true
      ;;
    checkout)
      # Tracked file modified — revert index and worktree to HEAD.
      git -C "$REPO" checkout HEAD -- "$path" 2>/dev/null || true
      ;;
    restore)
      # Tracked file deleted — restore from HEAD.
      git -C "$REPO" checkout HEAD -- "$path" 2>/dev/null || true
      ;;
  esac
done

# Report what was reverted.
{
  echo "YOLO post-bash gate: reverted out-of-scope changes for feature '$SLUG'."
  echo ""
  echo "Changes reverted:"
  for p in "${OUT_OF_SCOPE[@]}"; do
    echo "  - $p"
  done
  echo ""
  echo "If this was intentional, add the paths to the plan's files: annotations"
  echo "or set YOLO_BYPASS=1 for this shell session."
} >&2

exit 2
