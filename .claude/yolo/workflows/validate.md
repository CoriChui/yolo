<purpose>
Validate YOLO framework integrity across all layers.
Checks structural references, YAML schemas, enum consistency,
generated agent quality, and cross-file references.
Read-only by default — use --fix to auto-correct where possible.
</purpose>

<triggers>
- `/validate` - Run all validation checks
- `/validate --structure` - Check file existence and references only
- `/validate --schemas` - Validate YAML parsing and required fields only
- `/validate --consistency` - Check enum/status consistency across files only
- `/validate --agents` - Validate generated agent integrity only
- `/validate --cross-refs` - Check cross-file references only
- `/validate --fix` - Auto-fix issues where possible (e.g., regenerate agents)
</triggers>

<required_reading>
Read index.yaml to discover all referenced files.
This workflow does NOT read or modify state.yaml (no lock needed).
</required_reading>

<process>

<step name="setup">
**Initialize validation context:**

```bash
YOLO_ROOT=".claude/yolo"
ERRORS=0
WARNINGS=0
PASSES=0

# Parse flags
RUN_ALL=true
RUN_STRUCTURE=false
RUN_SCHEMAS=false
RUN_CONSISTENCY=false
RUN_AGENTS=false
RUN_CROSSREFS=false
FIX_MODE=false

# If any specific flag set, run only that
# If no flags, run all
```

**Display header:**

```
═══════════════════════════════════════════════════════════════
YOLO FRAMEWORK VALIDATION
═══════════════════════════════════════════════════════════════
```
</step>

<step name="check_structure" condition="RUN_ALL or RUN_STRUCTURE">
## Check 1: Structural Integrity

Verify all files referenced in index.yaml exist.

### 1.1 Workflow files

```bash
# Extract all workflow paths from index.yaml
WORKFLOWS=$(cat ${YOLO_ROOT}/index.yaml | grep 'workflow:' | sed 's/.*workflow: //' | tr -d '"' | sort -u)

echo "── Workflow Files ──"
for wf in $WORKFLOWS; do
  if [ -f "${YOLO_ROOT}/${wf}" ]; then
    echo "  ✓ ${wf}"
    PASSES=$((PASSES + 1))
  else
    echo "  ✗ ${wf} — MISSING"
    ERRORS=$((ERRORS + 1))
  fi
done
```

### 1.2 Spec files

```bash
echo ""
echo "── Spec Files ──"
SPECS="00-overview.md 01-intake.md 02-releases.md 03-features.md 04-state.md 05-commands.md 06-schemas.md 07-statuses.md"

for spec in $SPECS; do
  if [ -f "${YOLO_ROOT}/specs/${spec}" ]; then
    echo "  ✓ specs/${spec}"
    PASSES=$((PASSES + 1))
  else
    echo "  ✗ specs/${spec} — MISSING"
    ERRORS=$((ERRORS + 1))
  fi
done
```

### 1.3 Template files

```bash
echo ""
echo "── Template Files ──"
TEMPLATES="state.yaml release.yaml feature.yaml config.yaml manifest.yaml proposal.yaml debug.yaml do.yaml sync-config.yaml"

for tpl in $TEMPLATES; do
  if [ -f "${YOLO_ROOT}/templates/${tpl}" ]; then
    echo "  ✓ templates/${tpl}"
    PASSES=$((PASSES + 1))
  else
    echo "  ✗ templates/${tpl} — MISSING"
    ERRORS=$((ERRORS + 1))
  fi
done
```

### 1.4 Generated agent files

```bash
echo ""
echo "── Generated Agent Files ──"
AGENTS="research-thorough research-quick research-interactive plan-detailed plan-minimal execute-standard execute-fix verify-strict verify-basic decide-conversation"

for agent in $AGENTS; do
  if [ -f "${YOLO_ROOT}/agents/generated/${agent}.md" ]; then
    echo "  ✓ agents/generated/${agent}.md"
    PASSES=$((PASSES + 1))
  else
    echo "  ✗ agents/generated/${agent}.md — MISSING"
    ERRORS=$((ERRORS + 1))
  fi
done
```

