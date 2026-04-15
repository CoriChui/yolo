#!/usr/bin/env bash
# test-lib.sh — tests for scripts/yolo-cli/lib.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

PASS=0
FAIL=0

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "  PASS: $label"
    PASS=$(( PASS + 1 ))
  else
    echo "  FAIL: $label"
    echo "    expected: '$expected'"
    echo "    actual:   '$actual'"
    FAIL=$(( FAIL + 1 ))
  fi
}

# ── Temp workspace ──────────────────────────────────────────────────
TMPDIR_TEST="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_TEST"' EXIT

# ── parse_frontmatter ──────────────────────────────────────────────
echo "=== parse_frontmatter ==="

FEATURE_FILE="$TMPDIR_TEST/feature.yaml"
cat > "$FEATURE_FILE" <<'YAMLEOF'
---
slug: dark-mode
title: Add dark mode support
branch: feature/dark-mode
status: in-progress
test_commands: ["pnpm test"]
---
## Criteria
- Must support system preference detection

## Plan
1. [x] Create theme provider — a1b2c3d
2. [ ] Add toggle component (test: none — trivial)
3. [ ] Persist preference (test: pnpm test -- theme)
YAMLEOF

assert_eq "extract branch" \
  "feature/dark-mode" \
  "$(parse_frontmatter "$FEATURE_FILE" "branch")"

assert_eq "extract test_commands" \
  '["pnpm test"]' \
  "$(parse_frontmatter "$FEATURE_FILE" "test_commands")"

assert_eq "extract slug" \
  "dark-mode" \
  "$(parse_frontmatter "$FEATURE_FILE" "slug")"

assert_eq "extract status" \
  "in-progress" \
  "$(parse_frontmatter "$FEATURE_FILE" "status")"

assert_eq "missing field returns empty" \
  "" \
  "$(parse_frontmatter "$FEATURE_FILE" "nonexistent")"

# Edge case: file with no frontmatter delimiters
NO_FM_FILE="$TMPDIR_TEST/no-frontmatter.yaml"
cat > "$NO_FM_FILE" <<'YAMLEOF'
slug: no-frontmatter
title: No delimiters here
YAMLEOF

assert_eq "no frontmatter delimiters returns empty" \
  "" \
  "$(parse_frontmatter "$NO_FM_FILE" "slug")"

# Edge case: file with unclosed frontmatter (single ---)
UNCLOSED_FM_FILE="$TMPDIR_TEST/unclosed-fm.yaml"
cat > "$UNCLOSED_FM_FILE" <<'YAMLEOF'
---
slug: unclosed
title: Unclosed frontmatter
## Plan
1. [ ] This should not be parsed as frontmatter
YAMLEOF

assert_eq "unclosed frontmatter still extracts field" \
  "unclosed" \
  "$(parse_frontmatter "$UNCLOSED_FM_FILE" "slug")"

# Edge case: empty file
EMPTY_FILE="$TMPDIR_TEST/empty.yaml"
: > "$EMPTY_FILE"

assert_eq "empty file returns empty" \
  "" \
  "$(parse_frontmatter "$EMPTY_FILE" "slug")"

# Edge case: non-existent file
assert_eq "non-existent file returns empty" \
  "" \
  "$(parse_frontmatter "$TMPDIR_TEST/does-not-exist.yaml" "slug")"

# Edge case: field value containing colons (e.g., URL)
COLON_FILE="$TMPDIR_TEST/colon-value.yaml"
cat > "$COLON_FILE" <<'YAMLEOF'
---
url: http://example.com:8080/path
slug: colon-test
---
YAMLEOF

assert_eq "field with colon in value" \
  "http://example.com:8080/path" \
  "$(parse_frontmatter "$COLON_FILE" "url")"

# ── parse_frontmatter: 51-line safety limit ────────────────────────
echo "=== parse_frontmatter 51-line safety limit ==="

