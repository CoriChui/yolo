#!/usr/bin/env bash
# commit.sh — prefix-enforced git commit wrapper for YOLO v2 CLI
#
# Usage:
#   commit.sh task <N> "<message>" [--repo <path>] [--allow-test-reduction]
#   commit.sh fix  <N> "<message>" [--repo <path>]
#   commit.sh wip  ["<message>"]   [--repo <path>]
#   commit.sh revert ["<message>"] [--repo <path>]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

# ── Argument parsing ───────────────────────────────────────────────────
PREFIX_TYPE="${1:-}"
shift || true

REPO_PATH="."
ALLOW_TEST_REDUCTION=0
TASK_NUM=""
MSG=""

if [[ -z "$PREFIX_TYPE" ]]; then
  echo "Error: No prefix type specified. Use: task, fix, wip, revert" >&2
  exit 1
fi

# Validate prefix type
case "$PREFIX_TYPE" in
  task|fix|wip|revert) ;;
  *)
    echo "Error: Unknown prefix type '$PREFIX_TYPE'. Use: task, fix, wip, revert" >&2
    exit 1
    ;;
esac

# Parse remaining args based on prefix type
POSITIONAL=()
while (( $# > 0 )); do
  case "$1" in
    --repo)
      REPO_PATH="${2:-}"
      if [[ -z "$REPO_PATH" ]]; then
        echo "Error: --repo requires a path argument" >&2
        exit 1
      fi
      shift 2
      ;;
    --allow-test-reduction)
      ALLOW_TEST_REDUCTION=1
      shift
      ;;
    *)
      POSITIONAL+=("$1")
      shift
      ;;
  esac
done

# Assign positional args based on prefix type
case "$PREFIX_TYPE" in
  task|fix)
    TASK_NUM="${POSITIONAL[0]:-}"
    MSG="${POSITIONAL[1]:-}"

    if [[ -z "$TASK_NUM" ]]; then
      echo "Error: '$PREFIX_TYPE' requires a task number. Usage: commit.sh $PREFIX_TYPE <N> \"<message>\"" >&2
      exit 1
    fi

    # Validate that N is a number
    if ! [[ "$TASK_NUM" =~ ^[0-9]+$ ]]; then
      echo "Error: Task number must be a positive integer, got '$TASK_NUM'" >&2
      exit 1
    fi

    if [[ -z "$MSG" ]]; then
      echo "Error: '$PREFIX_TYPE' requires a message. Usage: commit.sh $PREFIX_TYPE <N> \"<message>\"" >&2
      exit 1
    fi

    FULL_PREFIX="[$PREFIX_TYPE-$TASK_NUM]"
    ;;
  wip)
    MSG="${POSITIONAL[0]:-Parking feature}"
    FULL_PREFIX="[wip]"
    ;;
  revert)
    MSG="${POSITIONAL[0]:-}"
    if [[ -z "$MSG" ]]; then
      MSG="revert"
    fi
    FULL_PREFIX="[revert]"
    ;;
esac

COMMIT_MSG="$FULL_PREFIX $MSG"

# ── Test integrity check ──────────────────────────────────────────────
# Only for task and fix commits (skip for wip/revert)
if [[ "$PREFIX_TYPE" == "task" || "$PREFIX_TYPE" == "fix" ]] && (( ALLOW_TEST_REDUCTION == 0 )); then

  # Get list of staged test files
  TEST_FILES=()
  while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    TEST_FILES+=("$file")
  done < <(git -C "$REPO_PATH" diff --cached --name-only --diff-filter=ACMR | grep -E '(\.test\.|\.spec\.|_test\.|^test_)' || true)

  if (( ${#TEST_FILES[@]} > 0 )); then

    # ── Check 1: test count must not decrease ──────────────────────
    # Count test-like patterns in staged version vs HEAD version
    TEST_PATTERNS='(test\(|it\(|describe\(|def test_|#\[test\])'

    TOTAL_HEAD=0
    TOTAL_STAGED=0

    for tfile in "${TEST_FILES[@]}"; do
      # Count in HEAD version (may not exist if file is new)
      head_count=0
      if git -C "$REPO_PATH" show "HEAD:$tfile" &>/dev/null; then
        head_count=$(git -C "$REPO_PATH" show "HEAD:$tfile" | grep -cE "$TEST_PATTERNS" || true)
      fi

      # Count in staged version
      staged_count=$(git -C "$REPO_PATH" show ":$tfile" | grep -cE "$TEST_PATTERNS" || true)

      TOTAL_HEAD=$(( TOTAL_HEAD + head_count ))
      TOTAL_STAGED=$(( TOTAL_STAGED + staged_count ))
    done

    if (( TOTAL_STAGED < TOTAL_HEAD )); then
      echo "Error: Test count decreased ($TOTAL_HEAD → $TOTAL_STAGED). Tests must not be deleted." >&2
      exit 1
    fi

    # ── Check 2: no skip/disable markers in staged diff ────────────
    SKIP_PATTERNS='\.(skip|only)\b|xit\(|xdescribe\(|@pytest\.mark\.skip|@unittest\.skip'
    skip_matches=""
    skip_matches=$(git -C "$REPO_PATH" diff --cached -- "${TEST_FILES[@]}" | grep -E "^\+" | grep -E "$SKIP_PATTERNS" || true)

    if [[ -n "$skip_matches" ]]; then
      echo "Error: Found skip/disable markers in staged test files:" >&2
      echo "$skip_matches" >&2
      exit 1
    fi
  fi
fi

# ── Commit ─────────────────────────────────────────────────────────────
git -C "$REPO_PATH" commit -m "$COMMIT_MSG"