### 1.5 Agent source files

```bash
echo ""
echo "── Agent Source Files ──"

# Baselines
BASELINES="research plan execute verify decide"
for bl in $BASELINES; do
  if [ -f "${YOLO_ROOT}/agents/src/baselines/${bl}.md" ]; then
    echo "  ✓ agents/src/baselines/${bl}.md"
    PASSES=$((PASSES + 1))
  else
    echo "  ✗ agents/src/baselines/${bl}.md — MISSING"
    ERRORS=$((ERRORS + 1))
  fi
done

# Contracts
for ct in $BASELINES; do
  if [ -f "${YOLO_ROOT}/agents/src/contracts/${ct}.yaml" ]; then
    echo "  ✓ agents/src/contracts/${ct}.yaml"
    PASSES=$((PASSES + 1))
  else
    echo "  ✗ agents/src/contracts/${ct}.yaml — MISSING"
    ERRORS=$((ERRORS + 1))
  fi
done

# Implementations (check each expected variant)
IMPLS="research/thorough research/quick research/interactive plan/detailed plan/minimal execute/standard execute/fix verify/strict verify/basic decide/conversation"
for impl in $IMPLS; do
  if [ -f "${YOLO_ROOT}/agents/src/implementations/${impl}.yaml" ]; then
    echo "  ✓ agents/src/implementations/${impl}.yaml"
    PASSES=$((PASSES + 1))
  else
    echo "  ✗ agents/src/implementations/${impl}.yaml — MISSING"
    ERRORS=$((ERRORS + 1))
  fi
done
```

### 1.6 Pipeline files

```bash
echo ""
echo "── Pipeline Files ──"
PIPELINES="feature-full feature-quick debug design-decision"

for pl in $PIPELINES; do
  if [ -f "${YOLO_ROOT}/orchestration/pipelines/${pl}.yaml" ]; then
    echo "  ✓ orchestration/pipelines/${pl}.yaml"
    PASSES=$((PASSES + 1))
  else
    echo "  ✗ orchestration/pipelines/${pl}.yaml — MISSING"
    ERRORS=$((ERRORS + 1))
  fi
done
```

### 1.7 Trigger files

```bash
echo ""
echo "── Trigger Files ──"
TRIGGERS="on-verification-failed on-execution-failed on-context-pressure"

for tr in $TRIGGERS; do
  if [ -f "${YOLO_ROOT}/orchestration/triggers/${tr}.yaml" ]; then
    echo "  ✓ orchestration/triggers/${tr}.yaml"
    PASSES=$((PASSES + 1))
  else
    echo "  ✗ orchestration/triggers/${tr}.yaml — MISSING"
    ERRORS=$((ERRORS + 1))
  fi
done
```

### 1.8 Profile files

```bash
echo ""
echo "── Profile Files ──"
PROFILES="quality balanced budget guided"

for pf in $PROFILES; do
  if [ -f "${YOLO_ROOT}/profiles/${pf}.yaml" ]; then
    echo "  ✓ profiles/${pf}.yaml"
    PASSES=$((PASSES + 1))
  else
    echo "  ✗ profiles/${pf}.yaml — MISSING"
    ERRORS=$((ERRORS + 1))
  fi
done
```

### 1.9 Adapter files

```bash
echo ""
echo "── Adapter Files ──"
ADAPTERS="github gitlab linear jira notion"

for ad in $ADAPTERS; do
  if [ -f "${YOLO_ROOT}/adapters/${ad}.md" ]; then
    echo "  ✓ adapters/${ad}.md"
    PASSES=$((PASSES + 1))
  else
    echo "  ✗ adapters/${ad}.md — MISSING"
    ERRORS=$((ERRORS + 1))
  fi
done
```

### 1.10 Other required files

