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

# ── audit_log ───────────────────────────────────────────────────────
# Append a tab-separated line to .planning/.audit.log recording a gate
# decision. Used by pre/post hooks on block and bypass paths to provide
# a durable, reviewable trail.
#
# Usage: audit_log <repo> <event> <hook> <feature> <target> <extra>
#   event:   block | bypass | revert
#   hook:    pre-bash | pre-write | post-bash
#   feature: active feature slug (empty if none)
#   target:  file path or command fragment
#   extra:   free-form additional context (no tabs, no newlines)
#
# Line format:
#   ISO-8601-UTC \t event \t hook \t feature \t target \t extra
#
# Creates .planning/ if missing. Silently swallows errors so failed
# logging never breaks a session — audit is best-effort.
audit_log() {
  local repo="${1:-}" event="${2:-}" hook="${3:-}" feature="${4:-}" target="${5:-}" extra="${6:-}"
  [[ -z "$repo" || -z "$event" ]] && return 0
  local logdir="$repo/.planning"
  local logfile="$logdir/.audit.log"
  [[ -d "$logdir" ]] || mkdir -p "$logdir" 2>/dev/null || return 0
  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)"
  # Strip tabs/newlines from fields to keep the format parseable.
  _strip_tabs() { printf '%s' "${1//$'\t'/ }" | tr -d '\n'; }
  {
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$ts" "$event" "$hook" \
      "$(_strip_tabs "$feature")" \
      "$(_strip_tabs "$target")" \
      "$(_strip_tabs "$extra")"
  } >> "$logfile" 2>/dev/null || true
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

# ── _normalize_path ───────────────────────────────────────────────
# Lexical path normalization — no symlink follow, no filesystem lookup.
# Relative paths are resolved against <repo_root>. '.' and '..' segments
# are collapsed. Prints absolute path on stdout, empty string on error.
# Usage: _normalize_path <path> <repo_root>
_normalize_path() {
  local p="${1:-}" repo="${2:-.}"
  [[ -z "$p" ]] && return 1
  # Ensure repo is absolute (caller should already provide absolute).
  case "$repo" in
    /*) ;;
    *) repo="$(cd "$repo" 2>/dev/null && pwd -P)" || return 1 ;;
  esac
  case "$p" in
    /*) ;;
    *) p="$repo/$p" ;;
  esac
  # Split on '/' walking a stack. Use a saved IFS so we don't leak.
  local saved_ifs="$IFS"
  local IFS='/'
  # shellcheck disable=SC2206
  local parts=($p)
  IFS="$saved_ifs"
  local -a stack=()
  local seg
  for seg in "${parts[@]}"; do
    case "$seg" in
      ''|'.') ;;
      '..') [[ ${#stack[@]} -gt 0 ]] && unset "stack[$(( ${#stack[@]} - 1 ))]" ;;
      *) stack+=("$seg") ;;
    esac
  done
  local out=""
  for seg in "${stack[@]}"; do
    out="${out}/${seg}"
  done
  [[ -z "$out" ]] && out="/"
  printf '%s' "$out"
}

# ── is_path_in_scope ───────────────────────────────────────────────
# Return 0 iff <target> is in the active plan's declared file scope.
# Usage: is_path_in_scope <feature_file> <target_path> [<repo_root>]
#
# Policy:
#   - target with no value → out of scope
#   - target resolves to a path outside the repo → out of scope
#   - target resolves under .planning/ in the repo → in scope (always)
#   - target matches (by file equality or directory prefix) one of the
#     entries under a task's 'files:' annotation → in scope
#   - otherwise → out of scope
#
# Path handling is lexical (no symlinks followed), prefix-only (not
# suffix), and glob-safe (set -f active during entry split).
is_path_in_scope() {
  local feature_file="${1:-}" target="${2:-}" repo="${3:-}"
  [[ -z "$target" ]] && return 1

  # Determine repo root.
  if [[ -z "$repo" ]]; then
    local search_dir="${feature_file:+$(dirname "$feature_file")}"
    search_dir="${search_dir:-.}"
    if ! repo="$(git -C "$search_dir" rev-parse --show-toplevel 2>/dev/null)"; then
      repo="$(cd "$search_dir" 2>/dev/null && pwd -P)" || repo="$PWD"
    fi
  fi
  if [[ ! -d "$repo" ]]; then
    return 1
  fi
  # Canonicalize repo, but use logical path (no symlink resolution) so that
  # macOS's /var → /private/var symlink doesn't force absolute targets to
  # start with /private/var while users pass /var. We use `pwd` (not -P)
  # here; symlink handling is done separately via _normalize_path.
  repo="$(cd "$repo" 2>/dev/null && pwd)" || return 1

  # Normalize target.
  local abs_target
  abs_target="$(_normalize_path "$target" "$repo")" || return 1
  [[ -z "$abs_target" ]] && return 1

  # Reject anything outside the repo root (no '..' escapes).
  case "$abs_target" in
    "$repo"|"$repo"/*) ;;
    *) return 1 ;;
  esac

  # Repo-relative path.
  local rel="${abs_target#"$repo"}"
  rel="${rel#/}"

  # .planning/ is always in scope.
  case "$rel" in
    .planning|.planning/*) return 0 ;;
  esac

  [[ -z "$feature_file" || ! -f "$feature_file" ]] && return 1

  # Walk the plan, split each 'files:' entry on commas with set -f active so
  # glob chars (*, ?) in entries don't expand against the working directory.
  local glob_was_off=1
  case $- in *f*) glob_was_off=0 ;; esac
  set -f

  local in_plan=0 line
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^##[[:space:]]+Plan ]]; then in_plan=1; continue; fi
    if (( in_plan )) && [[ "$line" =~ ^##[[:space:]] ]]; then break; fi
    (( in_plan )) || continue
    [[ "$line" == *files:* ]] || continue

    local rest="${line#*files:}"
    local saved_ifs="$IFS"
    local IFS=','
    # shellcheck disable=SC2206
    local entries=($rest)
    IFS="$saved_ifs"

    local entry
    for entry in "${entries[@]}"; do
      # Trim whitespace at both ends
      entry="${entry#"${entry%%[![:space:]]*}"}"
      entry="${entry%"${entry##*[![:space:]]}"}"
      # Strip matching surrounding quotes
      [[ "$entry" == \"*\" ]] && entry="${entry#\"}" && entry="${entry%\"}"
      [[ "$entry" == \'*\' ]] && entry="${entry#\'}" && entry="${entry%\'}"
      # Strip a single trailing period (sentence punctuation)
      entry="${entry%.}"
      [[ -z "$entry" ]] && continue

      local abs_entry entry_rel
      abs_entry="$(_normalize_path "$entry" "$repo")" || continue
      case "$abs_entry" in
        "$repo"|"$repo"/*) ;;
        *) continue ;;
      esac
      entry_rel="${abs_entry#"$repo"}"
      entry_rel="${entry_rel#/}"
      entry_rel="${entry_rel%/}"
      [[ -z "$entry_rel" ]] && continue

      if [[ "$rel" == "$entry_rel" || "$rel" == "$entry_rel"/* ]]; then
        (( glob_was_off )) && set +f
        return 0
      fi
    done
  done < "$feature_file"

  (( glob_was_off )) && set +f
  return 1
}
