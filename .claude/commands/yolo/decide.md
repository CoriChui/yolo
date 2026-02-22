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
Read `.claude/yolo/agents/decide.md` for the agent prompt.
Note: This is a lightweight single-shot command that skips the workflow layer by design.
Note: The allowed-tools above apply to the orchestrator (this command). The spawned decide agent is restricted to Read, Glob, Grep (read-only) as declared in the agent file.
</execution_context>

<context>
Arguments: $ARGUMENTS
</context>

<process>

1. Get question from $ARGUMENTS or ask user
2. Gather codebase context: use Glob and Grep to find files relevant to the question, then Read key files to build a markdown context summary
3. Ensure `.planning/decisions/` directory exists (create with `mkdir -p` if missing)
4. Spawn decide agent (opus) with the question and the gathered codebase context
5. Save decision to `.planning/decisions/{slug}.md`
6. **Update state.yaml:** Set `session.last_action` to decision summary, update `session.resume` and `updated_at`.
7. Report recommendation

</process>
