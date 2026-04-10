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
source "$(dirname "$0")/lib.sh"

# ---------- argument parsing ----------

FIX=false
REPO_PATH="."
FEATURE_FILE=""
BRANCH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --fix)    FIX=true; shift ;;
    --repo)   REPO_PATH="$2"; shift 2 ;;
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

if [[ -z "$FEATURE_FILE" || -z "$BRANCH" ]]; then
  echo "Usage: reconcile.sh <feature-file> <branch-name> [--fix] [--repo <path>]" >&2
  exit 1
fi

if [[ ! -f "$FEATURE_FILE" ]]; then
  echo "Error: Feature file not found: $FEATURE_FILE" >&2
  exit 1
fi

# ---------- timing ----------
START_TIME=$(python3 -c 'import time; print(time.time())')

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
    if [[ "$line" =~ ^([0-9]+)\.[[:space:]]\[([xX[:space:]])\][[:space:]]+(.*) ]]; then
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

if [[ ${#PLAN_TASK_IDS[@]} -eq 0 ]]; then
  echo "Error: No tasks found in ## Plan section of $FEATURE_FILE" >&2
  exit 1
fi

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

# Get commits on the feature branch with [task-N] markers
declare -A GIT_TASK_COMMITS=()   # task-id -> commit hash (short)
declare -A GIT_TASK_MSGS=()      # task-id -> commit message

while IFS= read -r logline; do
  [[ -z "$logline" ]] && continue
  COMMIT_HASH="${logline%% *}"
  COMMIT_MSG="${logline#* }"

  # Extract [task-N] from the commit message
  if [[ "$COMMIT_MSG" =~ \[task-([0-9]+)\] ]]; then
    TID="task-${BASH_REMATCH[1]}"
    # If multiple commits for same task, keep the latest (first in log = most recent)
    if [[ -z "${GIT_TASK_COMMITS[$TID]+x}" ]]; then
      GIT_TASK_COMMITS["$TID"]="$COMMIT_HASH"
      GIT_TASK_MSGS["$TID"]="$COMMIT_MSG"
    fi
  fi
done < <(git log "${MERGE_BASE}..${BRANCH}" --oneline --grep='\[task-' 2>/dev/null || true)

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
while IFS= read -r line; do
  if [[ "$line" =~ ^##[[:space:]]Verification ]]; then
    # Check if there's actual content after the heading
    HAS_CONTENT=false
    READING_VERIFICATION=true
    continue
  fi
  if [[ "${READING_VERIFICATION:-false}" == "true" ]]; then
    if [[ "$line" =~ ^##[[:space:]] ]]; then
      break
    fi
    # Non-empty, non-comment line
    STRIPPED=$(echo "$line" | tr -d '[:space:]')
    if [[ -n "$STRIPPED" && "$STRIPPED" != "(Writtenbycheckstep"* ]]; then
      HAS_VERIFICATION=true
      break
    fi
  fi
done < "$FEATURE_FILE"

CURRENT_STEP=""
if [[ $COMPLETED_TASKS -eq 0 ]]; then
  # Check if there is a plan at all
  if [[ $TOTAL_TASKS -gt 0 ]]; then
    CURRENT_STEP="plan (plan exists, no tasks started)"
  else
    CURRENT_STEP="think"
  fi
elif [[ $COMPLETED_TASKS -lt $TOTAL_TASKS ]]; then
  CURRENT_STEP="do ($COMPLETED_TASKS/$TOTAL_TASKS tasks completed)"
elif [[ $COMPLETED_TASKS -eq $TOTAL_TASKS ]]; then
  if $HAS_VERIFICATION; then
    # Check if branch is merged into main
    IS_MERGED=false
    if [[ -n "$MAIN_BRANCH" ]]; then
      if git merge-base --is-ancestor "$BRANCH" "$MAIN_BRANCH" 2>/dev/null; then
        IS_MERGED=true
      fi
    fi
    if $IS_MERGED; then
      CURRENT_STEP="done (merged)"
    else
      CURRENT_STEP="ship (all tasks done, verified)"
    fi
  else
    CURRENT_STEP="check (all $TOTAL_TASKS tasks done, needs verification)"
  fi
fi

# ---------- 5. Output report ----------

END_TIME=$(python3 -c 'import time; print(time.time())')
ELAPSED=$(python3 -c "print(f'{${END_TIME} - ${START_TIME}:.3f}')")

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
    TMPFILE=$(mktemp)
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

          # Strip existing trailing hash from label
          CLEAN_LABEL="$LABEL"
          if [[ "$CLEAN_LABEL" =~ ^(.*)[[:space:]][—–-]+[[:space:]]*[0-9a-f]{7,40}$ ]]; then
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

    cp "$TMPFILE" "$FEATURE_FILE"
    rm "$TMPFILE"
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
