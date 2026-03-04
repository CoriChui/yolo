# Intake Workflow
# Commands: /yolo:intake capture, /yolo:intake add, /yolo:intake list, /yolo:intake status

Intake is **optional auxiliary context** — release-scoped, stored as `.md` digest files.
Read `.planning/state.yaml` before any operation. Validate it exists and is valid YAML — if missing, error: "Run `/yolo:init` first."
**Rule:** Every state.yaml, release.yaml, or manifest.yaml mutation must update `updated_at` to current ISO 8601 UTC timestamp.
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

1. **Resolve release:** Use `--release` flag or `focus.release`. Must be pending or active (not completed) AND `intake.locked` must be `false`. **Note (TOCTOU):** The `intake.locked` check here and the re-validation in step 11 form a best-effort safety net, not a true lock — the single-threaded rule (see header) is the primary guard against concurrent modification. File writes in steps 5-9 are not protected by a lock between the initial check and the re-validation. **Advisory lock:** Check for existing `.planning/releases/{id}/intake/.capture-in-progress` file — if present and recent (< 30 min), warn user: "A prior intake capture may still be in progress (started at {timestamp} for source {source}). It may have crashed. Override and continue?" via AskUserQuestion. **Crash recovery:** If the lock file exists (stale or acknowledged by user), also check if the source directory from the previous capture exists (`intake/{version}/{source}/`). If found, offer cleanup: "Found orphaned source directory from a prior crashed capture: {source}. Clean up (delete directory and restore conflicts.yaml if modified)?" via AskUserQuestion. If approved, delete the orphaned source directory and revert any `conflicts.yaml` additions from the crashed capture. If the lock file is older than 30 min, treat as stale from a crash and proceed. Then write a temporary file `.planning/releases/{id}/intake/.capture-in-progress` at this step (containing timestamp and source name). `/release end` should check for this file before locking intake — if present and recent (< 30 min), warn: "An intake capture may be in progress. Continue?" Remove the advisory lock in step 14 after completion.

2. **Check MCP** (for MCP sources): Use ToolSearch to check which MCP tools are available as deferred tools, then load them. Verify server responds. If not configured, show setup command from the Source Catalog table above.

3. **Check existing:** If source already captured, ask: re-capture or skip.

4. **Enforce intake limits:** Read `config.yaml` `intake.max_files` (default 200). Count existing intake versions for this release (`intake/{slug}-v*` directories) — if count >= 10 (max versions per release), error: "Maximum intake versions (10) reached for this release." Count existing files across all sources in the current version — if count >= `max_files`, error: "Maximum files per version ({max_files}) reached. Start a new patch version or remove unused sources." **Note:** Total size (100 MB) is checked after capture in step 10 below.

5. **Create source directory:** `intake/{version}/{source}/`

6. **Capture content** based on source type:
   - **MCP sources:** Use appropriate MCP tools to fetch content. Save as `.md` files.
   - **WebFetch sources:** Use WebFetch tool. Save raw content in fenced code blocks.
   - **CLI sources:** Run commands via Bash. Save output as `.md`.
   - **Local files:** Read files directly. Save in fenced code blocks.
   - **Interactive:** Prompt user for content.
   - **NotebookLM special:** Requires Google auth (`setup_auth`), use `notebook_id` for queries, run 5 parallel topic queries, close sessions after using `mcp__notebooklm__close_session`.
   - **Google Sheets special:** Discover all tabs via `/htmlview`, fetch each as CSV via `/gviz/tq?tqx=out:csv&gid={GID}`. Always capture all sheets including empty ones.
   - **`--raw` flag:** Copy directory as-is (no digesting).

7. **Extract requirements** (for document sources): Parse `.md` files for actionable requirements. Save to `{source}/requirements.yaml` with IDs (REQ-001, ...), text, types (functional/business_rule/constraint/adjustment/decision), domains, confidence, source_ref (traceability reference back to source material), and status (default: `active`; set to `superseded` if a later requirement overrides it).

8. **Validate coverage:** Re-read source, check each section has at least one requirement. Re-extract for uncovered sections.

9. **Resolve conflicts** (if multiple sources): Compare requirements by domain, resolve contradictions using priority: decision > adjustment > latest timestamp. Save to `conflicts.yaml`.

10. **Validate total size:** Calculate cumulative size of all files in the current intake version directory. If total exceeds 100 MB, clean up the source directory created in step 5 and error: "Intake version exceeds 100 MB size limit. Remove large sources or start a new version."

11. **Re-read state.yaml** to get current values. **Validate** that `focus.release` still matches the resolved release from step 1 — if not, clean up the source directory created in step 5 (remove `intake/{version}/{source}/`), **restore `conflicts.yaml`** to its pre-capture state if it was modified in step 9 (revert additions from this capture), then error: "Release focus changed during capture. Re-run `/yolo:intake capture`." **Re-read release.yaml** to verify release status is still `pending` or `active` and `intake.locked` is still `false` — if release was completed or intake locked since step 1, clean up the source directory and restore `conflicts.yaml`, then error: "Release was completed or intake locked during capture. Re-run `/yolo:intake capture`."

12. **Update manifest.yaml:** Add source entry with name, captured_at, file count, source_category. **Update release.yaml:** Set `updated_at` to current timestamp (intake is release-scoped, so release metadata should reflect the change).

13. **Generate summary.yaml (optional):** Content hints, entities mentioned, priority domains. Saved to `intake/{version}/summary.yaml`. Human-readable summary — not consumed by downstream agents.

14. **Clean up advisory lock:** Remove `.planning/releases/{id}/intake/.capture-in-progress` file. **Update state.yaml:** Re-read `state.yaml` to get current values before writing. Update `releases[].intake.current` to match `release.yaml` `intake.current` (keep state.yaml cache in sync). Update `updated_at`, `session.last_action` (describe what was captured), `session.resume` (current context for session continuity).

15. **Git commit:** Check `git status` for changes in `.planning/`. If changes exist, stage `.planning/` files and commit: `"chore: intake capture {source} for release {id}"`.

16. **Report** with source count, requirements extracted, conflicts resolved.

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

6. **Update manifest.yaml** and optionally **generate summary.yaml**.

7. **Re-read state.yaml** to get current values. **Re-validate:** Re-read `release.yaml` to verify release status is still `pending` or `active` and `intake.locked` is still `false` — if release was completed or intake locked, error: "Release was completed or intake locked during add. Re-run `/yolo:intake add`." Then update `updated_at`, `session.last_action` (describe what was added), `session.resume` (current context for session continuity). **Git commit**.

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
