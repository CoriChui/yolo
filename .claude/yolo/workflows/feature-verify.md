<purpose>
Verify that a feature achieved its goal through goal-backward analysis.
Checks that success criteria from feature.yaml are met in the actual codebase.
Supports both release-scoped and standalone features.
</purpose>

<triggers>
- `/feature verify <feature-id>` - Verify specific feature
- `/feature verify` - Verify current executed feature
</triggers>

<core_principle>
**Task completion ≠ Goal achievement**

A feature can have all tasks "done" but still fail its goal. Verification
works backwards from the goal to check what must be TRUE, EXIST, and WIRED.
</core_principle>

<process>

<step name="load_verification_context">
Load all context needed for verification:

```bash
FEATURE_ID=$(cat .planning/state.yaml | yq '.feature.id')
FEATURE_RELEASE=$(cat .planning/state.yaml | yq '.feature.release')

# Determine feature directory based on release status
if [ "$FEATURE_RELEASE" != "null" ] && [ -n "$FEATURE_RELEASE" ]; then
  # Release-scoped feature
  FEATURE_DIR=$(ls -d "releases/${FEATURE_RELEASE}/features/${FEATURE_ID}-"* 2>/dev/null | head -1)
else
  # Standalone feature
  FEATURE_DIR="features/${FEATURE_ID}"
fi

# Load feature definition
FEATURE_YAML=$(cat "${FEATURE_DIR}/feature.yaml")
GOAL=$(echo "$FEATURE_YAML" | yq '.goal')
SUCCESS_CRITERIA=$(echo "$FEATURE_YAML" | yq '.success_criteria[]')
FEATURE_TITLE=$(echo "$FEATURE_YAML" | yq '.title')

# Load summary (what was claimed)
SUMMARY=$(cat "${FEATURE_DIR}/summary.md")
```
</step>

<step name="set_verifying_status">
Update state.yaml to reflect verification phase on entry (WF-018, matching pipeline on_start):

```yaml
feature:
  status: "verifying"
```
</step>

<step name="verify">
# Load orchestrator
@orchestration/agent-orchestrator.md

# Derive criteria from feature.yaml
# WF-014: Feature-level success_criteria is the canonical source (from user perspective per contract)
criteria: ${SUCCESS_CRITERIA from feature.yaml}

# Collect files from summary
files: ${FILES from summary.md}

# Spawn verify agent
verify_result: spawn_agent_with_profile(
  contract: "verify",
  input:
    criteria: ${criteria}
    files: ${files}
    run_tests: true
    strict: ${PROFILE == "quality"}    # WF-025: strict mode is profile-dependent; pipeline should be updated to match
  profile: "${PROFILE:-balanced}"
)

# Handle result
if verify_result.passed:
  # Update state
  Update state.yaml: feature.status = "completed"   # WF-015: verified -> completed

  # Write verification.md from agent output
  Write "${FEATURE_DIR}/verification.md":
    Convert verify_result to markdown format
    Include: results, issues, test_results, human_verification_items

else:
  # Trigger verification failure handler
  trigger: on-verification-failed
  context:
    issues: verify_result.issues
    results: verify_result.results

  # The trigger will:
  # 1. Classify issues (fixable/blocked/design)
  # 2. Spawn execute-fix for fixable issues
  # 3. Re-run verification
  # 4. After 2 retries, pause for human
</step>

<step name="determine_status">
Determine overall verification status from verify agent result:

**Using verify_result.passed:**
```
if verify_result.passed:
  STATUS = "passed"
  feature.status = "completed"       # WF-015: passed -> completed for feature-complete to handle
elif verify_result.human_verification_required:
  STATUS = "human_needed"
  feature.status = "verifying"       # Stay in verifying until human confirms
else:
  STATUS = "gaps_found"
  feature.status = "in_progress"     # WF-015: gaps_found -> in_progress (per spec: verifying->in_progress on failure)
```

**Status definitions:**
- **passed**: verify_result.passed == true, all criteria met -> feature status `completed`
- **gaps_found**: verify_result.passed == false, issues found -> feature status `in_progress`
- **human_needed**: Automated checks pass but human verification items pending -> feature status `verifying`

**Score from agent (WF-017):**
```
# Derive score from contract output
VERIFIED = verify_result.results.filter(r => r.passed).length
TOTAL = verify_result.results.length
score = VERIFIED / TOTAL
```
</step>

<step name="create_verification_report">
Convert verify agent output to verification.md format:

**Input from verify_result (WF-016: simplified contract output structure):**
```yaml
verify_result:
  passed: boolean
  results:                           # Flat array with {criterion, passed, evidence}
    - criterion: string
      passed: boolean
      evidence: string
  issues:
    - {file, line, pattern, severity}
  test_results:
    passed: boolean
    summary: string
```

