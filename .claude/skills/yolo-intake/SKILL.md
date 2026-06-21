---
name: yolo-intake
description: Use when the user references external material (Figma, a Google Doc, a DB schema, an API spec, a URL) to bring into context. Fetches just-in-time for cheap/live sources; persists a digest only for expensive, rate-limited, or offline sources. Triggers on "pull in this Figma/doc/schema", "use this spec".
---

# yolo-intake

Bring external material into reach. The shelf is project-level (`workspace/intake/`), owned by no release.

## Decide: just-in-time vs persist
- **Just-in-time** (default for cheap/live sources — a URL, an MCP-reachable doc): fetch now, use it, cite it. Do NOT persist a digest.
- **Persist** (only for expensive / rate-limited / offline sources — a large Figma, a DB you don't want to hammer, a PDF): write a `.md` digest under `workspace/intake/<source>/` so it is reusable across features and commits.

## Procedure
1. Identify the source type and reach it (MCP tool, WebFetch, a CLI, or a local file).
2. If persisting: write the digested `.md` under `workspace/intake/<source>/` and commit. If JIT: keep it in working context only.
3. A feature brief references persisted intake via its `intake_refs` list.

## Constraints
- Never persist secrets verbatim — strip `.env`/credentials before writing a digest.
- The shelf is shared across all features. Never nest intake under a feature or a "release".
