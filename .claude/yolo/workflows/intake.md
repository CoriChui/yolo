# Intake Workflow
# Commands: /intake capture, /intake add, /intake list, /intake status

Intake is **optional auxiliary context** — release-scoped, stored as `.md` digest files.
Read `.planning/state.yaml` before any operation. Validate it exists and is valid YAML — if missing, error: "Run `/yolo:init` first."
**Rule:** Every state.yaml mutation must update `updated_at` to current ISO 8601 UTC timestamp.
**Rule:** Intake workflows are single-threaded — only one `/intake capture` or `/intake add` operation at a time. Do not run concurrent intake operations on the same release.

---

## /intake capture <source> [url] [--release <id>] [--prompt "<text>"]

Capture from an external source into the focused release's intake.

### Source Catalog

**MCP sources** (require MCP server):

| Source | MCP Server | Setup |
|--------|------------|-------|
| `figma` | figma | `claude mcp add figma -- npx -y figma-developer-mcp --stdio` |
| `notion` | notionApi | `claude mcp add notionApi --env NOTION_TOKEN=<your-token> -- npx -y @notionhq/notion-mcp-server` |
| `linear` | linear | `claude mcp add linear -- npx -y @anthropic/linear-mcp` |
| `jira` | jira | `claude mcp add jira -- npx -y @anthropic/jira-mcp` |
| `confluence` | confluence | `claude mcp add confluence -- npx -y @anthropic/confluence-mcp` |
| `slack` | slack | `claude mcp add slack -- npx -y @anthropic/slack-mcp` |
| `notebooklm` | notebooklm | `claude mcp add notebooklm -- npx -y notebooklm-mcp@latest` |

**WebFetch sources** (URL, no MCP): `gdocs`, `swagger`, `graphql`, `website`

**CLI sources** (local commands): `github` (gh CLI), `db` (psql/mysql/sqlite)

**Local file sources**: `openapi`, `postman`, `protobuf`, `graphql-schema`, `pdf`, `csv`, `sql`, `har`, `docker`, `terraform`, `envfile`

**Interactive**: `manual`, `notes`

### Process

1. **Resolve release:** Use `--release` flag or `focus.release`. Must be pending/active with unlocked intake.

2. **Check MCP** (for MCP sources): Use ToolSearch to load deferred tools, verify server responds. If not configured, show setup command from the Source Catalog table above. Note: only `notion` and `notebooklm` are pre-configured as deferred tools; other MCP sources (`figma`, `linear`, `jira`, `confluence`, `slack`) require user to run the setup command first.

3. **Check existing:** If source already captured, ask: re-capture or skip.

4. **Create source directory:** `intake/{version}/{source}/`

5. **Capture content** based on source type:
   - **MCP sources:** Use appropriate MCP tools to fetch content. Save as `.md` files.
   - **WebFetch sources:** Use WebFetch tool. Save raw content in fenced code blocks.
   - **CLI sources:** Run commands via Bash. Save output as `.md`.
   - **Local files:** Read files directly. Save in fenced code blocks.
   - **Interactive:** Prompt user for content.
   - **NotebookLM special:** Requires Google auth (`setup_auth`), use `notebook_id` for queries, run 5 parallel topic queries, close sessions after using `mcp__notebooklm__close_session`.
   - **Google Sheets special:** Discover all tabs via `/htmlview`, fetch each as CSV via `/gviz/tq?tqx=out:csv&gid={GID}`. Always capture all sheets including empty ones.
   - **`--raw` flag:** Copy directory as-is (no digesting).

6. **Extract requirements** (for document sources): Parse `.md` files for actionable requirements. Save to `{source}/requirements.yaml` with IDs (REQ-001, ...), types (functional/business_rule/constraint/adjustment/decision), domains, confidence.

7. **Validate coverage:** Re-read source, check each section has at least one requirement. Re-extract for uncovered sections.

8. **Resolve conflicts** (if multiple sources): Compare requirements by domain, resolve contradictions using priority: decision > adjustment > latest timestamp. Save to `conflicts.yaml`.

