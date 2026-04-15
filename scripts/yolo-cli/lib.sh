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

# ── get_active_feature ─────────────────────────────────────────────
# Print the active feature slug derived from the current git branch.
# Convention: branch matching 'feature/<slug>' → prints '<slug>'.
# Branches 'main', 'master', or anything else → empty output, exit 1.
# Usage: get_active_feature [<repo_path>]
get_active_feature() {
  local repo="${1:-.}"
  local branch
  branch="$(git -C "$repo" symbolic-ref --short HEAD 2>/dev/null || true)"
  if [[ -z "$branch" ]]; then
    return 1
  fi
  if [[ "$branch" =~ ^feature/(.+)$ ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
    return 0
  fi
  return 1
}

# ── parse_trailer ──────────────────────────────────────────────────
# Extract a named trailer value from a commit message.
# Usage: parse_trailer <repo_path> <commit_ref> <trailer_name>
# Prints the value (everything after 'Name: ') or empty string if not present.
parse_trailer() {
  local repo="${1:-.}" ref="${2:-HEAD}" name="${3:-}"
  if [[ -z "$name" ]]; then
    printf ''
    return 0
  fi
  local msg
  msg="$(git -C "$repo" log -1 --format='%B' "$ref" 2>/dev/null || true)"
  if [[ -z "$msg" ]]; then
    printf ''
    return 0
  fi
  # Use interpret-trailers --parse to get only the trailer block,
  # then grep for the named trailer. Case-insensitive match per git convention.
  local trailer_line
  trailer_line="$(printf '%s\n' "$msg" | git interpret-trailers --parse 2>/dev/null | grep -i "^${name}:" | tail -1 || true)"
  if [[ -z "$trailer_line" ]]; then
    printf ''
    return 0
  fi
  # Strip "Name: " prefix
  printf '%s' "${trailer_line#*: }"
}

# ── get_current_phase ──────────────────────────────────────────────
# Derive the current phase from the latest commit's YOLO-Phase trailer
# whose YOLO-Feature trailer matches the active feature slug.
# Usage: get_current_phase [<repo_path>] [<branch>]
# Returns empty string if no matching trailer found (caller may default
# to 'plan' for feature branches without task commits yet).
get_current_phase() {
  local repo="${1:-.}" branch="${2:-HEAD}"
  local slug
  slug="$(get_active_feature "$repo" 2>/dev/null || true)"

  # Scan recent commits for a YOLO-Phase trailer. If a feature is active,
  # only accept trailers whose YOLO-Feature matches — avoids inheriting
  # phase state from a parent branch's history.
  local commit commit_slug commit_phase
  while IFS= read -r commit; do
    [[ -z "$commit" ]] && continue
    commit_phase="$(parse_trailer "$repo" "$commit" "YOLO-Phase")"
    [[ -z "$commit_phase" ]] && continue
    if [[ -n "$slug" ]]; then
      commit_slug="$(parse_trailer "$repo" "$commit" "YOLO-Feature")"
      if [[ "$commit_slug" != "$slug" ]]; then
        continue
      fi
    fi
    printf '%s' "$commit_phase"
    return 0
  done < <(git -C "$repo" log -n 50 --format='%H' --grep='^YOLO-Phase:' "$branch" 2>/dev/null || true)
  printf ''
}

# ── is_path_in_scope ───────────────────────────────────────────────
# Check whether a target path is in the active plan's declared file scope.
# Usage: is_path_in_scope <feature_file> <target_path>
# Returns 0 (true) if target is listed in any task's 'files:' annotation
# OR the target lives under .planning/ (always in scope).
# Returns 1 (false) otherwise.
# Paths are normalized to workspace-relative; comparison is suffix-match
# so absolute, relative, and './' variants all unify.
is_path_in_scope() {
  local feature_file="${1:-}" target="${2:-}"
  if [[ -z "$target" ]]; then
    return 1
  fi
  # .planning/ edits are always allowed (content layer, not code)
  case "$target" in
    */.planning/*|.planning/*|*/.planning|.planning) return 0 ;;
  esac
  if [[ -z "$feature_file" || ! -f "$feature_file" ]]; then
    return 1
  fi
  # Normalize target to basename-ish form for suffix match
  local t_norm="${target#./}"
  # Parse plan section, collect every path listed after 'files:'
  local in_plan=0 line
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^##[[:space:]]+Plan ]]; then in_plan=1; continue; fi
    if (( in_plan )) && [[ "$line" =~ ^##[[:space:]] ]]; then break; fi
    if (( in_plan )); then
      # Extract the value after 'files:' on the same line (header or sub-line)
      if [[ "$line" == *files:* ]]; then
        local rest="${line#*files:}"
        # Split on commas
        local IFS=',' entry
        for entry in $rest; do
          # Trim leading/trailing whitespace and stray punctuation
          entry="${entry#"${entry%%[![:space:]]*}"}"
          entry="${entry%"${entry##*[![:space:]]}"}"
          entry="${entry%.}"
          [[ -z "$entry" ]] && continue
          # Exact, relative-prefix, or suffix match
          if [[ "$t_norm" == "$entry" || "$t_norm" == */"$entry" || "$entry" == */"$t_norm" ]]; then
            return 0
          fi
        done
      fi
    fi
  done < "$feature_file"
  return 1
}
