#!/usr/bin/env bash
# hook-pre-write.sh — PreToolUse hook for Edit/Write/MultiEdit/NotebookEdit.
# Enforces feature-scope invariant: when a feature is active, writes outside
# its plan's declared file scope are blocked. Paths inside .planning/ are
# always allowed. When no feature is active (e.g. on main), writes pass
# through (trust user; feature discipline only applies after /yolo:start).
#
# Input (stdin JSON): { "tool_name": "...", "tool_input": { "file_path": "..." } }
# Exit 0 = allow, Exit 2 = block (reason printed to stderr)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

# Read the tool-call JSON from stdin
INPUT="$(cat)"

# jq is required — fail closed if missing so malformed JSON cannot silently
# bypass the gate. Edit/Write/MultiEdit expose the target as tool_input.file_path;
# NotebookEdit uses tool_input.notebook_path.
if ! command -v jq >/dev/null 2>&1; then
  echo "Blocked: jq is required by YOLO hooks but not installed in PATH." >&2
  exit 2
fi

if ! TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null) \
  || ! TARGET=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.notebook_path // ""' 2>/dev/null); then
  echo "Blocked: YOLO hook failed to parse Edit/Write tool input as JSON." >&2
  exit 2
fi

# No target field present — allow (nothing to gate).
if [[ -z "$TARGET" ]]; then
  exit 0
fi

# Determine the repo to check against. CLAUDE_PROJECT_DIR is the session root;
# fall back to the current working directory.
REPO="${CLAUDE_PROJECT_DIR:-$PWD}"

# Derive active feature. If none, allow the write (no gate to enforce).
SLUG="$(get_active_feature "$REPO" 2>/dev/null || true)"
if [[ -z "$SLUG" ]]; then
  exit 0
fi

# Feature file is the plan that declares scope.
FEATURE_FILE="$REPO/.planning/features/$SLUG/feature.md"
if [[ ! -f "$FEATURE_FILE" ]]; then
  # Active feature branch but no feature file — allow, with a note.
  # The reconcile workflow will surface this to the user.
  exit 0
fi

# Scope check.
if is_path_in_scope "$FEATURE_FILE" "$TARGET"; then
  exit 0
fi

# Out of scope — block.
cat >&2 <<EOF
YOLO gate: '$TARGET' is not in the plan scope for feature '$SLUG'.

To proceed, choose one:
  1. Add the path to a task's 'files:' annotation in $FEATURE_FILE
  2. Split this change into a separate feature
  3. Set YOLO_BYPASS=1 for this shell session to temporarily disable the gate

Tool: ${TOOL:-unknown}
EOF

# Respect an explicit environment override for one-off bypasses.
if [[ "${YOLO_BYPASS:-0}" == "1" ]]; then
  echo "YOLO gate: bypass honored (YOLO_BYPASS=1)" >&2
  audit_log "$REPO" "bypass" "pre-write" "$SLUG" "$TARGET" "${TOOL:-unknown}"
  exit 0
fi

audit_log "$REPO" "block" "pre-write" "$SLUG" "$TARGET" "${TOOL:-unknown}"
exit 2
