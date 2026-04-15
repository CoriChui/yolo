#!/usr/bin/env bash
# commit.sh — prefix-enforced git commit wrapper for YOLO v2 CLI
#
# Usage:
#   commit.sh task <N> "<message>" [--repo <path>] [--stage] [--allow-test-reduction]
#   commit.sh fix  <N> "<message>" [--repo <path>] [--stage]
#   commit.sh wip  ["<message>"]   [--repo <path>] [--stage]
#   commit.sh revert ["<message>"] [--repo <path>] [--stage]
#   commit.sh squash "<message>"   [--repo <path>] [--stage]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

# ── Argument parsing ───────────────────────────────────────────────────
PREFIX_TYPE="${1:-}"
shift || true

REPO_PATH="."
ALLOW_TEST_REDUCTION=0
STAGE_ALL=0
JSON_OUTPUT=0
TASK_NUM=""
MSG=""

if [[ -z "$PREFIX_TYPE" ]]; then
  echo "Error: No prefix type specified. Use: task, fix, wip, revert, squash" >&2
  exit 1
fi

# Validate prefix type
case "$PREFIX_TYPE" in
  task|fix|wip|revert|squash) ;;
  *)
    echo "Error: Unknown prefix type '$PREFIX_TYPE'. Use: task, fix, wip, revert, squash" >&2
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
    --stage)
      STAGE_ALL=1
      shift
      ;;
    --json)
      JSON_OUTPUT=1
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
  squash)
    MSG="${POSITIONAL[0]:-}"
    if [[ -z "$MSG" ]]; then
      echo "Error: 'squash' requires a message. Usage: commit.sh squash \"<message>\"" >&2
      exit 1
    fi
    FULL_PREFIX="[squash]"
    ;;
esac

COMMIT_MSG="$FULL_PREFIX $MSG"

# ── Append YOLO trailers (git-native state) ────────────────────────────
# Derive feature slug from branch; map prefix type to phase.
# Trailers are only appended when a feature slug is derivable (i.e. on a
# feature/<slug> branch). On main/master, commits like [squash] for ship also
# carry trailers via the PHASE_SLUG_OVERRIDE hook — handled below.
YOLO_SLUG=""
if slug_derived="$(get_active_feature "$REPO_PATH" 2>/dev/null)"; then
  YOLO_SLUG="$slug_derived"
fi

case "$PREFIX_TYPE" in
  task|fix) YOLO_PHASE="do" ;;
  wip)      YOLO_PHASE="wip" ;;
  revert)   YOLO_PHASE="revert" ;;
  squash)   YOLO_PHASE="ship" ;;
  *)        YOLO_PHASE="" ;;
esac

# Build trailer block. Use git interpret-trailers to guarantee
# canonical formatting and to dedupe if the message already contains trailers.
if [[ -n "$YOLO_SLUG" && -n "$YOLO_PHASE" ]]; then
  COMMIT_MSG="$(printf '%s\n' "$COMMIT_MSG" | git interpret-trailers \
    --if-exists replace \
    --trailer "YOLO-Feature: $YOLO_SLUG" \
    --trailer "YOLO-Phase: $YOLO_PHASE")"
elif [[ -n "$YOLO_PHASE" ]]; then
  # No slug (on main/master) — only emit the phase trailer for squash/ship-level commits
  if [[ "$PREFIX_TYPE" == "squash" ]]; then
    COMMIT_MSG="$(printf '%s\n' "$COMMIT_MSG" | git interpret-trailers \
      --if-exists replace \
      --trailer "YOLO-Phase: $YOLO_PHASE")"
  fi
fi

# ── Squash branch guard ─────────────────────────────────────────────────
# [squash] prefix is only valid on main/master (used during ship step)
if [[ "$PREFIX_TYPE" == "squash" ]]; then
  CURRENT_BRANCH=$(git -C "$REPO_PATH" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
  if [[ "$CURRENT_BRANCH" != "main" && "$CURRENT_BRANCH" != "master" ]]; then
    echo "Error: squash commits are only allowed on main/master (current branch: $CURRENT_BRANCH)" >&2
    exit 1
  fi
fi

# ── Stage all (if requested) — BEFORE integrity checks ────────────────
# Must happen before test integrity checks so that `git diff --cached`
# sees the agent's changes (otherwise checks run against empty staging area).
if (( STAGE_ALL )); then
  git -C "$REPO_PATH" add -A
fi

# ── Test integrity check ──────────────────────────────────────────────
# Only for task and fix commits (skip for wip/revert)
INTEGRITY_WARNINGS=()

if [[ "$PREFIX_TYPE" == "task" || "$PREFIX_TYPE" == "fix" ]] && (( ALLOW_TEST_REDUCTION == 0 )); then

  # ── Check 0: detect deleted test files ──────────────────────────
  DELETED_TEST_FILES=()
  while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    DELETED_TEST_FILES+=("$file")
  done < <(git -C "$REPO_PATH" diff --cached --name-only --diff-filter=D | grep -E "$YOLO_TEST_FILE_GREP" || true)

  for dtf in "${DELETED_TEST_FILES[@]}"; do
    INTEGRITY_WARNINGS+=("test_file_deleted:$dtf")
  done

  # Get list of staged test files (added/copied/modified/renamed)
  TEST_FILES=()
  while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    TEST_FILES+=("$file")
  done < <(git -C "$REPO_PATH" diff --cached --name-only --diff-filter=ACMR | grep -E "$YOLO_TEST_FILE_GREP" || true)

  if (( ${#TEST_FILES[@]} > 0 )); then

    # ── Check 1: test count must not decrease ──────────────────────
    # Count test-like patterns in staged version vs HEAD version
    TEST_PATTERNS='(test\(|it\(|describe\(|def test_|#\[test\]|@Test|func Test|class Test)'

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
      INTEGRITY_WARNINGS+=("test_count_decreased:${TOTAL_HEAD}>${TOTAL_STAGED}")
    fi

    # ── Check 2: no skip/disable markers in staged diff ────────────
    SKIP_PATTERNS="$YOLO_SKIP_PATTERNS"
    skip_matches=""
    skip_matches=$(git -C "$REPO_PATH" diff --cached -- "${TEST_FILES[@]}" | grep -E "^\+" | grep -E "$SKIP_PATTERNS" || true)

    if [[ -n "$skip_matches" ]]; then
      skip_count=$(printf '%s\n' "$skip_matches" | wc -l | tr -d ' ')
      INTEGRITY_WARNINGS+=("skip_marker_added:${skip_count} lines")
    fi
  fi
fi

# ── Commit ─────────────────────────────────────────────────────────────
git -C "$REPO_PATH" commit -m "$COMMIT_MSG"

# ── Report warnings ──────────────────────────────────────────────────
if (( JSON_OUTPUT )); then
  warnings_str=""
  for w in "${INTEGRITY_WARNINGS[@]}"; do
    if [[ -n "$warnings_str" ]]; then warnings_str+="|"; fi
    warnings_str+="$w"
  done
  emit_json "true" "$warnings_str" ""
else
  if (( ${#INTEGRITY_WARNINGS[@]} > 0 )); then
    for w in "${INTEGRITY_WARNINGS[@]}"; do
      wtype="${w%%:*}"
      wdetail="${w#*:}"
      echo "WARNING: $wtype — $wdetail" >&2
    done
  fi
fi
