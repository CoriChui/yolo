# Agent Orchestrator
# ═══════════════════════════════════════════════════════════════════════════════
# Central agent management for YOLO workflows
# All agent spawning goes through this orchestrator
# ═══════════════════════════════════════════════════════════════════════════════

<purpose>
Central agent management for YOLO workflows.
All agent spawning goes through this orchestrator.
Provides consistent agent loading, validation, and error handling.
</purpose>

---

## Agent Registry

Location: `.claude/yolo/agents/generated/`

| Agent | Contract | Model | Description |
|-------|----------|-------|-------------|
| research-thorough | research | opus | Deep codebase + intake exploration |
| research-quick | research | haiku | Fast surface scan |
| research-interactive | research | opus | User-guided with questions |
| plan-detailed | plan | opus | Comprehensive task breakdown |
| plan-minimal | plan | sonnet | Quick task list |
| execute-standard | execute | sonnet | Normal task execution |
| execute-fix | execute | sonnet | Fix verification issues |
| verify-strict | verify | opus | Thorough verification + tests |
| verify-basic | verify | haiku | Quick sanity check |
| decide-conversation | decide | opus | Multi-perspective design decision |

---

<function name="spawn_agent">
## spawn_agent(agent_name, input, options?)

Spawns an agent and returns its output.

### Parameters

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| agent_name | string | yes | Agent to spawn (e.g., "research-thorough") |
| input | object | yes | Input matching agent's contract |
| options.timeout | number | no | Max execution time (ms) |
| options.on_progress | function | no | Callback for progress updates |

### Process

```yaml
1. Resolve agent path:
   agent_path: .claude/yolo/agents/generated/${agent_name}.md

   If not exists:
     Error: "Agent '${agent_name}' not found. Run /yolo:sync-agents"

2. Load agent definition:
   content: Read(agent_path)

   Parse frontmatter:
     name: string
     description: string
     tools: list
     model: string

   Parse sections:
     role: <role>...</role>
     contract: <contract>...</contract>
     constraints: <constraints>...</constraints>
     output_format: <output_format>...</output_format>

3. Load contract:
   contract_name: agent_name.split("-")[0]  # e.g., "research" from "research-thorough"
   contract_path: .claude/yolo/agents/src/contracts/${contract_name}.yaml

   contract: parse_yaml(Read(contract_path))

4. Validate input:
   For each field in contract.input.required:
     If field not in input:
       Error: "Missing required input field: ${field}"

   For each field in input:
     If field not in contract.input.required AND field not in contract.input.optional:
       Warning: "Unknown input field: ${field}"

5. Construct prompt:
   prompt: |
     ${parsed.role}

     ════════════════════════════════════════════════════════════════════
     YOUR TASK
     ════════════════════════════════════════════════════════════════════

     ${format_input(input, contract.input)}

     ${parsed.constraints}

     ════════════════════════════════════════════════════════════════════
     OUTPUT REQUIREMENTS
     ════════════════════════════════════════════════════════════════════

     ${parsed.output_format}

     Return your output as structured YAML at the end of your response.

6. Spawn agent:
   result: Task(
     description: "${agent_name}: ${input.goal || input.task?.title || 'execute'}",
     prompt: constructed_prompt,
     subagent_type: "general-purpose",
     model: parsed.frontmatter.model
   )

7. Parse output:
   Extract YAML block from result
   Parse into structured object

8. Validate output:
   For each field in contract.output.required:
     If field not in result:
       Error: "Agent output missing required field: ${field}"

9. Return result
```

### Example Usage

```yaml
# In a workflow:

research_result: spawn_agent(
  agent_name: "research-thorough",
  input:
    goal: "Understand authentication system"
    scope: "src/auth/"
    intake:
      version: "mvp-v1"
      path: ".planning/releases/2026-02-04-mvp/intake/mvp-v1"  # .planning/ is the on-disk root prepended by the workflow
    release_context:
      release_id: "2026-02-04-mvp"
      release_goal: "Build MVP authentication and core features"
)

# research_result contains:
#   findings: "..."
#   relevant_files: [...]
#   patterns: [...]
#   intake_insights: [...]
#   gaps: [...]
```
</function>

---

<function name="spawn_agent_with_profile">
## spawn_agent_with_profile(contract, input, profile, options?)

Spawns an agent using profile-based implementation selection.

### Parameters

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| contract | string | yes | Contract name (research, plan, execute, verify, decide) |
| input | object | yes | Input matching contract |
| profile | string | yes | Profile name (quality, balanced, budget, guided) |
| options | object | no | Additional options |

### Process

```yaml
1. Load profile:
   profile_path: .claude/yolo/profiles/${profile}.yaml
   profile_config: parse_yaml(Read(profile_path))

2. Resolve implementation:
   implementation: profile_config.implementations[contract]
   # e.g., profile=balanced, contract=research → implementation=thorough

   If implementation is null or 'skip':
     return { skipped: true, reason: "Profile ${profile} skips ${contract}" }

3. Construct agent name:
   agent_name: "${contract}-${implementation}"
   # e.g., "research-thorough"

4. Apply profile overrides:
   If profile_config.models[contract]:
     options.model_override: profile_config.models[contract]

   If profile_config.behavior[contract]:
     Merge into input where applicable

5. Spawn agent:
   return spawn_agent(agent_name, input, options)
```

### Example Usage

```yaml
# Using profile-based selection:

research_result: spawn_agent_with_profile(
  contract: "research",
  input:
    goal: "Understand billing system"
    scope: "src/billing/"
  profile: "balanced"
)

# Resolves to: spawn_agent("research-thorough", input)
# Because balanced.implementations.research = "thorough"
```
</function>