9. **Re-read state.yaml** to get current values. **Validate** that `focus.release` still matches the resolved release from step 1 — if not, clean up the source directory created in step 4 (remove `intake/{version}/{source}/`), then error: "Release focus changed during capture. Re-run `/yolo:intake capture`."

10. **Update manifest.yaml:** Add source entry with name, captured_at, file count, source_category.

11. **Generate summary.yaml:** Content hints, entities mentioned, priority domains. Saved to `intake/{version}/summary.yaml`.

12. **Update state.yaml:** `updated_at`, `session.last_action` (describe what was captured), `session.resume` (current context for session continuity).

13. **Report** with source count, requirements extracted, conflicts resolved.

### Digest Format

All intake files are raw content wrapped in fenced code blocks:
````markdown
# src/models/user.ts

```ts
{raw file content}
```
````

---

## /intake add <path> [--as <name>] [--release <id>] [--prompt "<text>"]

Add local files or directories as `.md` digests. Never copies raw files — always produces `.md` digests.

### Process

1. **Validate path exists.** Determine if file or directory.

2. **Resolve release:** Same as `/intake capture`.

3. **Determine destination name:** `--as` flag, directory basename, or "manual".

4. **Detect content type:**
   - **Single file** → one `.md` with raw content in code block
   - **Plain directory** → concatenate all files into `content.md`
   - **Code project** (has package.json/go.mod/etc.) → categorized digests:
     | File | Contents |
     |------|----------|
     | `file-tree.md` | Directory structure |
     | `stack.md` | Package manifest, build/runtime config |
     | `types.md` | Models, interfaces, DTOs, enums |
     | `schema.md` | DB migrations, ORM schemas |
     | `routes.md` | Router/URL config, endpoints |
     | `api.md` | Service layer, controllers |

5. **Extract requirements** (for non-code-project sources).

6. **Update manifest.yaml** and **generate summary.yaml**.

7. **Re-read state.yaml** to get current values, then update `updated_at`, `session.last_action` (describe what was added), `session.resume` (current context for session continuity). **Git commit**.

---

## /intake list [--release <id>]

List intake versions for a release (read-only).

### Process

1. **Resolve release:** Use `--release` or `focus.release`.

2. **Find versions:** List `intake/{slug}-v*` directories, sort by version.

3. **Display:**
   ```
   INTAKE VERSIONS: {release}
   ─────────────────────────────
   VERSION      DATE         TYPE    SOURCES         FILES
   mvp-v1       2026-02-03   major   figma,notion    20
   mvp-v1.1     2026-02-10   patch   +notes          21     ← current
   ```

---

## /intake status [--release <id>]

Show current intake version and stats (read-only).

### Process

1. **Resolve release:** Use `--release` or `focus.release`.

2. **Read manifest.yaml** from current intake version.

3. **Display:**
   ```
   INTAKE STATUS: {release}
   ─────────────────────────────
   Version:     {version} ({type})
   Created:     {created_at}
   Locked:      {locked}

   SOURCES                              FILES
   {source_name}    {captured_at}       {files}
   {source_name}    {captured_at}       {files}

   TOTALS
     Sources:   {stats.sources}
     Files:     {stats.total_files}

   REQUIREMENTS
     Total:     {count from requirements.yaml}
     By type:   {functional}: N, {business_rule}: N, ...
     Conflicts: {count from conflicts.yaml}
   ```

4. **If no intake exists:** Report "No intake captured. Run `/yolo:intake capture <source>` to start."

---

## Notes

- Intake is always release-scoped at `.planning/releases/{id}/intake/`
- Never store credentials or secrets in intake files
- Never copy raw source files — always produce `.md` digests (except `--raw` flag)
- `--prompt` shapes requirement extraction, summary generation
- `envfile`: strip secret values, keep only key names
- `db`: schema-only dump, never persist connection strings
- Requirement types: functional, business_rule (invariant/parameter), constraint, adjustment, decision
- Conflict resolution: decision > adjustment > latest timestamp
