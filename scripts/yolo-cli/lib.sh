#!/usr/bin/env bash
# lib.sh — shared functions for the YOLO v2 CLI
# Source this file; do not execute directly.
set -euo pipefail

# ── shared constants ───────────────────────────────────────────────
# Unified skip/disable marker patterns for test integrity checks.
# Used by commit.sh (pre-commit) and verify-commit.sh (post-commit).
YOLO_SKIP_PATTERNS='\.(skip|only)\b|xit\(|xdescribe\(|@pytest\.mark\.skip|@unittest\.skip|@disabled|@Disabled|#\[ignore\]'

# Unified test file detection patterns — used by commit.sh and verify-commit.sh.
# grep -E regex pattern (for commit.sh pre-commit checks)
YOLO_TEST_FILE_GREP='(\.test\.|\.spec\.|_test\.|(^|/)test_|__tests__/|tests/)'
# git pathspec patterns (for verify-commit.sh post-commit checks)
YOLO_TEST_FILE_PATHSPECS=('*.test.*' '*.spec.*' '*_test.*' '*/test_*' 'test_*' '*/__tests__/*' '__tests__/*' 'tests/*' '*/tests/*')

# ── parse_frontmatter ──────────────────────────────────────────────
# Extract a YAML frontmatter field value from a file.
# Usage: parse_frontmatter <file> <field>
# Returns the raw value (after "field: " or "field:") or empty string if not found.
# Note: handles both "field: value" and "field:value" (YAML allows both).
parse_frontmatter() {
  local file="${1:-}" field="${2:-}"
  if [[ -z "$file" || -z "$field" ]]; then
    printf ''
    return 0
  fi
  [[ -f "$file" ]] || { printf ''; return 0; }
  local in_frontmatter=0 line line_num=0

  while IFS= read -r line || [[ -n "$line" ]]; do
    line_num=$(( line_num + 1 ))
    if [[ "$line" == "---" ]]; then
      if (( in_frontmatter )); then
        # End of frontmatter — stop scanning
        break
      else
        in_frontmatter=1
        continue
      fi
    fi
    # Safety limit: frontmatter should not exceed ~50 lines
    if (( in_frontmatter && line_num > 51 )); then
      echo "Warning: frontmatter exceeds 50-line safety limit in $file" >&2
      break
    fi
    if (( in_frontmatter )); then
      # Stop at first markdown heading (indicates body content, not frontmatter)
      if [[ "$line" =~ ^##[[:space:]] ]]; then
        break
      fi
      # Match "field: value" or "field:value" — handle optional space after colon
      if [[ "$line" == "${field}: "* ]]; then
        printf '%s' "${line#"${field}: "}"
        return 0
      elif [[ "$line" == "${field}:"* ]]; then
        local val="${line#"${field}:"}"
        # Trim leading whitespace (handles tabs or multiple spaces)
        val="${val#"${val%%[![:space:]]*}"}"
        printf '%s' "$val"
        return 0
      fi
    fi
  done < "$file"
  # Field not found — return empty
  printf ''
}

# ── emit_json ──────────────────────────────────────────────────────
# Build a JSON result object from pipe-separated warning/error strings.
# Usage: emit_json <committed:true|false> <warnings_str> <errors_str>
#
# warnings_str / errors_str format: "type:detail|type:detail|..."
#   - Empty string → empty array []
#   - type is the portion before the first ':'
#   - detail is everything after the first ':'
#
# Example:
#   emit_json true "skip_added:foo.test.ts|skip_added:bar.test.ts" ""
#   → {"committed":true,"warnings":[{"type":"skip_added","detail":"foo.test.ts"},{"type":"skip_added","detail":"bar.test.ts"}],"errors":[]}
emit_json() {
  local committed="${1:-false}"
  local warnings_str="${2:-}"
  local errors_str="${3:-}"

  # Build a JSON array string from a pipe-separated entries string.
  # Each entry has format "type:detail" (detail may contain colons).
  _build_array() {
    local entries_str="$1"
    local result=""
    if [[ -z "$entries_str" ]]; then
      printf '[]'
      return
    fi
    local IFS='|'
    local entries
    read -ra entries <<< "$entries_str"
    for entry in "${entries[@]}"; do
      local type="${entry%%:*}"
      local detail="${entry#*:}"
      if [[ -n "$result" ]]; then
        result="${result},"
      fi
      result="${result}{\"type\":\"${type}\",\"detail\":\"${detail}\"}"
    done
    printf '[%s]' "$result"
  }

  local warnings_json errors_json
  warnings_json="$(_build_array "$warnings_str")"
  errors_json="$(_build_array "$errors_str")"

  printf '{"committed":%s,"warnings":%s,"errors":%s}' \
    "$committed" "$warnings_json" "$errors_json"
}