**Convert to markdown format (WF-016: simplified to match contract output):**
```markdown
# Feature: ${FEATURE_ID} - ${FEATURE_TITLE}

## Verification Report

**Status:** ${STATUS}
**Score:** ${VERIFIED}/${TOTAL} criteria passed
${IF_RELEASE}**Release:** ${FEATURE_RELEASE}${ELSE}**Type:** Standalone${END_IF}

## Goal

${GOAL_FROM_FEATURE_YAML}

## Criteria Results

| Criterion | Passed | Evidence |
|-----------|--------|----------|
${FOR result IN verify_result.results}
| ${result.criterion} | ${result.passed} | ${result.evidence} |
${END_FOR}

## Anti-Patterns Found

| File | Line | Pattern | Severity |
|------|------|---------|----------|
${FOR issue IN verify_result.issues}
| ${issue.file} | ${issue.line} | ${issue.pattern} | ${issue.severity} |
${END_FOR}

## Test Results

**Passed:** ${verify_result.test_results.passed}
${verify_result.test_results.summary}

## Gaps Summary

${IF verify_result.issues.filter(i => i.severity == "blocker").length > 0}
### Critical Gaps (blocking goal)
${FOR gap IN verify_result.issues.filter(i => i.severity == "blocker")}
- ${gap.pattern} in ${gap.file}:${gap.line}
${END_FOR}

### Non-Critical Gaps (warnings)
${FOR gap IN verify_result.issues.filter(i => i.severity == "warning")}
- ${gap.pattern} in ${gap.file}:${gap.line}
${END_FOR}
${ELSE}
No gaps found.
${END_IF}

## Verification Metadata

- Verified at: ${TIMESTAMP}
- Feature location: ${FEATURE_DIR}
- Approach: goal-backward analysis via verify agent
- Profile: ${PROFILE:-balanced}
```

Write to `${FEATURE_DIR}/verification.md`.
</step>

<step name="acquire_state_lock_verify">
Acquire state lock (set lock.held_by, lock.acquired_at, lock.expires_at in state.yaml):

```yaml
lock:
  held_by: feature-verify
  acquired_at: ${TIMESTAMP}
  expires_at: ${TIMESTAMP + 60s}
```
</step>

<step name="update_state">
Update state.yaml based on verification result:

```yaml
feature:
  id: ${FEATURE_ID}
  release: ${FEATURE_RELEASE}    # null if standalone
  status: ${IF_PASSED: "completed" ELIF_HUMAN_NEEDED: "verifying" ELSE: "in_progress"}  # WF-015
  verified_at: ${TIMESTAMP}
  verification_score: "${VERIFIED}/${TOTAL}"

session:
  last_activity: ${TIMESTAMP}
  last_action: "Verified feature ${FEATURE_ID}"
  last_error: null                   # XC-003: Clear last_error on success

  resume:
    context: |
      Feature ${FEATURE_ID} verification: ${STATUS}.
      ${IF_RELEASE}Release: ${FEATURE_RELEASE}.${END_IF}
      ${IF_STANDALONE}Standalone feature.${END_IF}
      Score: ${VERIFIED}/${TOTAL}.
      ${NEXT_ACTION_HINT}

updated_at: ${TIMESTAMP}
updated_by: feature-verify
```

Compute and set `_checksum` on state.yaml (XC-002).
</step>

<step name="release_state_lock_verify">
Release state lock (clear lock fields in state.yaml):

```yaml
lock:
  held_by: null
  acquired_at: null
  expires_at: null
```
</step>

<step name="commit_verification">
Commit verification artifacts (WF-023):

```bash
git add "${FEATURE_DIR}/verification.md" .planning/state.yaml
git commit -m "docs(${FEATURE_ID}): add verification report

Score: ${VERIFIED}/${TOTAL} criteria passed
Status: ${STATUS}
"
```
</step>

<step name="report_results">
Report verification results:

**If passed:**
```
═══════════════════════════════════════════════════════════════
FEATURE VERIFIED: ${FEATURE_ID}
═══════════════════════════════════════════════════════════════

Feature:  ${FEATURE_TITLE}
${IF_RELEASE}Release:  ${FEATURE_RELEASE}${END_IF}
${IF_STANDALONE}Type:     Standalone${END_IF}
Score:    ${VERIFIED}/${TOTAL} must-haves verified
Report:   ${FEATURE_DIR}/verification.md

All automated checks passed.

${IF_HUMAN_NEEDED}
Human verification items:
  1. ${ITEM_1}
  2. ${ITEM_2}

Please test manually, then continue.
${END_IF}

───────────────────────────────────────────────────────────────
NEXT STEPS:
  /feature complete  — Mark feature complete
═══════════════════════════════════════════════════════════════
```

**If gaps_found:**
```
═══════════════════════════════════════════════════════════════
FEATURE GAPS FOUND: ${FEATURE_ID}
═══════════════════════════════════════════════════════════════

Feature:  ${FEATURE_TITLE}
${IF_RELEASE}Release:  ${FEATURE_RELEASE}${END_IF}
${IF_STANDALONE}Type:     Standalone${END_IF}
Score:    ${VERIFIED}/${TOTAL} must-haves verified
Report:   ${FEATURE_DIR}/verification.md

Critical gaps:
  - ${GAP_1}
  - ${GAP_2}

───────────────────────────────────────────────────────────────
NEXT STEPS:
  /feature execute --gaps  — Execute gap closure
  cat ${FEATURE_DIR}/verification.md  — See full report
═══════════════════════════════════════════════════════════════
```
</step>

</process>

<error_handling>

On any failure path, record `session.last_error` in state.yaml with the error details before exiting (XC-003).

**Feature not executed:**
```
Feature has not been executed yet.

Feature: ${FEATURE_ID}
Location: ${FEATURE_DIR}

Run /feature execute first, then verify.
```

**No summary.md:**
```
No summary.md found for this feature.

Feature: ${FEATURE_ID}
Location: ${FEATURE_DIR}

Feature execution may have failed. Check status.
```

</error_handling>

<invariants>
- Verification checks codebase, not just claims
- Goal-backward analysis ensures goal achievement
- Human verification items clearly flagged
- Gaps documented with evidence
- verification.md provides audit trail
- Feature directory path depends on release vs standalone status
</invariants>