LONG_FM_FILE="$TMPDIR_TEST/long-frontmatter.yaml"
{
  echo "---"
  for i in $(seq 1 60); do
    echo "field$i: value$i"
  done
  echo "---"
} > "$LONG_FM_FILE"

assert_eq "field at line 50 is found (within limit)" \
  "value49" \
  "$(parse_frontmatter "$LONG_FM_FILE" "field49")"

assert_eq "field at line 53 is NOT found (beyond limit)" \
  "" \
  "$(parse_frontmatter "$LONG_FM_FILE" "field52")"

# ── emit_json ─────────────────────────────────────────────────────────
echo "=== emit_json ==="

assert_eq "empty warnings and errors" \
  '{"committed":true,"warnings":[],"errors":[]}' \
  "$(emit_json true "" "")"

assert_eq "single warning" \
  '{"committed":false,"warnings":[{"type":"test_count_decreased","detail":"auth.test.ts:5:3"}],"errors":[]}' \
  "$(emit_json false "test_count_decreased:auth.test.ts:5:3" "")"

assert_eq "multiple warnings pipe-separated" \
  '{"committed":true,"warnings":[{"type":"skip_added","detail":"foo.test.ts"},{"type":"skip_added","detail":"bar.test.ts"}],"errors":[]}' \
  "$(emit_json true "skip_added:foo.test.ts|skip_added:bar.test.ts" "")"

assert_eq "with errors" \
  '{"committed":false,"warnings":[],"errors":[{"type":"no_tests","detail":"missing coverage"}]}' \
  "$(emit_json false "" "no_tests:missing coverage")"

assert_eq "both warnings and errors" \
  '{"committed":false,"warnings":[{"type":"skip_added","detail":"x.test.ts"}],"errors":[{"type":"no_tests","detail":"y.test.ts"}]}' \
  "$(emit_json false "skip_added:x.test.ts" "no_tests:y.test.ts")"

# ── git helpers: setup shared repo fixture ──────────────────────────
echo ""
echo "=== git helpers (get_active_feature, parse_trailer, get_current_phase, is_path_in_scope) ==="

REPO_FIX="$TMPDIR_TEST/git-helpers-repo"
mkdir -p "$REPO_FIX"
git -C "$REPO_FIX" init -q -b main
git -C "$REPO_FIX" config user.email "test@example.com"
git -C "$REPO_FIX" config user.name "test"
echo "seed" > "$REPO_FIX/seed.txt"
git -C "$REPO_FIX" add seed.txt
git -C "$REPO_FIX" commit -q -m "seed"

# ── get_active_feature ─────────────────────────────────────────────
# On main — no active feature
actual="$(get_active_feature "$REPO_FIX" 2>/dev/null || printf '<none>')"
assert_eq "get_active_feature on main returns <none>" "<none>" "$actual"

# On feature/dark-mode — slug is 'dark-mode'
git -C "$REPO_FIX" checkout -q -b feature/dark-mode
actual="$(get_active_feature "$REPO_FIX" 2>/dev/null || printf '<none>')"
assert_eq "get_active_feature on feature/dark-mode returns slug" "dark-mode" "$actual"

# On some-other-branch — no active feature
git -C "$REPO_FIX" checkout -q -b some-other-branch
actual="$(get_active_feature "$REPO_FIX" 2>/dev/null || printf '<none>')"
assert_eq "get_active_feature on non-feature branch returns <none>" "<none>" "$actual"

git -C "$REPO_FIX" checkout -q feature/dark-mode

# ── parse_trailer ──────────────────────────────────────────────────
# No trailers — empty
actual="$(parse_trailer "$REPO_FIX" HEAD YOLO-Phase)"
assert_eq "parse_trailer missing trailer returns empty" "" "$actual"

# Add a commit with trailers
echo "content" > "$REPO_FIX/work.txt"
git -C "$REPO_FIX" add work.txt
git -C "$REPO_FIX" commit -q -m "[task-1] do work

