---
name: yolo:decide
description: Use when facing a non-trivial design tradeoff that needs structured analysis — architecture choices, tech selection, pattern decisions, or resolving disagreements. Runs Architect/Pragmatist/Critic debate and saves the decision to .planning/decisions/.
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
Ensure `.planning/decisions/` exists — create with `mkdir -p .planning/decisions` if missing.
Read `.claude/yolo/agents/decide.md` for the agent prompt.
Note: This is a single-shot command that does not require /yolo:init or any state files.
Note: The allowed-tools above apply to the orchestrator (this command). The spawned decide agent is restricted to Read, Glob, Grep (read-only) as declared in the agent file.
</execution_context>

<context>
Arguments: $ARGUMENTS
</context>

<process>

1. **Validate:** Ensure `.planning/decisions/` exists (create with `mkdir -p` if missing)
2. Get question from $ARGUMENTS or ask user
3. Gather codebase context: use Glob and Grep to find files relevant to the question, then Read key files to build a markdown context summary
4. Spawn decide agent via Task tool with the question and the gathered codebase context

## Post-Agent Orchestrator Steps

5. Save decision to `.planning/decisions/{slug}.md`
6. Report recommendation

</process>