```bash
echo ""
echo "── Other Files ──"
OTHER_FILES="index.yaml agents/sync.yaml orchestration/agent-orchestrator.md orchestration/patterns/conversation.yaml"

for of in $OTHER_FILES; do
  if [ -f "${YOLO_ROOT}/${of}" ]; then
    echo "  ✓ ${of}"
    PASSES=$((PASSES + 1))
  else
    echo "  ✗ ${of} — MISSING"
    ERRORS=$((ERRORS + 1))
  fi
done
```
</step>

<step name="check_schemas" condition="RUN_ALL or RUN_SCHEMAS">
## Check 2: Schema Validation

Verify YAML files parse correctly and have required fields.

### 2.1 Template required fields

```bash
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "SCHEMA VALIDATION"
echo "═══════════════════════════════════════════════════════════════"
```

**state.yaml template:**
Required fields: `schema_version`, `lock`, `_checksum`, `focus`, `releases`, `standalone_features`, `feature`, `session`, `metrics`

```bash
echo ""
echo "── state.yaml template ──"
REQUIRED_STATE="schema_version lock _checksum focus releases standalone_features feature session metrics"
for field in $REQUIRED_STATE; do
  if grep -q "^${field}:" "${YOLO_ROOT}/templates/state.yaml"; then
    echo "  ✓ ${field}"
    PASSES=$((PASSES + 1))
  else
    echo "  ✗ ${field} — MISSING from template"
    ERRORS=$((ERRORS + 1))
  fi
done
```

**feature.yaml template:**
Required fields: `id`, `name`, `title`, `created`, `release`, `depends_on`, `goal`, `success_criteria`, `status`, `blocked`, `tasks`, `research`

```bash
echo ""
echo "── feature.yaml template ──"
REQUIRED_FEATURE="id name title created release depends_on goal success_criteria status blocked tasks research"
for field in $REQUIRED_FEATURE; do
  if grep -q "^${field}:" "${YOLO_ROOT}/templates/feature.yaml"; then
    echo "  ✓ ${field}"
    PASSES=$((PASSES + 1))
  else
    echo "  ✗ ${field} — MISSING from template"
    ERRORS=$((ERRORS + 1))
  fi
done
```

### 2.2 Pipeline required sections

```bash
echo ""
echo "── Pipeline schemas ──"

for pl in feature-full feature-quick debug design-decision; do
  PL_FILE="${YOLO_ROOT}/orchestration/pipelines/${pl}.yaml"
  if [ ! -f "$PL_FILE" ]; then continue; fi

  ISSUES=""
  grep -q "^name:" "$PL_FILE" || ISSUES="${ISSUES} name"
  grep -q "^stages:" "$PL_FILE" || ISSUES="${ISSUES} stages"

  if [ -z "$ISSUES" ]; then
    echo "  ✓ ${pl}.yaml — has required fields"
    PASSES=$((PASSES + 1))
  else
    echo "  ✗ ${pl}.yaml — missing:${ISSUES}"
    ERRORS=$((ERRORS + 1))
  fi
done
```

### 2.3 Agent contract required fields

```bash
echo ""
echo "── Agent contracts ──"

for ct in research plan execute verify decide; do
  CT_FILE="${YOLO_ROOT}/agents/src/contracts/${ct}.yaml"
  if [ ! -f "$CT_FILE" ]; then continue; fi

  ISSUES=""
  grep -q "name:" "$CT_FILE" || ISSUES="${ISSUES} name"
  grep -q "input:" "$CT_FILE" || ISSUES="${ISSUES} input"
  grep -q "output:" "$CT_FILE" || ISSUES="${ISSUES} output"

  if [ -z "$ISSUES" ]; then
    echo "  ✓ ${ct}.yaml — has required fields"
    PASSES=$((PASSES + 1))
  else
    echo "  ✗ ${ct}.yaml — missing:${ISSUES}"
    ERRORS=$((ERRORS + 1))
  fi
done
```

### 2.4 Profile required fields

