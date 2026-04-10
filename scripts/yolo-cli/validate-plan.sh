#!/usr/bin/env bash
# validate-plan.sh — plan quality gates that reject bad plans before execution.
# Usage: validate-plan.sh <feature-file>
# Exit 0 = valid, Exit 1 = rejected (prints reasons to stderr)
set -euo pipefail

source "$(dirname "$0")/lib.sh"

# ── Args ──────────────────────────────────────────────────────────────
if [[ $# -lt 1 ]]; then
  echo "Usage: validate-plan.sh <feature-file>" >&2
  exit 1
fi

FEATURE_FILE="$1"

if [[ ! -f "$FEATURE_FILE" ]]; then
  echo "Error: file not found: $FEATURE_FILE" >&2
  exit 1
fi

# ── Parse plan section ────────────────────────────────────────────────
errors=()
task_count=0
test_none_count=0

in_plan=0
while IFS= read -r line || [[ -n "$line" ]]; do
  # Detect start of Plan section
  if [[ "$line" =~ ^##[[:space:]]+Plan ]]; then
    in_plan=1
    continue
  fi
  # Detect start of any other section — stop
  if (( in_plan )) && [[ "$line" =~ ^##[[:space:]] ]]; then
    break
  fi
  if (( in_plan )); then
    # Match task lines: "N. [x] description" or "N. [ ] description"
    if [[ "$line" =~ ^([0-9]+)\.[[:space:]]+\[(x|X|\ )\][[:space:]]+(.*) ]]; then
      task_num="${BASH_REMATCH[1]}"
      description="${BASH_REMATCH[3]}"
      task_count=$(( task_count + 1 ))

      # Check for test: none (case-insensitive)
      if echo "$description" | grep -qi '(test: none'; then
        test_none_count=$(( test_none_count + 1 ))
      fi

      # Check description word count
      word_count=$(echo "$description" | wc -w | tr -d ' ')
      if (( word_count < 20 )); then
        errors+=("Task $task_num: description too short ($word_count words, minimum 20)")
      fi
    fi
  fi
done < "$FEATURE_FILE"

# ── Quality gates ─────────────────────────────────────────────────────

# Gate 1: No empty plan
if (( ! in_plan )) || (( task_count == 0 )); then
  errors+=("Plan section missing or empty — must have at least 1 task")
fi

# Gate 2: Task count bounds (only check upper bound if we have tasks)
if (( task_count > 12 )); then
  errors+=("Too many tasks ($task_count) — maximum is 12, split feature into smaller pieces")
fi

# Gate 3: >50% test:none rejection (only if we have tasks)
if (( task_count > 0 )); then
  # More than half marked test:none
  threshold=$(( task_count / 2 ))
  if (( task_count % 2 == 0 )); then
    # For even counts, >50% means strictly more than half
    if (( test_none_count > threshold )); then
      errors+=("Too many tasks with test: none ($test_none_count of $task_count) — TDD requires most tasks to have tests")
    fi
  else
    # For odd counts, >50% means more than floor(count/2)
    if (( test_none_count > threshold )); then
      errors+=("Too many tasks with test: none ($test_none_count of $task_count) — TDD requires most tasks to have tests")
    fi
  fi
fi

# ── Report ────────────────────────────────────────────────────────────
if (( ${#errors[@]} > 0 )); then
  echo "Plan validation FAILED (${#errors[@]} error(s)):" >&2
  for err in "${errors[@]}"; do
    echo "  - $err" >&2
  done
  exit 1
fi

echo "Plan validation passed: $task_count task(s), $test_none_count with test:none"
exit 0
