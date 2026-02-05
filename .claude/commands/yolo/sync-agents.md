---
name: yolo:sync-agents
description: Regenerate agents from baselines, contracts, and implementations
argument-hint: '[--check|--validate|--force|--agent <name>|--diff]'
allowed-tools:
  - Read
  - Write
  - Glob
  - Grep
  - Bash
---

<objective>
Regenerate agent definitions from source files.

**Sources:**
- `agents/src/baselines/*.md` — Agent foundations with placeholders
- `agents/src/contracts/*.yaml` — Input/output schemas
- `agents/src/implementations/**/*.yaml` — Variant configs + prompts

**Output:**
- `agents/generated/*.md` — Ready-to-use agent definitions

**Subcommands:**
- `/yolo:sync-agents` — Regenerate stale agents
- `/yolo:sync-agents --check` — Show status without regenerating
- `/yolo:sync-agents --validate` — Regenerate + validate
- `/yolo:sync-agents --force` — Force regenerate all
</objective>

<execution_context>
@./.claude/yolo/agents/sync.yaml
</execution_context>

<context>
Arguments: $ARGUMENTS

Working directory: .claude/yolo/agents/
</context>

<process>

## Parse Arguments

```
--check      → Status only, no changes
--validate   → Regenerate + run validation checks
--force      → Regenerate all, ignore hashes
--agent <name> → Regenerate single agent (e.g., --agent research-thorough)
--diff       → Preview changes without writing (show what would change)
(default)    → Regenerate only stale agents
```

---

## Step 1: Discover Sources

Find all implementation files:

```bash
find .claude/yolo/agents/src/implementations -name "*.yaml" -type f
```

For each implementation file, extract:
- Contract name (parent directory or `implements` field)
- Variant name (filename without extension)

Expected implementations:
- research/thorough.yaml
- research/quick.yaml
- research/interactive.yaml
- plan/detailed.yaml
- plan/minimal.yaml
- execute/standard.yaml
- execute/fix.yaml
- verify/strict.yaml
- verify/basic.yaml
- decide/conversation.yaml

---

## Step 2: Check Status (if --check or default)

For each expected agent:

1. Check if generated file exists: `agents/generated/{contract}-{variant}.md`
2. If exists, parse header to get source hashes
3. Compare with current source file hashes
4. Determine status:
   - `up_to_date` — All hashes match
   - `stale` — Source changed since generation
   - `modified` — Generated file manually edited (hash mismatch)
   - `missing` — Generated file doesn't exist

**If --check:** Display status table and exit

```
═══════════════════════════════════════════════════════════════════
YOLO > AGENT SYNC STATUS
═══════════════════════════════════════════════════════════════════

| Agent                  | Status      | Last Generated      |
|------------------------|-------------|---------------------|
| research-thorough      | ✓ up to date | 2026-02-04 10:00   |
| research-quick         | ✓ up to date | 2026-02-04 10:00   |
| research-interactive   | ⚠ stale     | 2026-02-03 15:00   |
| plan-detailed          | ✓ up to date | 2026-02-04 10:00   |
| plan-minimal           | ✗ missing   | —                   |
| execute-standard       | ✓ up to date | 2026-02-04 10:00   |
| execute-fix            | ✓ up to date | 2026-02-04 10:00   |
| verify-strict          | ✓ up to date | 2026-02-04 10:00   |
| verify-basic           | ✓ up to date | 2026-02-04 10:00   |
| decide-conversation    | ✓ up to date | 2026-02-04 10:00   |

Summary: 8 up to date, 1 stale, 1 missing
Run /yolo:sync-agents to regenerate

═══════════════════════════════════════════════════════════════════
```

---

## Step 3: Generate Agents

For each agent that needs regeneration (stale, missing, or --force):

### 3.1 Load Sources

