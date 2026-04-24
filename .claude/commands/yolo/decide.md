---
name: yolo:decide
description: Make a design decision with multi-perspective analysis
argument-hint: "[question]"
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Glob
  - Grep
  - AskUserQuestion
  - Task
---

<objective>
Make design decisions using multi-perspective analysis (Architect, Pragmatist, Critic).

Takes a question, spawns a decide agent, and produces a structured recommendation with trade-offs.
</objective>

<execution_context>
Read `workspace/state.yaml` and `workspace/config.yaml` first. Validate `workspace/` exists — if missing, error: "Run `/yolo:init` first."
Read `.claude/yolo/agents/decide.md` for the agent prompt.
Note: This is a single-shot command that skips the workflow layer by design.
Note: The allowed-tools above apply to the orchestrator (this command). The spawned decide agent is restricted to Read, Glob, Grep (read-only) as declared in the agent file.
</execution_context>

<context>
Arguments: $ARGUMENTS
</context>

<process>

1. **Validate:** Read `workspace/config.yaml` — verify it exists and contains `agents.decide`. If missing, error: "Run `/yolo:init` first."
2. Get question from $ARGUMENTS or ask user
3. Gather codebase context: use Glob and Grep to find files relevant to the question, then Read key files to build a markdown context summary
4. Ensure `workspace/decisions/` directory exists (create with `mkdir -p` if missing)
5. Spawn decide agent via Task tool (model from `workspace/config.yaml` `agents.decide`) with the question and the gathered codebase context

## Post-Agent Orchestrator Steps

6. Save decision to `workspace/decisions/{slug}.md`
7. **Update state.yaml:** Re-read `state.yaml` to get current values before writing. Set `session.last_action` to decision summary, update `session.resume` and `updated_at`.
8. Report recommendation

</process>
