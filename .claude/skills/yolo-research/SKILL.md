---
name: yolo-research
description: Use before planning a YOLO change, to understand the codebase and any cited intake before a plan is written. Read-only exploration that produces context for yolo-plan. Triggers on "understand how X works", "explore the code before we change it", or as the research step of yolo-feature.
---

# yolo-research

Read-only exploration. You gather the context a plan needs; you change nothing.

## Inputs
- A brief (`workspace/features/<slug>/brief.md`) — read `goal`, `success_criteria`, `intake_refs`.
  Or, when invoked standalone, a plain question.

## Procedure
1. Identify the relevant surface: `Glob`/`Grep` for the entities, modules, and routes named in the goal.
2. Read the key files. Capture concrete `file:line` references — never vague summaries.
3. If the brief lists `intake_refs`, read those digests under `workspace/intake/<source>/`. If a needed source is live and cheap (a URL, an MCP-reachable doc), fetch it just-in-time instead of expecting a stored digest.
4. Note: existing patterns/conventions to follow, integration points, risks, and any open questions that would block planning.

## Output
Write a concise note to `workspace/features/<slug>/research.md` (or return it inline when standalone) and commit it (`yolo: research <slug>`). Sections: Findings (with file:line), Patterns, Integration points, Risks, Open questions. Keep it tight — this feeds yolo-plan, not a human report.

## Constraints
- Read-only: never edit code, never run mutating commands.
- No status files. You do not set or read any feature "status" — that is derived from git (`.claude/yolo/conventions.md`).
- Cite `file:line`; do not invent APIs.
