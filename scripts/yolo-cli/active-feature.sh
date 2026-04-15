#!/usr/bin/env bash
# active-feature.sh — print active feature slug + current phase from git state.
#
# Usage:
#   active-feature.sh [--repo <path>] [--format plain|status]
#
# Exits 1 with no output when no feature is active (branch is not feature/*).
# plain format (default): "<slug> <phase>"
# status format:           "yolo: <slug> · <phase>"  (for Claude Code status line)
#
# Phase is derived from the latest commit's YOLO-Phase trailer on the
# current branch. If no trailered commits exist yet, reports "plan" as the
# bootstrap phase (feature branch exists but has no task commits).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

REPO="."
FORMAT="plain"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      REPO="${2:-}"
      if [[ -z "$REPO" ]]; then
        echo "Error: --repo requires a path" >&2
        exit 1
      fi
      shift 2
      ;;
    --format)
      FORMAT="${2:-plain}"
      shift 2
      ;;
    -h|--help)
      sed -n '2,12p' "$0" | sed 's/^# \?//'
      exit 0
      ;;
    *)
      echo "Error: unknown argument '$1'" >&2
      exit 1
      ;;
  esac
done

case "$FORMAT" in
  plain|status) ;;
  *)
    echo "Error: --format must be 'plain' or 'status', got '$FORMAT'" >&2
    exit 1
    ;;
esac

SLUG="$(get_active_feature "$REPO" 2>/dev/null || true)"
if [[ -z "$SLUG" ]]; then
  exit 1
fi

PHASE="$(get_current_phase "$REPO" 2>/dev/null || true)"
if [[ -z "$PHASE" ]]; then
  PHASE="plan"
fi

case "$FORMAT" in
  status) printf 'yolo: %s · %s\n' "$SLUG" "$PHASE" ;;
  plain)  printf '%s %s\n' "$SLUG" "$PHASE" ;;
esac