```bash
echo ""
echo "── Profile schemas ──"

for pf in quality balanced budget guided; do
  PF_FILE="${YOLO_ROOT}/profiles/${pf}.yaml"
  if [ ! -f "$PF_FILE" ]; then continue; fi

  ISSUES=""
  grep -q "name:" "$PF_FILE" || ISSUES="${ISSUES} name"
  grep -q "model:" "$PF_FILE" || ISSUES="${ISSUES} model"

  if [ -z "$ISSUES" ]; then
    echo "  ✓ ${pf}.yaml — has required fields"
    PASSES=$((PASSES + 1))
  else
    echo "  ✗ ${pf}.yaml — missing:${ISSUES}"
    ERRORS=$((ERRORS + 1))
  fi
done
```
</step>

<step name="check_consistency" condition="RUN_ALL or RUN_CONSISTENCY">
## Check 3: Enum Consistency

Verify enums and status values match across all files that reference them.

```bash
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "CONSISTENCY CHECKS"
echo "═══════════════════════════════════════════════════════════════"
```

### 3.1 Feature status enum

The canonical feature statuses are: `pending`, `researching`, `planning`, `in_progress`, `blocked`, `verifying`, `completed`, `dropped`

```bash
echo ""
echo "── Feature status enum ──"

CANONICAL_STATUSES="pending researching planning in_progress blocked verifying completed dropped"

# Check 03-features.md defines all statuses
for status in $CANONICAL_STATUSES; do
  if grep -q "$status" "${YOLO_ROOT}/specs/03-features.md"; then
    echo "  ✓ 03-features.md has '${status}'"
    PASSES=$((PASSES + 1))
  else
    echo "  ✗ 03-features.md missing '${status}'"
    ERRORS=$((ERRORS + 1))
  fi
done

# Check feature.yaml template references the enum
if grep -q "pending | researching | planning | in_progress | blocked | verifying | completed | dropped" "${YOLO_ROOT}/templates/feature.yaml"; then
  echo "  ✓ feature.yaml template has full enum in comment"
  PASSES=$((PASSES + 1))
else
  echo "  ⚠ feature.yaml template — enum comment may be incomplete"
  WARNINGS=$((WARNINGS + 1))
fi
```

### 3.2 Release status enum

Canonical: `pending`, `active`, `paused`, `completed`, `failed`, `cancelled`

```bash
echo ""
echo "── Release status enum ──"

RELEASE_STATUSES="pending active paused completed failed cancelled"

for status in $RELEASE_STATUSES; do
  if grep -q "$status" "${YOLO_ROOT}/specs/02-releases.md"; then
    echo "  ✓ 02-releases.md has '${status}'"
    PASSES=$((PASSES + 1))
  else
    echo "  ✗ 02-releases.md missing '${status}'"
    ERRORS=$((ERRORS + 1))
  fi
done
```

### 3.3 Intake source enum

Canonical source catalog (26+ types across 4 categories):
- MCP: `figma`, `notion`, `linear`, `jira`, `confluence`, `slack`, `miro`
- WebFetch: `gdocs`, `swagger`, `graphql`, `website`
- CLI: `github`, `db`
- Local: `openapi`, `postman`, `protobuf`, `graphql-schema`, `pdf`, `csv`, `sql`, `har`, `docker`, `terraform`, `envfile`
- Interactive: `manual`, `notes`

```bash
echo ""
echo "── Intake source enum ──"

INTAKE_SOURCES="figma notion linear jira confluence slack miro gdocs swagger graphql website github db openapi postman protobuf graphql-schema pdf csv sql har docker terraform envfile manual notes"

# Check across key files
SOURCE_FILES="specs/01-intake.md agents/src/contracts/research.yaml workflows/intake-capture.md"
for file in $SOURCE_FILES; do
  MISSING=""
  for src in $INTAKE_SOURCES; do
    if ! grep -q "$src" "${YOLO_ROOT}/${file}"; then
      MISSING="${MISSING} ${src}"
    fi
  done

  if [ -z "$MISSING" ]; then
    echo "  ✓ ${file} — all sources present"
    PASSES=$((PASSES + 1))
  else
    echo "  ✗ ${file} — missing:${MISSING}"
    ERRORS=$((ERRORS + 1))
  fi
done
```