---

<function name="spawn_agent_with_retry">
## spawn_agent_with_retry(agent_name, input, options?)

Spawns agent with automatic retry on failure.

### Additional Options

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| options.max_retries | number | 2 | Max retry attempts |
| options.retry_delay_ms | number | 1000 | Delay between retries |
| options.on_retry | function | null | Callback on retry |
| options.retry_on | list | [timeout, agent_error] | Error types to retry |

### Process

```yaml
attempt: 0

while attempt <= max_retries:
  try:
    result: spawn_agent(agent_name, input, options)
    return result

  catch error:
    attempt++

    If error.type not in options.retry_on:
      throw error  # Don't retry validation errors, etc.

    If attempt > max_retries:
      throw error

    If options.on_retry:
      options.on_retry(error, attempt)

    wait(retry_delay_ms)
```
</function>

---

<error_handling>
## Error Handling

### Error Classification

| Error Type | Description | Retryable? |
|------------|-------------|------------|
| agent_not_found | Agent file doesn't exist | No |
| validation_error | Input doesn't match contract | No |
| output_error | Output doesn't match contract | No |
| agent_error | Agent threw error during execution | Yes |
| timeout_error | Agent exceeded time limit | Yes |
| context_error | Agent ran out of context | Yes (with reduced scope) |

### Error Response

```yaml
On error:
  1. Classify error type

  2. Check triggers:
     For each trigger in orchestration/triggers/:
       If trigger.condition matches error:
         Execute trigger.reaction
         Return trigger result

  3. If no trigger matches:
     Return error to calling workflow:
       error:
         type: ${error_type}
         message: ${error_message}
         agent: ${agent_name}
         recoverable: ${is_retryable}
         suggestion: ${how_to_fix}
```

### Common Errors and Solutions

| Error | Cause | Solution |
|-------|-------|----------|
| Agent 'X' not found | Agent not generated | Run `/yolo:sync-agents` |
| Missing required field: Y | Input incomplete | Check workflow provides all required fields |
| Output missing field: Z | Agent bug | Check implementation prompt |
| Agent timeout | Task too large | Break into smaller tasks or increase timeout |
| Context exceeded | Too much exploration | Use quick variant or reduce scope |
</error_handling>

---

<integration>
## Integration with Pipelines

Pipelines use the orchestrator implicitly through stage definitions:

```yaml
# orchestration/pipelines/feature-full.yaml

stages:
  - name: research
    contract: research
    # Pipeline executor calls spawn_agent_with_profile internally:
    # spawn_agent_with_profile("research", stage.input, pipeline.profile)
    input:
      goal: "${FEATURE_GOAL}"
      scope: "${SCOPE}"
    output_as: research_findings
```

### Pipeline Executor Flow

```yaml
For each stage in pipeline.stages:
  1. Check conditions (if stage.condition)

  2. Resolve input variables:
     Replace ${VAR} with actual values from context

  3. Spawn agent:
     If stage.loop:
       For each item in stage.loop:
         result: spawn_agent_with_profile(stage.contract, item_input, profile)
         Append to stage.output_as[]
     Else:
       result: spawn_agent_with_profile(stage.contract, stage.input, profile)
       Store as stage.output_as

  4. Handle errors:
     If stage.on_failure:
       Execute trigger: stage.on_failure.trigger

  5. Pass output to next stage
```

### Status-Agent Mapping

| Feature Status | Agent Phase | Agent Contract |
|---|---|---|
| researching | Research | research |
| planning | Plan | plan |
| in_progress | Execute | execute |
| verifying | Verify | verify |
</integration>

---

<utilities>
## Utility Functions

### format_input(input, schema)

Formats input for display in agent prompt.

```yaml
format_input:
  template: |
    {{#each required}}
    **{{name}}:** {{value}}
    {{/each}}

    {{#if optional_present}}
    **Optional inputs provided:**
    {{#each optional}}
    - {{name}}: {{value}}
    {{/each}}
    {{/if}}
```

### parse_agent_output(response)

Extracts structured YAML from agent response.

```yaml
parse_agent_output:
  1. Find YAML block:
     Match: ```yaml\n(.*?)\n```
     Or: Lines starting with valid YAML after "output:" marker

  2. Parse YAML

  3. Return structured object
```

### resolve_agent_name(contract, profile)

Maps contract + profile to specific agent.

```yaml
resolve_agent_name:
  1. Load profile config
  2. Get implementation: profile.implementations[contract]
  3. Return: "${contract}-${implementation}"
```
</utilities>

---

<best_practices>
## Best Practices

### For Workflows Using Orchestrator

1. **Always use profile-based spawning** for consistency
2. **Handle errors gracefully** — check for error responses
3. **Pass complete context** — don't assume agent has prior knowledge
4. **Log agent calls** — for debugging and metrics
5. **Execute agents must not run git commands** (git add, git commit, etc.) — workflows handle all git operations

### For Adding New Agents

1. Create baseline in `agents/src/baselines/`
2. Create contract in `agents/src/contracts/`
3. Create implementation(s) in `agents/src/implementations/`
4. Run `/yolo:sync-agents` to generate
5. Add to profile implementations if needed
6. Update this registry

### For Debugging Agent Issues

1. Check agent exists: `ls agents/generated/`
2. Validate sources: `/yolo:sync-agents --check`
3. Check input matches contract
4. Review agent output for parsing issues
5. Check triggers for error handling
</best_practices>