```yaml
# Load baseline
baseline_path: .claude/yolo/agents/src/baselines/{contract}.md
baseline_content: Read(baseline_path)

# Load contract
contract_path: .claude/yolo/agents/src/contracts/{contract}.yaml
contract_content: Read(contract_path)
contract: parse_yaml(contract_content)

# Load implementation
impl_path: .claude/yolo/agents/src/implementations/{contract}/{variant}.yaml
impl_content: Read(impl_path)
impl: parse_yaml(impl_content)
```

### 3.2 Compute Hashes

```bash
# Compute SHA256 hash of each source (first 8 chars)
baseline_hash=$(shasum -a 256 "$baseline_path" | cut -c1-8)
contract_hash=$(shasum -a 256 "$contract_path" | cut -c1-8)
impl_hash=$(shasum -a 256 "$impl_path" | cut -c1-8)
combined_hash=$(echo "$baseline_hash$contract_hash$impl_hash" | shasum -a 256 | cut -c1-16)
```

### 3.3 Format Schemas

Format contract input schema for display:

```
**Required:**
- `goal` (string): What we're trying to understand or build
- `scope` (string): Directory or area to focus on

**Optional:**
- `intake` (IntakeRef): Reference to intake materials
- `depth` (enum): shallow | medium | deep (default: medium)
```

Format contract output schema similarly.

### 3.4 Resolve Tools

Determine tools list:
```yaml
tools: []

# Always include base tools from contract
tools.add(contract.tools.base)

# Add external tools if implementation enables it
if impl.config.include_external:
  tools.add(contract.tools.external)

# Add interactive tools if implementation enables it
if impl.config.interactive:
  tools.add(contract.tools.interactive)

# Format as comma-separated list
tools_string: tools.join(", ")
```

### 3.5 Replace Placeholders

In the baseline content, replace:

| Placeholder | Value |
|-------------|-------|
| `{{VARIANT}}` | impl.variant |
| `{{DESCRIPTION}}` | impl.description |
| `{{MODEL}}` | impl.model |
| `{{TOOLS}}` | tools_string |
| `{{MAX_FILES}}` | impl.config.max_files or 20 |
| `{{MAX_TASKS}}` | impl.config.max_tasks or 5 |
| `{{INPUT_SCHEMA}}` | formatted input schema |
| `{{OUTPUT_SCHEMA}}` | formatted output schema |
| `{{IMPLEMENTATION_PROMPT}}` | `<implementation>\n${impl.prompt}\n</implementation>` |
| `{{INTERACTIVE_SECTION}}` | impl.interactive_section or "" |
| `{{PERSPECTIVES}}` | formatted perspectives (for decide) |
| `{{ROUNDS}}` | impl.config.rounds or 3 |
| `{{RUN_TESTS}}` | impl.config.run_tests or true |
| `{{CHECK_TYPES}}` | impl.config.check_types or true |
| `{{CHECK_LINT}}` | impl.config.check_lint or false |

### 3.6 Prepend Header

Add generated header at the top:

```markdown
# {contract}-{variant}
# ═══════════════════════════════════════════════════════════════════════════════
# GENERATED — Do not edit directly. Run /yolo:sync-agents to regenerate.
# ═══════════════════════════════════════════════════════════════════════════════
# Hash: {combined_hash}
# Generated: {ISO_TIMESTAMP}
# Sources:
#   src/baselines/{contract}.md ({baseline_hash})
#   src/contracts/{contract}.yaml ({contract_hash})
#   src/implementations/{contract}/{variant}.yaml ({impl_hash})
# ═══════════════════════════════════════════════════════════════════════════════

{processed_baseline_content}
```

### 3.7 Write Output

```
Write to: .claude/yolo/agents/generated/{contract}-{variant}.md
```

---

## Step 4: Validate (if --validate)

For each generated agent, run validation checks:

### Check 1: Placeholders Replaced

```bash
# Should find 0 matches
grep -E '\{\{[A-Z_]+\}\}' "$agent_file" | wc -l
```

If any found → ERROR

### Check 2: Required Sections Present

Check for:
- `<role>` section
- `<contract>` section
- `<constraints>` section
- `<output_format>` section