### 3.4 Agent registry vs generated files

```bash
echo ""
echo "── Agent registry consistency ──"

# Every agent in registry must have a generated file
REGISTRY_AGENTS=$(grep '^\    - ' "${YOLO_ROOT}/index.yaml" | sed 's/^    - //' | head -10)
for agent in $REGISTRY_AGENTS; do
  agent_clean=$(echo "$agent" | tr -d ' ')
  if [ -f "${YOLO_ROOT}/agents/generated/${agent_clean}.md" ]; then
    echo "  ✓ Registry '${agent_clean}' has generated file"
    PASSES=$((PASSES + 1))
  else
    echo "  ✗ Registry '${agent_clean}' — no generated file"
    ERRORS=$((ERRORS + 1))
  fi
done

# Every generated file should be in registry
for gen_file in ${YOLO_ROOT}/agents/generated/*.md; do
  AGENT_NAME=$(basename "$gen_file" .md)
  if grep -q "- ${AGENT_NAME}" "${YOLO_ROOT}/index.yaml"; then
    echo "  ✓ Generated '${AGENT_NAME}' is in registry"
    PASSES=$((PASSES + 1))
  else
    echo "  ⚠ Generated '${AGENT_NAME}' — NOT in registry (orphan)"
    WARNINGS=$((WARNINGS + 1))
  fi
done
```

### 3.5 Profile names consistency

```bash
echo ""
echo "── Profile names ──"

EXPECTED_PROFILES="quality balanced budget guided"
for pf in $EXPECTED_PROFILES; do
  # Check in index.yaml profiles section
  if grep -q "${pf}:" "${YOLO_ROOT}/index.yaml"; then
    echo "  ✓ Profile '${pf}' in index.yaml"
    PASSES=$((PASSES + 1))
  else
    echo "  ✗ Profile '${pf}' missing from index.yaml"
    ERRORS=$((ERRORS + 1))
  fi

  # Check pipeline references it
  if grep -q "${pf}:" "${YOLO_ROOT}/orchestration/pipelines/feature-full.yaml"; then
    echo "  ✓ Profile '${pf}' in feature-full pipeline"
    PASSES=$((PASSES + 1))
  else
    echo "  ✗ Profile '${pf}' missing from feature-full pipeline"
    ERRORS=$((ERRORS + 1))
  fi
done
```
</step>

<step name="check_agents" condition="RUN_ALL or RUN_AGENTS">
## Check 4: Agent Integrity

Validate generated agent files are complete and correct.

```bash
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "AGENT INTEGRITY"
echo "═══════════════════════════════════════════════════════════════"
```

### 4.1 No unresolved placeholders

```bash
echo ""
echo "── Placeholder check ──"

for agent_file in ${YOLO_ROOT}/agents/generated/*.md; do
  AGENT_NAME=$(basename "$agent_file" .md)
  # Look for {{...}} patterns (excluding comments/documentation lines)
  PLACEHOLDERS=$(grep -E '\{\{[A-Z_]+\}\}' "$agent_file" 2>/dev/null | grep -v '^#' | wc -l | tr -d ' ')

  if [ "$PLACEHOLDERS" = "0" ]; then
    echo "  ✓ ${AGENT_NAME} — no placeholders"
    PASSES=$((PASSES + 1))
  else
    echo "  ✗ ${AGENT_NAME} — ${PLACEHOLDERS} unresolved placeholder(s)"
    ERRORS=$((ERRORS + 1))
  fi
done
```

### 4.2 Required sections present

Every generated agent must have: `<role>`, `<contract>`, `<constraints>`, `<output_format>`

