#!/usr/bin/env bash
# run-tests.sh — execute test and lint commands from a feature file's YAML frontmatter.
#
# Usage: run-tests.sh <feature-file> [--repo <path>] [--tail <N>]
# Exit 0 = all pass, Exit 1 = any failure
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

# ── Argument parsing ───────────────────────────────────────────────────
FEATURE_FILE="${1:-}"
shift || true

WORKDIR="."
TAIL_LINES=200

if [[ -z "$FEATURE_FILE" ]]; then
  echo "Error: No feature file specified." >&2
  echo "Usage: run-tests.sh <feature-file> [--repo <path>] [--tail <N>]" >&2
  exit 1
fi

if [[ "$FEATURE_FILE" == --* ]]; then
  echo "Error: first argument must be a feature file path, not a flag ('$FEATURE_FILE')" >&2
  echo "Usage: run-tests.sh <feature-file> [--repo <path>] [--tail <N>]" >&2
  exit 1
fi

if [[ ! -f "$FEATURE_FILE" ]]; then
  echo "Error: Feature file not found: $FEATURE_FILE" >&2
  exit 1
fi

while (( $# > 0 )); do
  case "$1" in
    --repo)
      WORKDIR="${2:-}"
      if [[ -z "$WORKDIR" ]]; then
        echo "Error: $1 requires a path argument" >&2
        exit 1
      fi
      shift 2
      ;;
    --tail)
      TAIL_LINES="${2:-}"
      if [[ -z "$TAIL_LINES" ]]; then
        echo "Error: --tail requires a number argument" >&2
        exit 1
      fi
      if ! [[ "$TAIL_LINES" =~ ^[0-9]+$ ]]; then
        echo "Error: --tail must be a positive integer, got '$TAIL_LINES'" >&2
        exit 1
      fi
      shift 2
      ;;
    *)
      echo "Error: Unknown argument '$1'" >&2
      exit 1
      ;;
  esac
done

# ── Parse command arrays from frontmatter ──────────────────────────────
# parse_json_array: parse a simple JSON array string into newline-separated commands
# Input: '["pnpm lint", "tsc --noEmit"]'
# Output: one command per line
parse_json_array() {
  local raw="$1"

  # Strip outer brackets
  raw="${raw#\[}"
  raw="${raw%\]}"

  # Trim whitespace
  raw="$(printf '%s' "$raw" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

  # Empty after stripping brackets — no commands
  if [[ -z "$raw" ]]; then
    return 0
  fi

  # Try jq first (handles commas in quoted strings correctly)
  if command -v jq &>/dev/null; then
    printf '[%s]' "$raw" | jq -r '.[]' 2>/dev/null && return 0
  fi

  # Fallback: split on comma (does not handle commas inside quoted strings)
  local IFS=',' fragment_warnings=0
  for item in $raw; do
    # Trim whitespace
    item="$(printf '%s' "$item" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    # Strip surrounding quotes
    item="${item#\"}"
    item="${item%\"}"
    # Warn on likely malformed fragments from comma splitting
    if [[ "$item" =~ ^[[:space:]]*\" && ! "$item" =~ \"[[:space:]]*$ ]] || [[ "$item" =~ ^[[:space:]]*\' && ! "$item" =~ \'[[:space:]]*$ ]]; then
      echo "Warning: possible malformed command fragment after comma split: '$item'" >&2
      fragment_warnings=$(( fragment_warnings + 1 ))
    fi
    # Skip empty items
    if [[ -n "$item" ]]; then
      printf '%s\n' "$item"
    fi
  done
}

lint_commands_raw="$(parse_frontmatter "$FEATURE_FILE" "lint_commands")"
test_commands_raw="$(parse_frontmatter "$FEATURE_FILE" "test_commands")"

# ── Run commands ───────────────────────────────────────────────────────
OVERALL_EXIT=0

run_command() {
  local label="$1" cmd="$2"

  echo "=== $label: $cmd ==="

  local cmd_output=""
  local cmd_exit=0

  # Commands come from feature file frontmatter (developer-authored, trusted input).
  # SECURITY NOTE: eval is used because commands may include shell features (pipes, redirects).
  # Feature file frontmatter is written by the orchestrator, not by agents directly.
  set +e
  cmd_output=$(cd "$WORKDIR" && eval "$cmd" 2>&1)
  cmd_exit=$?
  set -e

  # Tail output if too large
  local line_count
  line_count=$(printf '%s\n' "$cmd_output" | wc -l | tr -d ' ')
  if (( line_count > TAIL_LINES )); then
    cmd_output=$(printf '%s\n' "$cmd_output" | tail -n "$TAIL_LINES")
    echo "[output truncated to last $TAIL_LINES lines]"
  fi

  if [[ -n "$cmd_output" ]]; then
    printf '%s\n' "$cmd_output"
  fi

  echo "=== Exit code: $cmd_exit ==="
  echo ""

  if (( cmd_exit != 0 )); then
    OVERALL_EXIT=1
  fi
}

# Run lint commands first
if [[ -n "$lint_commands_raw" ]]; then
  while IFS= read -r cmd; do
    [[ -z "$cmd" ]] && continue
    run_command "LINT" "$cmd"
  done < <(parse_json_array "$lint_commands_raw")
fi

# Then run test commands
if [[ -n "$test_commands_raw" ]]; then
  while IFS= read -r cmd; do
    [[ -z "$cmd" ]] && continue
    run_command "TEST" "$cmd"
  done < <(parse_json_array "$test_commands_raw")
fi

exit "$OVERALL_EXIT"