YOLO-Feature: dark-mode
YOLO-Phase: do"

actual="$(parse_trailer "$REPO_FIX" HEAD YOLO-Feature)"
assert_eq "parse_trailer extracts YOLO-Feature" "dark-mode" "$actual"

actual="$(parse_trailer "$REPO_FIX" HEAD YOLO-Phase)"
assert_eq "parse_trailer extracts YOLO-Phase" "do" "$actual"

actual="$(parse_trailer "$REPO_FIX" HEAD Nonexistent-Trailer)"
assert_eq "parse_trailer missing field returns empty" "" "$actual"

# ── get_current_phase ──────────────────────────────────────────────
actual="$(get_current_phase "$REPO_FIX")"
assert_eq "get_current_phase returns latest trailer value" "do" "$actual"

# Add a commit with a later phase
echo "more" >> "$REPO_FIX/work.txt"
git -C "$REPO_FIX" add work.txt
git -C "$REPO_FIX" commit -q -m "[task-2] check phase work

YOLO-Feature: dark-mode
YOLO-Phase: check"

actual="$(get_current_phase "$REPO_FIX")"
assert_eq "get_current_phase returns most-recent phase after new commit" "check" "$actual"

# Commit without trailer — phase stays at last seen
echo "note" >> "$REPO_FIX/work.txt"
git -C "$REPO_FIX" add work.txt
git -C "$REPO_FIX" commit -q -m "misc tweak (no trailer)"

actual="$(get_current_phase "$REPO_FIX")"
assert_eq "get_current_phase ignores commits with no trailer" "check" "$actual"

# ── is_path_in_scope ───────────────────────────────────────────────
SCOPE_FEATURE="$TMPDIR_TEST/scope-feature.md"
cat > "$SCOPE_FEATURE" <<'FEATUREEOF'
---
branch: feature/scope-test
---

## Plan
1. [ ] Add greeter module
  - files: src/greeter.ts, src/greeter.test.ts
  - test: none

2. [ ] Wire into app entry point
  - files: src/app.ts
  - test: pnpm test
FEATUREEOF

# In-scope paths
if is_path_in_scope "$SCOPE_FEATURE" "src/greeter.ts"; then
  assert_eq "in-scope: src/greeter.ts" "pass" "pass"
else
  assert_eq "in-scope: src/greeter.ts" "pass" "fail"
fi

if is_path_in_scope "$SCOPE_FEATURE" "src/app.ts"; then
  assert_eq "in-scope: src/app.ts" "pass" "pass"
else
  assert_eq "in-scope: src/app.ts" "pass" "fail"
fi

# .planning/ always in scope
if is_path_in_scope "$SCOPE_FEATURE" ".planning/features/foo/feature.md"; then
  assert_eq "in-scope: .planning/ path" "pass" "pass"
else
  assert_eq "in-scope: .planning/ path" "pass" "fail"
fi

# Out-of-scope path
if is_path_in_scope "$SCOPE_FEATURE" "src/unrelated.ts"; then
  assert_eq "out-of-scope: src/unrelated.ts blocked" "pass" "fail"
else
  assert_eq "out-of-scope: src/unrelated.ts blocked" "pass" "pass"
fi

# Missing feature file — not in scope (unless .planning/)
if is_path_in_scope "$TMPDIR_TEST/nonexistent.md" "src/app.ts"; then
  assert_eq "no feature file + non-planning path → out-of-scope" "pass" "fail"
else
  assert_eq "no feature file + non-planning path → out-of-scope" "pass" "pass"
fi

if is_path_in_scope "" ".planning/anything.md"; then
  assert_eq "no feature file + .planning/ path → in-scope" "pass" "pass"
else
  assert_eq "no feature file + .planning/ path → in-scope" "pass" "fail"
fi

# ── Summary ─────────────────────────────────────────────────────────
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="

if (( FAIL > 0 )); then
  exit 1
fi