### Check 3: Frontmatter Valid

Parse YAML frontmatter and verify:
- `name` matches filename
- `model` is one of: opus, sonnet, haiku
- `tools` is valid list

### Check 4: Size Check

```bash
# Approximate token count (words / 0.75)
WORDS=$(wc -w < "$agent_file")
TOKENS=$((WORDS * 4 / 3))
```

- If > 3000 tokens → WARNING
- If > 4000 tokens → ERROR

### Validation Output

```
═══════════════════════════════════════════════════════════════════
YOLO > AGENT VALIDATION
═══════════════════════════════════════════════════════════════════

research-thorough.md:
  ✓ All placeholders replaced
  ✓ Required sections present
  ✓ Frontmatter valid (model: opus)
  ✓ Size: ~1,247 tokens

research-quick.md:
  ✓ All placeholders replaced
  ✓ Required sections present
  ✓ Frontmatter valid (model: haiku)
  ✓ Size: ~890 tokens

plan-detailed.md:
  ✓ All placeholders replaced
  ✓ Required sections present
  ✓ Frontmatter valid (model: opus)
  ⚠ Size: ~3,891 tokens (approaching limit)

═══════════════════════════════════════════════════════════════════
Summary: 10 valid, 0 errors, 1 warning
═══════════════════════════════════════════════════════════════════
```

---

## Step 5: Output Summary

```
═══════════════════════════════════════════════════════════════════
YOLO > AGENT SYNC COMPLETE
═══════════════════════════════════════════════════════════════════

Generated: 10 agents

  ✓ research-thorough.md    (opus)
  ✓ research-quick.md       (haiku)
  ✓ research-interactive.md (opus)
  ✓ plan-detailed.md        (opus)
  ✓ plan-minimal.md         (sonnet)
  ✓ execute-standard.md     (sonnet)
  ✓ execute-fix.md          (sonnet)
  ✓ verify-strict.md        (sonnet)
  ✓ verify-basic.md         (haiku)
  ✓ decide-conversation.md  (opus)

Location: .claude/yolo/agents/generated/

═══════════════════════════════════════════════════════════════════
```

</process>

<generation_template>
## Agent File Template

The generated agent file follows this structure:

```markdown
# {contract}-{variant}
# ═══════════════════════════════════════════════════════════════════════════════
# GENERATED — Do not edit directly. Run /yolo:sync-agents to regenerate.
# ═══════════════════════════════════════════════════════════════════════════════
# Hash: {combined_hash}
# Generated: {timestamp}
# Sources:
#   src/baselines/{contract}.md ({baseline_hash})
#   src/contracts/{contract}.yaml ({contract_hash})
#   src/implementations/{contract}/{variant}.yaml ({impl_hash})
# ═══════════════════════════════════════════════════════════════════════════════

---
name: {contract}-{variant}
description: {impl.description}
tools: {tools_list}
model: {impl.model}
---

<role>
{from baseline, with context filled in}
</role>

<contract>
## Input Schema
{formatted input schema from contract}

## Output Schema
{formatted output schema from contract}
</contract>

<constraints>
{from baseline}
</constraints>

<tools>
{from baseline}
</tools>

<implementation>
{impl.prompt}
</implementation>

{if interactive: impl.interactive_section}

<output_format>
{from baseline}
</output_format>
```
</generation_template>

<error_handling>
**Partial Failures:**
If some agents fail to generate (e.g., missing baseline or contract):
- Continue generating remaining agents
- Report failures at the end with clear error messages
- Exit with non-zero status if any failures occurred
- Suggest: "Fix source files and re-run /yolo:sync-agents"
</error_handling>

<success_criteria>
- [ ] All implementation files discovered
- [ ] Baselines and contracts loaded for each
- [ ] Placeholders replaced correctly
- [ ] Hashes computed and embedded
- [ ] Generated files written to agents/generated/
- [ ] Validation passes (if --validate)
- [ ] Status accurately reflects changes
- [ ] Partial failures handled gracefully
</success_criteria>
