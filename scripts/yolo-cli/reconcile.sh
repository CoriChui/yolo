#!/usr/bin/env bash
#
# reconcile.sh — Reconcile a YOLO v2 feature file against git commit evidence.
#
# Usage:
#   reconcile.sh <feature-file> <branch-name> [--fix] [--repo <path>]
#
# Reads the feature file's ## Plan section, compares checkboxes against
# [task-N] commits on the feature branch, derives the current step,
# and reports drift. With --fix, updates the feature file in place.
#
set -euo pipefail

# shellcheck source=lib.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

# ---------- argument parsing ----------

FIX=false
REPO_PATH="."
FEATURE_FILE=""
BRANCH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    # --apply and --fix both enable mutations; --fix is kept as a compatibility
    # alias for prior callers and tests. Read-only mode is the default.
    --apply|--fix) FIX=true; shift ;;
    --repo)   REPO_PATH="${2:-}"; if [[ -z "$REPO_PATH" ]]; then echo "Error: --repo requires a path" >&2; exit 1; fi; shift 2 ;;
    -*)       echo "Unknown option: $1" >&2; exit 1 ;;
    *)
      if [[ -z "$FEATURE_FILE" ]]; then
        FEATURE_FILE="$1"
      elif [[ -z "$BRANCH" ]]; then
        BRANCH="$1"
      else
        echo "Unexpected argument: $1" >&2; exit 1
      fi
      shift
      ;;
  esac
done