```bash
echo ""
echo "── Required sections ──"

REQUIRED_SECTIONS="role contract constraints output_format"

for agent_file in ${YOLO_ROOT}/agents/generated/*.md; do
  AGENT_NAME=$(basename "$agent_file" .md)
  MISSING=""

  for section in $REQUIRED_SECTIONS; do
    if ! grep -q "<${section}>" "$agent_file"; then
      MISSING="${MISSING} <${section}>"
    fi
  done

  if [ -z "$MISSING" ]; then
    echo "  ✓ ${AGENT_NAME} — all sections present"
    PASSES=$((PASSES + 1))
  else
    echo "  ✗ ${AGENT_NAME} — missing:${MISSING}"
    ERRORS=$((ERRORS + 1))
  fi
done
```

### 4.3 Frontmatter validation

Each agent must have valid YAML frontmatter with `name`, `model`, `tools`.

```bash
echo ""
echo "── Frontmatter validation ──"

VALID_MODELS="opus sonnet haiku"

for agent_file in ${YOLO_ROOT}/agents/generated/*.md; do
  AGENT_NAME=$(basename "$agent_file" .md)
  ISSUES=""

  # Check name field matches filename
  FM_NAME=$(grep '^name:' "$agent_file" | head -1 | sed 's/name: //')
  if [ "$FM_NAME" != "$AGENT_NAME" ]; then
    ISSUES="${ISSUES} name-mismatch(${FM_NAME})"
  fi

  # Check model is valid
  FM_MODEL=$(grep '^model:' "$agent_file" | head -1 | sed 's/model: //')
  MODEL_VALID=false
  for vm in $VALID_MODELS; do
    if [ "$FM_MODEL" = "$vm" ]; then MODEL_VALID=true; fi
  done
  if [ "$MODEL_VALID" = false ]; then
    ISSUES="${ISSUES} invalid-model(${FM_MODEL})"
  fi

  # Check tools field exists
  if ! grep -q '^tools:' "$agent_file"; then
    ISSUES="${ISSUES} missing-tools"
  fi

  if [ -z "$ISSUES" ]; then
    echo "  ✓ ${AGENT_NAME} — frontmatter valid (model: ${FM_MODEL})"
    PASSES=$((PASSES + 1))
  else
    echo "  ✗ ${AGENT_NAME} —${ISSUES}"
    ERRORS=$((ERRORS + 1))
  fi
done
```

### 4.4 Agent size check

Agents should not exceed ~4000 tokens (~3000 words).

```bash
echo ""
echo "── Size check ──"

for agent_file in ${YOLO_ROOT}/agents/generated/*.md; do
  AGENT_NAME=$(basename "$agent_file" .md)
  WORDS=$(wc -w < "$agent_file" | tr -d ' ')
  APPROX_TOKENS=$((WORDS * 4 / 3))

  if [ "$APPROX_TOKENS" -gt 4000 ]; then
    echo "  ✗ ${AGENT_NAME} — ~${APPROX_TOKENS} tokens (exceeds 4000 limit)"
    ERRORS=$((ERRORS + 1))
  elif [ "$APPROX_TOKENS" -gt 3000 ]; then
    echo "  ⚠ ${AGENT_NAME} — ~${APPROX_TOKENS} tokens (approaching limit)"
    WARNINGS=$((WARNINGS + 1))
  else
    echo "  ✓ ${AGENT_NAME} — ~${APPROX_TOKENS} tokens"
    PASSES=$((PASSES + 1))
  fi
done
```

### 4.5 Source hash staleness

Check if generated agents are stale (source files changed since generation).

