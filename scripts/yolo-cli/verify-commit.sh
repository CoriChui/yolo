#!/usr/bin/env bash
# verify-commit.sh — Compare agent's claimed file changes against actual git diff.
#
# Usage:
#   verify-commit.sh <task-id> <files-changed> [--repo <path>] [--commit-hash <hash>]
#                    [--branch <branch>] [--allow-test-reduction]
#
# <task-id>:       e.g. "task-1" — looks for [task-1] or [fix-1] in most recent commits
# <files-changed>: comma-separated list of claimed files, e.g. "src/app.ts,src/app.test.ts"
#
# Exit 0 = verified, Exit 1 = warnings found
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

# ── Argument parsing ───────────────────────────────────────────────
TASK_ID="${1:-}"
FILES_CHANGED="${2:-}"
shift 2 2>/dev/null || true

REPO_PATH="."
COMMIT_HASH=""
BRANCH=""
ALLOW_TEST_REDUCTION=0

while (( $# > 0 )); do
  case "$1" in
    --repo)
      REPO_PATH="${2:-}"
      [[ -z "$REPO_PATH" ]] && { echo "Error: --repo requires a path" >&2; exit 1; }
      shift 2
      ;;
    --commit-hash)
      COMMIT_HASH="${2:-}"
      shift 2
      ;;
    --branch)
      BRANCH="${2:-}"
      shift 2
      ;;
    --allow-test-reduction)
      ALLOW_TEST_REDUCTION=1
      shift
      ;;
    *)
      echo "Error: unknown argument '$1'" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$TASK_ID" ]]; then
  echo "Usage: verify-commit.sh <task-id> <files-changed> [--repo <path>]" >&2
  exit 1
fi

# ── Find the commit ────────────────────────────────────────────────
if [[ -z "$COMMIT_HASH" ]]; then
  COMMIT_HASH=$(git -C "$REPO_PATH" log -1 --format='%H' --grep="\[${TASK_ID}\]\|\[fix-${TASK_ID#task-}\]" ${BRANCH:+"$BRANCH"} 2>/dev/null || true)
fi

if [[ -z "$COMMIT_HASH" ]]; then
  echo "Error: no commit found matching [$TASK_ID]" >&2
  exit 1
fi

# ── Get actual files changed ──────────────────────────────────────
ACTUAL_FILES=()
while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  ACTUAL_FILES+=("$f")
done < <(git -C "$REPO_PATH" diff-tree --no-commit-id --name-only -r "$COMMIT_HASH" 2>/dev/null || true)

# ── Parse claimed files ───────────────────────────────────────────
CLAIMED_FILES=()
if [[ -n "$FILES_CHANGED" ]]; then
  local_ifs="$IFS"
  IFS=','
  read -ra CLAIMED_FILES <<< "$FILES_CHANGED"
  IFS="$local_ifs"
fi

# ── Compare ───────────────────────────────────────────────────────
WARNINGS=()

# Thin commit check
if (( ${#ACTUAL_FILES[@]} == 0 )); then
  WARNINGS+=("thin_commit:0 files changed in $COMMIT_HASH")
fi

# Unexpected files (in actual but not in claimed)
for actual in "${ACTUAL_FILES[@]}"; do
  found=false
  for claimed in "${CLAIMED_FILES[@]}"; do
    claimed="${claimed#"${claimed%%[![:space:]]*}"}"
    claimed="${claimed%"${claimed##*[![:space:]]}"}"
    if [[ "$actual" == "$claimed" ]]; then
      found=true
      break
    fi
  done
  if ! $found; then
    WARNINGS+=("unexpected_file:$actual")
  fi
done

# Claimed but not actually changed
for claimed in "${CLAIMED_FILES[@]}"; do
  claimed="${claimed#"${claimed%%[![:space:]]*}"}"
  claimed="${claimed%"${claimed##*[![:space:]]}"}"
  [[ -z "$claimed" ]] && continue
  found=false
  for actual in "${ACTUAL_FILES[@]}"; do
    if [[ "$actual" == "$claimed" ]]; then
      found=true
      break
    fi
  done
  if ! $found; then
    WARNINGS+=("claimed_not_changed:$claimed")
  fi
done

# ── Test integrity (reuse patterns from lib.sh) ───────────────────
if (( ALLOW_TEST_REDUCTION == 0 )); then
  for actual in "${ACTUAL_FILES[@]}"; do
    if printf '%s' "$actual" | grep -qE "$YOLO_TEST_FILE_GREP"; then
      # Test count decrease
      head_count=0
      if git -C "$REPO_PATH" show "${COMMIT_HASH}~1:$actual" &>/dev/null 2>&1; then
        head_count=$(git -C "$REPO_PATH" show "${COMMIT_HASH}~1:$actual" 2>/dev/null | grep -cE '(test\(|it\(|describe\(|def test_|#\[test\]|@Test|func Test)' || true)
      fi
      curr_count=$(git -C "$REPO_PATH" show "${COMMIT_HASH}:$actual" 2>/dev/null | grep -cE '(test\(|it\(|describe\(|def test_|#\[test\]|@Test|func Test)' || true)
      if (( curr_count < head_count )); then
        WARNINGS+=("test_count_decreased:$actual:${head_count}>${curr_count}")
      fi

      # Skip markers
      skip_diff=$(git -C "$REPO_PATH" diff "${COMMIT_HASH}~1" "$COMMIT_HASH" -- "$actual" 2>/dev/null | grep -E '^\+' | grep -E "$YOLO_SKIP_PATTERNS" || true)
      if [[ -n "$skip_diff" ]]; then
        WARNINGS+=("skip_marker_added:$actual")
      fi
    fi
  done
fi

# Deleted test files
for pathspec in "${YOLO_TEST_FILE_PATHSPECS[@]}"; do
  while IFS= read -r deleted; do
    [[ -z "$deleted" ]] && continue
    WARNINGS+=("test_file_deleted:$deleted")
  done < <(git -C "$REPO_PATH" diff-tree --no-commit-id --name-only --diff-filter=D -r "$COMMIT_HASH" -- "$pathspec" 2>/dev/null || true)
done

# ── Report ────────────────────────────────────────────────────────
if (( ${#WARNINGS[@]} > 0 )); then
  echo "verify-commit: ${#WARNINGS[@]} warning(s) for $TASK_ID ($COMMIT_HASH):" >&2
  for w in "${WARNINGS[@]}"; do
    wtype="${w%%:*}"
    wdetail="${w#*:}"
    echo "  WARNING: $wtype — $wdetail" >&2
  done
  exit 1
fi

echo "verify-commit: $TASK_ID ($COMMIT_HASH) verified — ${#ACTUAL_FILES[@]} file(s), no issues."
exit 0