# ── Refuse to run during unsafe git states ──────────────────────────
# Rebase, bisect, merge, cherry-pick all have intermediate SHAs that would
# poison the phase derivation. Refuse until the operation finishes.
check_unsafe_state() {
  local repo="$1" gitdir
  gitdir="$(git -C "$repo" rev-parse --git-dir 2>/dev/null || true)"
  [[ -z "$gitdir" ]] && return 0
  # git-dir is relative to repo; normalize
  case "$gitdir" in
    /*) ;;
    *) gitdir="$repo/$gitdir" ;;
  esac
  local unsafe=""
  [[ -d "$gitdir/rebase-merge" ]] && unsafe="rebase (merge-mode)"
  [[ -d "$gitdir/rebase-apply" ]] && unsafe="rebase (apply-mode)"
  [[ -f "$gitdir/MERGE_HEAD" ]]     && unsafe="pending merge"
  [[ -f "$gitdir/CHERRY_PICK_HEAD" ]] && unsafe="cherry-pick in progress"
  [[ -f "$gitdir/REVERT_HEAD" ]]    && unsafe="revert in progress"
  [[ -f "$gitdir/BISECT_LOG" ]]     && unsafe="bisect in progress"
  if [[ -n "$unsafe" ]]; then
    echo "Error: refusing to reconcile during $unsafe — finish or abort the operation first" >&2
    exit 1
  fi
}
check_unsafe_state "$REPO_PATH"

if [[ -z "$FEATURE_FILE" ]]; then
  echo "Usage: reconcile.sh <feature-file> [<branch-name>] [--fix] [--repo <path>]" >&2
  exit 1
fi

# Auto-detect branch from feature file frontmatter if not provided
if [[ -z "$BRANCH" ]]; then
  BRANCH="$(parse_frontmatter "$FEATURE_FILE" "branch")"
  if [[ -z "$BRANCH" ]]; then
    echo "Error: No branch specified and no 'branch:' field in feature file frontmatter" >&2
    exit 1
  fi
fi

if [[ ! -f "$FEATURE_FILE" ]]; then
  echo "Error: Feature file not found: $FEATURE_FILE" >&2
  exit 1
fi

# Resolve to absolute path before any cd operations
FEATURE_FILE="$(cd "$(dirname "$FEATURE_FILE")" && pwd)/$(basename "$FEATURE_FILE")"

# ---------- timing ----------
START_TIME=$SECONDS

# ---------- 1. Parse the ## Plan section ----------
# Extract lines between "## Plan" and the next "##" heading (or EOF).
# Each line matching "N. [x] ..." or "N. [ ] ..." is a task checkbox.

IN_PLAN=false
declare -a PLAN_TASK_IDS=()      # ordered task IDs from the plan
declare -A PLAN_CHECKED=()        # task-id -> "true" | "false"
declare -A PLAN_LABELS=()         # task-id -> full label text
declare -A PLAN_HASHES=()         # task-id -> commit hash noted in file (if any)

while IFS= read -r line; do
  # Detect section boundaries
  if [[ "$line" =~ ^##[[:space:]] ]]; then
    if [[ "$line" =~ ^##[[:space:]]Plan ]]; then
      IN_PLAN=true
      continue
    else
      IN_PLAN=false
      continue
    fi
  fi

  if $IN_PLAN; then
    # Match: "N. [x] description" or "N. [ ] description"
    # The task number N becomes task-N.
    if [[ "$line" =~ ^([0-9]+)\.[[:space:]]\[([xX[:space:]])\][[:space:]]*(.*) ]]; then
      TASK_NUM="${BASH_REMATCH[1]}"
      CHECK_CHAR="${BASH_REMATCH[2]}"
      LABEL="${BASH_REMATCH[3]}"
      TASK_ID="task-${TASK_NUM}"

      PLAN_TASK_IDS+=("$TASK_ID")
      PLAN_LABELS["$TASK_ID"]="$LABEL"

      if [[ "$CHECK_CHAR" == "x" || "$CHECK_CHAR" == "X" ]]; then
        PLAN_CHECKED["$TASK_ID"]="true"
      else
        PLAN_CHECKED["$TASK_ID"]="false"
      fi

      # Extract trailing commit hash if present (e.g., "— a1b2c3d" or "-- a1b2c3d")
      if [[ "$LABEL" =~ [—–-]+[[:space:]]*([0-9a-f]{7,40})$ ]]; then
        PLAN_HASHES["$TASK_ID"]="${BASH_REMATCH[1]}"
      else
        PLAN_HASHES["$TASK_ID"]=""
      fi
    fi
  fi
done < "$FEATURE_FILE"

# Empty plan is valid — means we're in think/plan state (handled in step derivation)

# ---------- 2. Find [task-N] commits on the feature branch ----------
# Use merge-base to only look at commits on the feature branch (not inherited from main).

cd "$REPO_PATH"

# Determine the merge base. If branch doesn't exist or no merge-base, handle gracefully.
MAIN_BRANCH=""
for candidate in main master; do
  if git rev-parse --verify "$candidate" &>/dev/null; then
    MAIN_BRANCH="$candidate"
    break
  fi
done

if [[ -z "$MAIN_BRANCH" ]]; then
  # No main/master — use root commit as base
  MERGE_BASE=$(git rev-list --max-parents=0 HEAD 2>/dev/null | head -1)
else
  MERGE_BASE=$(git merge-base "$MAIN_BRANCH" "$BRANCH" 2>/dev/null || git rev-list --max-parents=0 HEAD 2>/dev/null | head -1)
fi

# Get commits on the feature branch with [task-N] or [fix-N] markers
declare -A GIT_TASK_COMMITS=()   # task-id -> commit hash (short)
declare -A GIT_TASK_MSGS=()      # task-id -> commit message

while IFS= read -r logline; do
  [[ -z "$logline" ]] && continue
  COMMIT_HASH="${logline%% *}"
  COMMIT_MSG="${logline#* }"

  # Extract [task-N] or [fix-N] from the commit message
  if [[ "$COMMIT_MSG" =~ \[(task|fix)-([0-9]+)\] ]]; then
    TID="task-${BASH_REMATCH[2]}"
    # If multiple commits for same task, keep the latest (first in log = most recent)
    if [[ -z "${GIT_TASK_COMMITS[$TID]+x}" ]]; then
      GIT_TASK_COMMITS["$TID"]="$COMMIT_HASH"
      GIT_TASK_MSGS["$TID"]="$COMMIT_MSG"
    fi
  fi
# BRE: match commits containing [task- or [fix-
done < <(git log "${MERGE_BASE}..${BRANCH}" --oneline --grep='\[task-\|\[fix-' 2>/dev/null || true)

# ---------- 3. Compare and detect drift ----------

declare -a DRIFT_MSGS=()
declare -A RECONCILED_CHECKED=()   # task-id -> "true" | "false" (corrected)
declare -A RECONCILED_HASHES=()    # task-id -> commit hash (corrected)

TOTAL_TASKS=${#PLAN_TASK_IDS[@]}
COMPLETED_TASKS=0

for TASK_ID in "${PLAN_TASK_IDS[@]}"; do
  HAS_COMMIT=false
  if [[ -n "${GIT_TASK_COMMITS[$TASK_ID]+x}" ]]; then
    HAS_COMMIT=true
  fi

  FILE_CHECKED="${PLAN_CHECKED[$TASK_ID]}"

  if $HAS_COMMIT; then
    RECONCILED_CHECKED["$TASK_ID"]="true"
    RECONCILED_HASHES["$TASK_ID"]="${GIT_TASK_COMMITS[$TASK_ID]}"
    COMPLETED_TASKS=$((COMPLETED_TASKS + 1))

    if [[ "$FILE_CHECKED" == "false" ]]; then
      DRIFT_MSGS+=("DRIFT: $TASK_ID is UNCHECKED in file but has commit ${GIT_TASK_COMMITS[$TASK_ID]} — should be checked")
    fi
    # Also check if the hash in the file matches
    FILE_HASH="${PLAN_HASHES[$TASK_ID]}"
    if [[ -n "$FILE_HASH" && "$FILE_HASH" != "${GIT_TASK_COMMITS[$TASK_ID]}" ]]; then
      DRIFT_MSGS+=("DRIFT: $TASK_ID hash in file ($FILE_HASH) differs from git (${GIT_TASK_COMMITS[$TASK_ID]})")
    fi
  else
    RECONCILED_CHECKED["$TASK_ID"]="false"
    RECONCILED_HASHES["$TASK_ID"]=""

    if [[ "$FILE_CHECKED" == "true" ]]; then
      DRIFT_MSGS+=("DRIFT: $TASK_ID is CHECKED in file but has NO matching commit — should be unchecked")
    fi
  fi
done

# Check for orphan commits (commits for tasks not in the plan)
declare -a ORPHAN_COMMITS=()
for TID in "${!GIT_TASK_COMMITS[@]}"; do
  FOUND=false
  for PID in "${PLAN_TASK_IDS[@]}"; do
    if [[ "$PID" == "$TID" ]]; then
      FOUND=true
      break
    fi
  done
  if ! $FOUND; then
    ORPHAN_COMMITS+=("ORPHAN: Commit ${GIT_TASK_COMMITS[$TID]} references $TID which is not in the plan")
  fi
done

# ---------- 4. Derive current step ----------
# Rules from spec:
#   - No commits on branch -> think or plan
#   - Has [task-N] commits but not all tasks -> do
#   - All tasks have commits but no ## Verification -> check
#   - Has verification -> ship (or done if merged)

HAS_VERIFICATION=false
VERIFICATION_PASSED=""
READING_VERIFICATION=false
while IFS= read -r line; do
  if [[ "$line" =~ ^##[[:space:]]Verification ]]; then
    READING_VERIFICATION=true
    continue
  fi
  if [[ "$READING_VERIFICATION" == "true" ]]; then
    if [[ "$line" =~ ^##[[:space:]] ]]; then
      break
    fi
    # Non-empty, non-placeholder line
    STRIPPED=$(echo "$line" | tr -d '[:space:]')
    if [[ -n "$STRIPPED" ]] && ! echo "$line" | grep -qi '(Written by'; then
      HAS_VERIFICATION=true
    fi
    # Check for passed: true/false
    if [[ "$line" =~ passed:[[:space:]]*(true|false) ]]; then
      VERIFICATION_PASSED="${BASH_REMATCH[1]}"
    fi
  fi
done < "$FEATURE_FILE"

# Check if branch is already merged into main (top-level, before task completion logic).
# Must be checked first: after merge, git log merge-base..branch returns empty,
# making COMPLETED_TASKS=0 even if all tasks were done.
# Only consider "merged" if the plan has checked tasks — otherwise the branch
# just hasn't been started yet (created from main with no commits).
IS_MERGED=false
if [[ -n "$MAIN_BRANCH" ]] && [[ $TOTAL_TASKS -gt 0 ]]; then
  HAS_CHECKED_TASKS=false
  for TID in "${PLAN_TASK_IDS[@]}"; do
    if [[ "${PLAN_CHECKED[$TID]}" == "true" ]]; then
      HAS_CHECKED_TASKS=true
      break
    fi
  done
  if $HAS_CHECKED_TASKS; then
    if git merge-base --is-ancestor "$BRANCH" "$MAIN_BRANCH" 2>/dev/null; then
      IS_MERGED=true
    fi
  fi
fi

CURRENT_STEP=""
if $IS_MERGED; then
  CURRENT_STEP="done (merged)"
elif [[ $TOTAL_TASKS -eq 0 ]]; then
  CURRENT_STEP="think (no plan tasks yet)"
elif [[ $COMPLETED_TASKS -eq 0 ]]; then
  CURRENT_STEP="plan (plan exists, no tasks started)"
elif [[ $COMPLETED_TASKS -lt $TOTAL_TASKS ]]; then
  CURRENT_STEP="do ($COMPLETED_TASKS/$TOTAL_TASKS tasks completed)"
elif [[ $COMPLETED_TASKS -eq $TOTAL_TASKS ]]; then
  if $HAS_VERIFICATION; then
    if [[ "$VERIFICATION_PASSED" == "false" ]]; then
      CURRENT_STEP="do-fix (verification failed, needs fix and re-check)"
    elif [[ "$VERIFICATION_PASSED" == "true" ]]; then
      CURRENT_STEP="ship (all tasks done, verified)"
    else
      CURRENT_STEP="check (verification incomplete — no explicit passed: field)"
    fi
  else
    CURRENT_STEP="check (all $TOTAL_TASKS tasks done, needs verification)"
  fi
fi

# ---------- 5. Output report ----------

ELAPSED=$(( SECONDS - START_TIME ))

echo "========================================"
echo "  YOLO v2 Reconciliation Report"
echo "========================================"
echo ""
echo "Feature file: $FEATURE_FILE"
echo "Branch:       $BRANCH"
echo "Elapsed:      ${ELAPSED}s"
echo ""
echo "--- Current Step ---"
echo "  $CURRENT_STEP"
echo ""
echo "--- Task Status ---"
printf "  %-12s %-10s %-10s %s\n" "TASK" "FILE" "GIT" "LABEL"
printf "  %-12s %-10s %-10s %s\n" "----" "----" "---" "-----"
for TASK_ID in "${PLAN_TASK_IDS[@]}"; do
  FILE_STATE="[ ]"
  if [[ "${PLAN_CHECKED[$TASK_ID]}" == "true" ]]; then
    FILE_STATE="[x]"
  fi
  GIT_STATE="no commit"
  if [[ -n "${GIT_TASK_COMMITS[$TASK_ID]+x}" ]]; then
    GIT_STATE="${GIT_TASK_COMMITS[$TASK_ID]}"
  fi
  # Truncate label for display
  LABEL="${PLAN_LABELS[$TASK_ID]}"
  if [[ ${#LABEL} -gt 50 ]]; then
    LABEL="${LABEL:0:47}..."
  fi
  printf "  %-12s %-10s %-10s %s\n" "$TASK_ID" "$FILE_STATE" "$GIT_STATE" "$LABEL"
done

echo ""
echo "--- Drift Detection ---"
if [[ ${#DRIFT_MSGS[@]} -eq 0 && ${#ORPHAN_COMMITS[@]} -eq 0 ]]; then
  echo "  No drift detected. File matches git evidence."
else
  for MSG in "${DRIFT_MSGS[@]}"; do
    echo "  $MSG"
  done
  for MSG in "${ORPHAN_COMMITS[@]}"; do
    echo "  $MSG"
  done
  echo ""
  echo "  Total drift items: $(( ${#DRIFT_MSGS[@]} + ${#ORPHAN_COMMITS[@]} ))"
fi

# ---------- 6. Fix mode ----------

if $FIX; then
  if [[ ${#DRIFT_MSGS[@]} -eq 0 && ${#ORPHAN_COMMITS[@]} -eq 0 ]]; then
    echo ""
    echo "--- Fix Mode ---"
    echo "  No drift to fix."
  else
    echo ""
    echo "--- Fix Mode: Updating feature file ---"

    # Build the updated file content
    TMPFILE=$(mktemp "${FEATURE_FILE}.tmp.XXXXXX")
    trap 'rm -f "$TMPFILE"' EXIT INT TERM
    IN_PLAN=false

    while IFS= read -r line; do
      # Detect section boundaries
      if [[ "$line" =~ ^##[[:space:]] ]]; then
        if [[ "$line" =~ ^##[[:space:]]Plan ]]; then
          IN_PLAN=true
          echo "$line" >> "$TMPFILE"
          continue
        else
          IN_PLAN=false
          echo "$line" >> "$TMPFILE"
          continue
        fi
      fi

      if $IN_PLAN; then
        # Match task checkbox lines
        if [[ "$line" =~ ^([0-9]+)\.[[:space:]]\[([xX[:space:]])\][[:space:]]+(.*) ]]; then
          TASK_NUM="${BASH_REMATCH[1]}"
          LABEL="${BASH_REMATCH[3]}"
          TASK_ID="task-${TASK_NUM}"

          # Strip existing trailing hash from label (pattern matches extraction regex on line 100)
          CLEAN_LABEL="$LABEL"
          if [[ "$CLEAN_LABEL" =~ ^(.*[^[:space:]])?[[:space:]]*[—–-]+[[:space:]]*[0-9a-f]{7,40}$ ]]; then
            CLEAN_LABEL="${BASH_REMATCH[1]}"
          fi

          if [[ "${RECONCILED_CHECKED[$TASK_ID]}" == "true" ]]; then
            HASH="${RECONCILED_HASHES[$TASK_ID]}"
            echo "${TASK_NUM}. [x] ${CLEAN_LABEL} — ${HASH}" >> "$TMPFILE"
          else
            echo "${TASK_NUM}. [ ] ${CLEAN_LABEL}" >> "$TMPFILE"
          fi
          continue
        fi
      fi

      echo "$line" >> "$TMPFILE"
    done < "$FEATURE_FILE"

    mv "$TMPFILE" "$FEATURE_FILE"
    echo "  Feature file updated: $FEATURE_FILE"

    # Show diff summary
    echo "  Changes applied:"
    for TASK_ID in "${PLAN_TASK_IDS[@]}"; do
      OLD="${PLAN_CHECKED[$TASK_ID]}"
      NEW="${RECONCILED_CHECKED[$TASK_ID]}"
      if [[ "$OLD" != "$NEW" ]]; then
        if [[ "$NEW" == "true" ]]; then
          echo "    $TASK_ID: [ ] -> [x] (commit ${RECONCILED_HASHES[$TASK_ID]})"
        else
          echo "    $TASK_ID: [x] -> [ ] (no commit found)"
        fi
      fi
    done
  fi
fi

echo ""
echo "Done."

# Exit 2 if drift was detected and --fix was not used (programmatic drift signal)
if ! $FIX && [[ ${#DRIFT_MSGS[@]} -gt 0 || ${#ORPHAN_COMMITS[@]} -gt 0 ]]; then
  exit 2
fi