```bash
echo ""
echo "── Staleness check ──"

for agent_file in ${YOLO_ROOT}/agents/generated/*.md; do
  AGENT_NAME=$(basename "$agent_file" .md)

  # Extract source paths and hashes from header
  HEADER_HASHES=$(grep '^#   src/' "$agent_file" | sed 's/#   //')

  STALE=false
  for line in $HEADER_HASHES; do
    SRC_PATH=$(echo "$line" | cut -d'(' -f1 | tr -d ' ')
    RECORDED_HASH=$(echo "$line" | grep -o '([a-f0-9]*)' | tr -d '()')

    FULL_PATH="${YOLO_ROOT}/agents/${SRC_PATH}"
    if [ -f "$FULL_PATH" ]; then
      CURRENT_HASH=$(shasum -a 256 "$FULL_PATH" | cut -c1-8)
      if [ "$CURRENT_HASH" != "$RECORDED_HASH" ]; then
        STALE=true
      fi
    fi
  done

  if [ "$STALE" = true ]; then
    echo "  ⚠ ${AGENT_NAME} — STALE (source changed since generation)"
    WARNINGS=$((WARNINGS + 1))
  else
    echo "  ✓ ${AGENT_NAME} — up to date"
    PASSES=$((PASSES + 1))
  fi
done
```
</step>

<step name="check_cross_refs" condition="RUN_ALL or RUN_CROSSREFS">
## Check 5: Cross-Reference Integrity

Verify references between files are valid.

```bash
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "CROSS-REFERENCE CHECKS"
echo "═══════════════════════════════════════════════════════════════"
```

### 5.1 Pipeline → Contract references

Each pipeline stage must reference a valid agent contract.

```bash
echo ""
echo "── Pipeline → Contract ──"

VALID_CONTRACTS="research plan execute verify decide"

for pl_file in ${YOLO_ROOT}/orchestration/pipelines/*.yaml; do
  PL_NAME=$(basename "$pl_file" .yaml)

  # Extract contract references from stages
  CONTRACTS=$(grep 'contract:' "$pl_file" | sed 's/.*contract: //' | tr -d '"' | sort -u)

  for ct in $CONTRACTS; do
    CT_VALID=false
    for vc in $VALID_CONTRACTS; do
      if [ "$ct" = "$vc" ]; then CT_VALID=true; fi
    done

    if [ "$CT_VALID" = true ]; then
      echo "  ✓ ${PL_NAME} → contract:${ct}"
      PASSES=$((PASSES + 1))
    else
      echo "  ✗ ${PL_NAME} → contract:${ct} — INVALID"
      ERRORS=$((ERRORS + 1))
    fi
  done
done
```

### 5.2 Pipeline → Trigger references

```bash
echo ""
echo "── Pipeline → Trigger ──"

for pl_file in ${YOLO_ROOT}/orchestration/pipelines/*.yaml; do
  PL_NAME=$(basename "$pl_file" .yaml)

  # Extract trigger references
  TRIGGERS=$(grep 'trigger:' "$pl_file" | sed 's/.*trigger: //' | tr -d '"' | grep -v '^$')

  for tr in $TRIGGERS; do
    # Trigger files use "on-" prefix
    if [ -f "${YOLO_ROOT}/orchestration/triggers/on-${tr}.yaml" ] || [ -f "${YOLO_ROOT}/orchestration/triggers/${tr}.yaml" ]; then
      echo "  ✓ ${PL_NAME} → trigger:${tr}"
      PASSES=$((PASSES + 1))
    else
      echo "  ✗ ${PL_NAME} → trigger:${tr} — trigger file not found"
      ERRORS=$((ERRORS + 1))
    fi
  done
done
```

### 5.3 Workflow → Orchestrator reference

Workflows that reference `@orchestration/agent-orchestrator.md` must point to an existing file.

```bash
echo ""
echo "── Workflow → Orchestrator ──"

ORCHESTRATOR="${YOLO_ROOT}/orchestration/agent-orchestrator.md"
WF_REFS=$(grep -rl '@orchestration/agent-orchestrator.md' "${YOLO_ROOT}/workflows/" 2>/dev/null)

if [ -f "$ORCHESTRATOR" ]; then
  echo "  ✓ agent-orchestrator.md exists"
  PASSES=$((PASSES + 1))
else
  echo "  ✗ agent-orchestrator.md — MISSING (referenced by workflows)"
  ERRORS=$((ERRORS + 1))
fi

for wf in $WF_REFS; do
  WF_NAME=$(basename "$wf")
  echo "  ✓ ${WF_NAME} references orchestrator"
  PASSES=$((PASSES + 1))
done
```

