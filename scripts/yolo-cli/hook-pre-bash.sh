#!/usr/bin/env bash
# hook-pre-bash.sh — PreToolUse hook for Bash tool calls.
# Two responsibilities:
#   1. Block destructive git operations (force-push, reset --hard, etc.)
#   2. Block write-redirection bypasses of the Edit/Write gate when an active
#      feature is in progress and the write target is out of the plan's scope.
# Receives JSON on stdin: {"tool_name": "Bash", "tool_input": {"command": "..."}}
# Exit 0 = allow, Exit 2 = block (with reason on stderr)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

# Read the tool input JSON from stdin
INPUT=$(cat)

# Extract the command field via jq. We fail closed on parse error — a garbled
# payload could be an injection attempt. jq is a required dependency.
if ! command -v jq >/dev/null 2>&1; then
  echo "Blocked: jq is required by YOLO hooks but not installed in PATH." >&2
  exit 2
fi

if ! COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null); then
  echo "Blocked: YOLO hook failed to parse Bash tool input as JSON." >&2
  exit 2
fi

if [[ -z "$COMMAND" ]]; then
  # Valid JSON but no command — treat as no-op (e.g., empty input). Allow.
  exit 0
fi

# ── 1. Destructive git operations (original behaviour) ───────────────
BLOCKED_PATTERNS=(
  'git push'
  'git reset --hard'
  'git clean -f'
  'git checkout \.'
  'git restore \.'
  'git branch -D'
  'git push --force'
  'git push -f'
)

for pattern in "${BLOCKED_PATTERNS[@]}"; do
  if printf '%s' "$COMMAND" | grep -qE "$pattern"; then
    echo "Blocked: '$pattern' is not allowed in agent context. Ask the user to run this manually." >&2
    exit 2
  fi
done

# ── 2. Write-redirection scope gate ──────────────────────────────────
# Only applies when a feature is active. On main (no feature), trust the user.
REPO="${CLAUDE_PROJECT_DIR:-$PWD}"
SLUG="$(get_active_feature "$REPO" 2>/dev/null || true)"
if [[ -z "$SLUG" ]]; then
  exit 0
fi

FEATURE_FILE="$REPO/.planning/features/$SLUG/feature.md"
if [[ ! -f "$FEATURE_FILE" ]]; then
  exit 0
fi

# Collect candidate write targets from the command.
# Patterns handled (not exhaustive, but covers the most common bypasses):
#   - Redirections:  > path   >> path   &> path   n> path
#   - sed -i [-e...] [script] file
#   - tee [-a] file [file ...]
#   - cp src... dest   mv src... dest  (dest = last arg)
#   - git checkout [ref] -- path...
#   - git apply/restore/am -- path...
#   - patch -p<n> target
declare -a TARGETS=()

# Redirections: capture path after > or >> (handle '&>' and '1>' too).
# Avoid matching heredoc '<<' by ensuring the capture is after '>'.
while read -r match; do
  [[ -z "$match" ]] && continue
  TARGETS+=("$match")
done < <(printf '%s\n' "$COMMAND" | grep -oE '[12&]?>{1,2}[[:space:]]*[^[:space:];|&<>]+' \
  | sed -E 's/^[12&]?>{1,2}[[:space:]]*//')

# sed -i target (last token matching a plausible path)
if printf '%s' "$COMMAND" | grep -qE '(^|[[:space:]])sed([[:space:]]+-[^[:space:]]*)*[[:space:]]+-i'; then
  # Extract all non-flag tokens after 'sed -i'; last one is the file arg
  sed_part="$(printf '%s' "$COMMAND" | sed -E 's/.*sed[[:space:]]+(-[^ ]+[[:space:]]+)*-i[^ ]*[[:space:]]+//')"
  # Drop leading script if present (starts with /'\"' or 's/...')
  # Take the last whitespace-delimited token as the file target
  last_token="${sed_part##* }"
  if [[ -n "$last_token" && "$last_token" != -* ]]; then
    TARGETS+=("$last_token")
  fi
fi

# tee: next arg after 'tee' (or 'tee -a')
if printf '%s' "$COMMAND" | grep -qE '(^|[[:space:]|])tee([[:space:]]|$)'; then
  tee_rest="$(printf '%s' "$COMMAND" | sed -E 's/.*(^|[[:space:]|])tee([[:space:]]+-[a-zA-Z]+)*[[:space:]]+//')"
  for tok in $tee_rest; do
    [[ "$tok" == -* ]] && continue
    [[ "$tok" == '|'* ]] && break
    [[ "$tok" == ';'* ]] && break
    TARGETS+=("$tok")
    break
  done
fi

# cp / mv: destination is the last positional arg before redirects or pipes
for cmd_name in cp mv; do
  if printf '%s' "$COMMAND" | grep -qE "(^|[[:space:];&|])${cmd_name}([[:space:]]|$)"; then
    # Extract the segment after cp/mv up to a pipe/semicolon/redirect
    seg="$(printf '%s' "$COMMAND" | sed -E "s/.*(^|[[:space:];&|])${cmd_name}[[:space:]]+//" | sed -E 's/[|;&<>].*$//')"
    # Last word is the destination
    dest="${seg##* }"
    if [[ -n "$dest" && "$dest" != -* ]]; then
      TARGETS+=("$dest")
    fi
  fi
done

# git checkout <ref> -- <paths>  OR  git restore -- <paths>
if printf '%s' "$COMMAND" | grep -qE 'git[[:space:]]+(checkout|restore)[[:space:]].*--[[:space:]]'; then
  paths_part="$(printf '%s' "$COMMAND" | sed -E 's/.*--[[:space:]]+//')"
  for tok in $paths_part; do
    [[ "$tok" == '|'* || "$tok" == ';'* || "$tok" == '&'* ]] && break
    TARGETS+=("$tok")
  done
fi

# git apply / git am takes a patch file (patch file is READ, not a write target) — skip.

# No candidate targets → nothing to gate
if (( ${#TARGETS[@]} == 0 )); then
  exit 0
fi

# Gate each target against the plan's file scope. Any out-of-scope → block.
for t in "${TARGETS[@]}"; do
  # Strip surrounding quotes
  t="${t#\"}"; t="${t%\"}"
  t="${t#\'}"; t="${t%\'}"
  [[ -z "$t" ]] && continue
  # /dev/* and /tmp/* are not project paths — allow
  case "$t" in
    /dev/*|/tmp/*|/var/tmp/*) continue ;;
  esac
  if ! is_path_in_scope "$FEATURE_FILE" "$t"; then
    cat >&2 <<EOF
YOLO bash gate: command writes to '$t' which is not in the plan scope for feature '$SLUG'.

Command:
  $COMMAND

To proceed:
  1. Add '$t' to a task's 'files:' annotation in $FEATURE_FILE
  2. Split this change into a separate feature
  3. Set YOLO_BYPASS=1 for this shell session to temporarily disable the gate
EOF
    if [[ "${YOLO_BYPASS:-0}" == "1" ]]; then
      echo "YOLO bash gate: bypass honored (YOLO_BYPASS=1)" >&2
      exit 0
    fi
    exit 2
  fi
done

exit 0
