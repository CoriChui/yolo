#!/usr/bin/env bash
# lib.sh — shared functions for the YOLO v2 CLI
# Source this file; do not execute directly.
set -euo pipefail

# ── slugify ─────────────────────────────────────────────────────────
# Convert arbitrary text to a kebab-case slug.
#   - lowercase
#   - only alphanumeric + hyphens
#   - collapse consecutive hyphens
#   - trim leading/trailing hyphens
#   - max 50 characters (trim at last full word-boundary hyphen if possible)
slugify() {
  local text="${1:-}"
  # Lowercase
  text="${text,,}"
  # Replace non-alphanumeric characters with hyphens
  text="$(printf '%s' "$text" | tr -cs 'a-z0-9' '-')"
  # Collapse multiple hyphens into one
  text="$(printf '%s' "$text" | sed 's/-\{2,\}/-/g')"
  # Trim leading/trailing hyphens
  text="${text#-}"
  text="${text%-}"
  # Truncate to 50 chars — trim at last hyphen to avoid partial words
  if (( ${#text} > 50 )); then
    text="${text:0:50}"
    # If the cut landed mid-word, trim back to last hyphen
    if [[ "${1,,}" != "" ]] && [[ "${text: -1}" != "-" ]]; then
      text="${text%-*}"
    fi
    text="${text%-}"
  fi
  printf '%s' "$text"
}

# ── parse_frontmatter ──────────────────────────────────────────────
# Extract a YAML frontmatter field value from a file.
# Usage: parse_frontmatter <file> <field>
# Returns the raw value (after "field: ") or empty string if not found.
parse_frontmatter() {
  local file="$1" field="$2"
  local in_frontmatter=0 line

  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" == "---" ]]; then
      if (( in_frontmatter )); then
        # End of frontmatter — stop scanning
        break
      else
        in_frontmatter=1
        continue
      fi
    fi
    if (( in_frontmatter )); then
      # Match "field: value" — value may contain colons, quotes, brackets, etc.
      if [[ "$line" =~ ^${field}:\ (.*) ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
        return 0
      fi
    fi
  done < "$file"
  # Field not found — return empty
  printf ''
}

# ── parse_plan_tasks ───────────────────────────────────────────────
# Extract task numbers from the ## Plan section.
# Matches lines like: "1. [x] ..." or "2. [ ] ..."
# Returns space-separated task numbers (e.g. "1 2 3").
parse_plan_tasks() {
  local file="$1"
  local in_plan=0 numbers=() line

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
      if [[ "$line" =~ ^([0-9]+)\.[[:space:]]+\[(x|X|\ )\] ]]; then
        numbers+=("${BASH_REMATCH[1]}")
      fi
    fi
  done < "$file"

  # Join with spaces
  printf '%s' "${numbers[*]}"
}

# ── count_plan_tasks ───────────────────────────────────────────────
# Count total tasks in the ## Plan section.
count_plan_tasks() {
  local file="$1"
  local tasks
  tasks="$(parse_plan_tasks "$file")"
  if [[ -z "$tasks" ]]; then
    printf '0'
    return
  fi
  # shellcheck disable=SC2086
  set -- $tasks
  printf '%s' "$#"
}

# ── get_checked_tasks ──────────────────────────────────────────────
# Return space-separated task numbers for checked [x] checkboxes only.
get_checked_tasks() {
  local file="$1"
  local in_plan=0 numbers=() line

  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^##[[:space:]]+Plan ]]; then
      in_plan=1
      continue
    fi
    if (( in_plan )) && [[ "$line" =~ ^##[[:space:]] ]]; then
      break
    fi
    if (( in_plan )); then
      if [[ "$line" =~ ^([0-9]+)\.[[:space:]]+\[(x|X)\] ]]; then
        numbers+=("${BASH_REMATCH[1]}")
      fi
    fi
  done < "$file"

  printf '%s' "${numbers[*]}"
}

# ── ensure_planning_dir ────────────────────────────────────────────
# Create the .planning directory tree under the given root.
# Idempotent — safe to call multiple times.
ensure_planning_dir() {
  local root="$1"
  mkdir -p "$root/.planning/features/done"
  mkdir -p "$root/.planning/decisions"
  mkdir -p "$root/.planning/debug-sessions"
}