### 5.4 Index.yaml command → workflow file consistency

Every command with a `workflow:` key must point to an existing file.

```bash
echo ""
echo "── Index → Workflow ──"

# Already checked in structure step, but verify no dangling refs
WORKFLOW_REFS=$(grep 'workflow:' "${YOLO_ROOT}/index.yaml" | sed 's/.*workflow: //' | tr -d '"' | sort -u)

for wf in $WORKFLOW_REFS; do
  if [ -f "${YOLO_ROOT}/${wf}" ]; then
    echo "  ✓ ${wf}"
    PASSES=$((PASSES + 1))
  else
    echo "  ✗ ${wf} — dangling reference in index.yaml"
    ERRORS=$((ERRORS + 1))
  fi
done
```

### 5.5 Spec cross-references

Check that specs reference each other correctly (e.g., 03-features.md mentions 04-state.md concepts).

```bash
echo ""
echo "── Spec cross-references ──"

# Key concept: state.yaml is mentioned in feature and release specs
if grep -q "state.yaml" "${YOLO_ROOT}/specs/03-features.md"; then
  echo "  ✓ 03-features.md references state.yaml"
  PASSES=$((PASSES + 1))
else
  echo "  ⚠ 03-features.md doesn't reference state.yaml"
  WARNINGS=$((WARNINGS + 1))
fi

# Key concept: feature lifecycle statuses match 07-statuses.md
if grep -q "pending.*researching.*planning.*in_progress" "${YOLO_ROOT}/specs/07-statuses.md"; then
  echo "  ✓ 07-statuses.md has feature lifecycle"
  PASSES=$((PASSES + 1))
else
  echo "  ⚠ 07-statuses.md may have incomplete feature lifecycle"
  WARNINGS=$((WARNINGS + 1))
fi
```
</step>

<step name="auto_fix" condition="FIX_MODE is true">
## Auto-Fix (--fix mode)

If fixable issues were found, attempt auto-correction:

**Stale agents:**
```bash
if [ "$STALE_AGENTS_FOUND" = true ]; then
  echo ""
  echo "── Auto-fixing stale agents ──"
  echo "Running /yolo:sync-agents to regenerate..."
  # Trigger: /yolo:sync-agents
fi
```

**Missing files:**
Cannot auto-fix — report what needs to be created manually.

**Consistency issues:**
Cannot auto-fix — report which files need manual enum updates.
</step>

<step name="report_summary">
## Summary Report

```
═══════════════════════════════════════════════════════════════
VALIDATION SUMMARY
═══════════════════════════════════════════════════════════════

  ✓ Passed:   ${PASSES}
  ⚠ Warnings: ${WARNINGS}
  ✗ Errors:   ${ERRORS}

${IF_ALL_PASS}
  STATUS: ALL CHECKS PASSED ✓

  Framework integrity verified across all layers.
${END_IF}

${IF_WARNINGS_ONLY}
  STATUS: PASSED WITH WARNINGS ⚠

  Warnings are non-blocking but should be addressed.
  Most common: stale agents (run /yolo:sync-agents)
${END_IF}

${IF_ERRORS}
  STATUS: FAILED ✗

  ${ERRORS} error(s) found. Fix these before using the framework.

  Common fixes:
    Missing files    → Create the file or update references
    Stale agents     → /yolo:sync-agents --force
    Enum mismatch    → Update the file with missing values
    Bad frontmatter  → Check agent name/model/tools
${END_IF}

═══════════════════════════════════════════════════════════════
```
</step>

</process>

<error_handling>
This workflow is read-only (unless --fix is used).
No state.yaml access, no lock needed.
If individual checks fail to run, skip and report as warning.
</error_handling>

<invariants>
- NEVER modifies files without --fix flag
- Does NOT require state.yaml or .planning/ to exist
- Can run before /init (validates framework, not project)
- Reports are deterministic given same file state
- Exit with summary counts (errors, warnings, passes)
</invariants>
