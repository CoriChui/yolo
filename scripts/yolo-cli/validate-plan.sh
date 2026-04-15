#!/usr/bin/env bash
# validate-plan.sh — plan quality gates that reject bad plans before execution.
# Usage: validate-plan.sh <feature-file> [--no-test-suite]
# Exit 0 = valid, Exit 1 = rejected (prints reasons to stderr)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

# ── Args ──────────────────────────────────────────────────────────────
NO_TEST_SUITE=0
FEATURE_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-test-suite) NO_TEST_SUITE=1; shift ;;
    -*) echo "Unknown option: $1" >&2; exit 1 ;;
    *)
      if [[ -z "$FEATURE_FILE" ]]; then
        FEATURE_FILE="$1"
      else
        echo "Unexpected argument: $1" >&2; exit 1
      fi
      shift
      ;;
  esac
done

if [[ -z "$FEATURE_FILE" ]]; then
  echo "Usage: validate-plan.sh <feature-file> [--no-test-suite]" >&2
  exit 1
fi

if [[ ! -f "$FEATURE_FILE" ]]; then
  echo "Error: file not found: $FEATURE_FILE" >&2
  exit 1
fi

# ── Parse plan section ────────────────────────────────────────────────
# Handles both single-line and multi-line plan formats:
#   Single-line: "1. [ ] Task title — description test: none files: a.ts"
#   Multi-line:
#     1. [ ] Task title — description
#       - files: a.ts, b.ts
#       - test: none (justification)
#       - depends: task-1
errors=()
task_count=0
test_none_count=0

# Per-task metadata accumulated from sub-lines
declare -a task_nums=()
declare -a task_descriptions=()
declare -a task_test_annotations=()   # "yes" | "none" | ""
declare -a task_files_lines=()        # raw files: line content

in_plan=0
current_task_idx=-1

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
    # Match task header lines: "N. [x] description" or "N. [ ] description"
    if [[ "$line" =~ ^([0-9]+)\.[[:space:]]+\[(x|X|\ )\][[:space:]]+(.*) ]]; then
      task_num="${BASH_REMATCH[1]}"
      description="${BASH_REMATCH[3]}"
      task_count=$(( task_count + 1 ))
      current_task_idx=$(( task_count - 1 ))

      task_nums+=("$task_num")
      task_descriptions+=("$description")
      task_test_annotations+=("")
      task_files_lines+=("")

      # Check header line for inline test: and files: (single-line format)
      if echo "$description" | grep -qiE '(^|[[:space:](])test:\s*none'; then
        task_test_annotations[$current_task_idx]="none"
      elif echo "$description" | grep -qi 'test:'; then
        # Extract value after test: in inline format — check if empty
        inline_test_value="$(echo "$description" | sed -n 's/.*[Tt]est:[[:space:]]*//p')"
        if [[ -z "$inline_test_value" ]]; then
          task_test_annotations[$current_task_idx]="empty"
        else
          task_test_annotations[$current_task_idx]="yes"
        fi
      fi
      if echo "$description" | grep -qE 'files:'; then
        task_files_lines[$current_task_idx]="$description"
      fi

    # Match indented sub-lines: "  - key: value"
    elif (( current_task_idx >= 0 )) && [[ "$line" =~ ^[[:space:]]+-[[:space:]]+(.*) ]]; then
      subline="${BASH_REMATCH[1]}"

      # test: annotation on sub-line
      if echo "$subline" | grep -qiE '^test:\s*none'; then
        task_test_annotations[$current_task_idx]="none"
      elif echo "$subline" | grep -qi '^test:'; then
        # Check for empty test: value (no command after "test:")
        test_value="$(echo "$subline" | sed 's/^test:[[:space:]]*//')"
        if [[ -z "$test_value" ]]; then
          task_test_annotations[$current_task_idx]="empty"
        else
          task_test_annotations[$current_task_idx]="yes"
        fi
      fi

      # files: annotation on sub-line
      if echo "$subline" | grep -qi '^files:'; then
        task_files_lines[$current_task_idx]="$subline"
      fi
    fi
  fi
done < "$FEATURE_FILE"

# ── Validate parsed tasks ────────────────────────────────────────────
for (( i = 0; i < task_count; i++ )); do
  task_num="${task_nums[$i]}"
  description="${task_descriptions[$i]}"
  test_ann="${task_test_annotations[$i]}"
  files_line="${task_files_lines[$i]}"

  # Count test: none tasks
  if [[ "$test_ann" == "none" ]]; then
    test_none_count=$(( test_none_count + 1 ))
  fi

  # Check for directory paths in files list (paths ending with /)
  if [[ -n "$files_line" ]]; then
    if echo "$files_line" | sed 's/^[^:]*://' | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -qE '[a-zA-Z0-9]/$'; then
      errors+=("Task $task_num: files list contains a directory path — use specific file paths")
    fi
  fi

  # Check description word count (strip parenthesized annotations before counting)
  clean_description="$(echo "$description" | sed 's/([^)]*test:[^)]*)//g; s/([^)]*files:[^)]*)//g')"
  word_count=$(echo "$clean_description" | wc -w | tr -d ' ')
  if (( word_count < 20 )); then
    errors+=("Task $task_num: description too short ($word_count words, minimum 20)")
  fi
done

# ── Quality gates ─────────────────────────────────────────────────────

# Gate 1: No empty plan
if (( ! in_plan )); then
  errors+=("No ## Plan section found — must have a Plan section with at least 2 tasks")
elif (( task_count == 0 )); then
  errors+=("Plan section exists but contains no tasks — must have at least 2 tasks")
fi

# Gate 2: Task count bounds
if (( task_count == 1 )); then
  errors+=("Only 1 task — minimum is 2 (if the feature is truly trivial, combine into a single commit outside the plan workflow)")
elif (( task_count > 12 )); then
  errors+=("Too many tasks ($task_count) — maximum is 12, split feature into smaller pieces")
fi

# Gate 3: >=50% test coverage rejection (only if we have tasks and a test suite exists)
# Missing test: annotations count the same as test: none — both fail the gate.
if (( task_count > 0 && NO_TEST_SUITE == 0 )); then
  missing_test_count=0
  for (( gi = 0; gi < task_count; gi++ )); do
    if [[ -z "${task_test_annotations[$gi]}" ]]; then
      missing_test_count=$(( missing_test_count + 1 ))
    fi
  done
  untested_count=$test_none_count
  if (( untested_count * 2 > task_count )); then
    errors+=("Too many tasks with test:none ($untested_count of $task_count) — TDD requires most tasks to have tests (use --no-test-suite to skip)")
  fi
fi

# Gate 4: Every task should have a test: annotation (warning, not error)
# Gate 5: Reject tasks with empty test: value (no command and no "none" justification)
warnings=()
if (( task_count > 0 && NO_TEST_SUITE == 0 )); then
  for (( i = 0; i < task_count; i++ )); do
    task_num="${task_nums[$i]}"
    test_ann="${task_test_annotations[$i]}"

    if [[ -z "$test_ann" ]]; then
      warnings+=("Task $task_num: missing test: annotation (add 'test: <command>' or 'test: none')")
    elif [[ "$test_ann" == "empty" ]]; then
      errors+=("Task $task_num: empty test: annotation — specify a test command or 'test: none (justification)'")
    fi
  done
fi

if (( ${#warnings[@]} > 0 )); then
  echo "Plan validation warnings (${#warnings[@]}):" >&2
  for w in "${warnings[@]}"; do
    echo "  - $w" >&2
  done
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
