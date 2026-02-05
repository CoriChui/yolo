<purpose>
Capture auxiliary materials from external source into release's intake.
REQUIRES a pending or active release — intake is release-scoped.
Uses focused release by default, can override with --release flag.
</purpose>

<triggers>
- `/intake capture [source]` - Capture from specified source (focused release)
- `/intake capture [source] [url-or-arg]` - Capture with URL or connection string
- `/intake capture [source] --release <id>` - Capture for specific release
</triggers>

<source_catalog>

## MCP sources (require MCP server)

| Source | MCP Server | Add Command |
|--------|------------|-------------|
| `figma` | figma | `claude mcp add figma -- npx -y figma-developer-mcp --stdio` |
| `notion` | notionApi | `claude mcp add notionApi --env NOTION_TOKEN=ntn_xxx -- npx -y @notionhq/notion-mcp-server` |
| `linear` | linear | `claude mcp add linear -- npx -y @anthropic/linear-mcp` |
| `jira` | jira | `claude mcp add jira -- npx -y @anthropic/jira-mcp` |
| `confluence` | confluence | `claude mcp add confluence -- npx -y @anthropic/confluence-mcp` |
| `slack` | slack | `claude mcp add slack -- npx -y @anthropic/slack-mcp` |
| `miro` | miro | `claude mcp add miro -- npx -y miro-mcp` |

## WebFetch sources (need URL, no MCP)

| Source | What it captures |
|--------|-----------------|
| `gdocs` | Google Docs/Sheets (link sharing required) |
| `swagger` | OpenAPI/Swagger spec from a live URL |
| `graphql` | GraphQL schema via introspection endpoint |
| `website` | Any web page — scrape content, UI patterns, docs |

## CLI sources (run commands locally)

| Source | What it captures |
|--------|-----------------|
| `github` | Issues, PRs, repo metadata via `gh` CLI |
| `db` | Live database schema via `psql`, `mysql`, `sqlite3`, etc. |

## Local file sources (read from disk)

| Source | What it captures |
|--------|-----------------|
| `openapi` | Local OpenAPI/Swagger YAML/JSON spec |
| `postman` | Postman/Insomnia collection export (JSON) |
| `protobuf` | `.proto` files — services, messages, enums |
| `graphql-schema` | Local `.graphql` / `.gql` schema files |
| `pdf` | PDF documents (specs, contracts, requirements) |
| `csv` | CSV/TSV data files |
| `sql` | SQL dump files, schema scripts |
| `har` | HAR files (browser network recordings — API discovery) |
| `docker` | Dockerfile + docker-compose — service topology |
| `terraform` | Terraform/OpenTofu — infrastructure topology |
| `envfile` | `.env` / `.env.example` — config shape (strip secrets) |

## Interactive (no external source)

| Source | What it captures |
|--------|-----------------|
| `manual` | Interactive dialog — user dictates domain info |
| `notes` | Free-form notes and observations |

</source_catalog>

<process>

<step name="determine_target_release">
**Determine which release to capture to:**

```bash
# Check for --release flag override
if [ -n "$RELEASE_FLAG" ]; then
  TARGET_RELEASE="$RELEASE_FLAG"
else
  # Use focused release from state
  TARGET_RELEASE=$(cat .planning/state.yaml 2>/dev/null | yq '.focus.release')
fi

# Load release details
RELEASE_ENTRY=$(cat .planning/state.yaml | yq ".releases[] | select(.id == \"${TARGET_RELEASE}\")")
RELEASE_STATUS=$(echo "$RELEASE_ENTRY" | yq '.status')
RELEASE_SLUG=$(echo "$RELEASE_ENTRY" | yq '.slug')
INTAKE_VERSION=$(echo "$RELEASE_ENTRY" | yq '.intake.current')
INTAKE_LOCKED=$(echo "$RELEASE_ENTRY" | yq '.intake.locked')
```
</step>

<step name="check_release_exists">
**REQUIRED: A pending or active release must exist.**

**If no release focused and no --release flag:**
```
═══════════════════════════════════════════════════════════════
NO RELEASE FOCUSED
═══════════════════════════════════════════════════════════════

No release is currently focused, and no --release flag provided.

Options:
  1. Focus a release:
       /release focus 2026-02-04-mvp

  2. Specify release explicitly:
       /intake capture figma --release 2026-02-04-mvp

  3. Create a new release:
       /release new <name>

═══════════════════════════════════════════════════════════════
```

**If target release not found:**
```
═══════════════════════════════════════════════════════════════
RELEASE NOT FOUND: ${TARGET_RELEASE}
═══════════════════════════════════════════════════════════════

Available releases:
  - 2026-02-04-mvp (active) [focused]
  - 2026-02-10-mobile (pending)

Use /release list to see all releases.
═══════════════════════════════════════════════════════════════
```

**If intake is locked (release completed):**
```
═══════════════════════════════════════════════════════════════
INTAKE LOCKED: ${TARGET_RELEASE}
═══════════════════════════════════════════════════════════════

Intake for release ${TARGET_RELEASE} is locked (release completed).

Start a new release to capture more:
  /release new <name>
═══════════════════════════════════════════════════════════════
```
</step>

<step name="check_mcp" condition="source is an MCP source (figma, notion, linear, jira, confluence, slack, miro)">
Check if required MCP server is available.

1. Try to use a tool from the MCP (e.g., list resources)
2. If MCP not found, show message and offer choices:

```
═══════════════════════════════════════════════════════════════
MCP NOT CONFIGURED: {source}
═══════════════════════════════════════════════════════════════

Capturing from {SOURCE} requires the {source} MCP server.

To add it manually, run in terminal:

  {ADD_COMMAND}

Then restart Claude Code and retry.
```

3. Use AskUserQuestion with options:
   - **Add MCP server** — Run the add command automatically
   - **Add manually** — Switch to manual capture mode
   - **Cancel** — Exit intake capture

4. Handle response:
   - If "Add MCP server": Run `{ADD_COMMAND}` via Bash, then inform user to restart
   - If "Add manually": Continue with `capture_manual` step
   - If "Cancel": Stop workflow
</step>

<step name="check_source_exists">
Check if source already captured in current intake:

```bash
# Intake is inside release directory
INTAKE_DIR="releases/${TARGET_RELEASE}/intake/${INTAKE_VERSION}"
SOURCE_EXISTS=$(cat "${INTAKE_DIR}/manifest.yaml" | \
  yq ".sources[] | select(.name == \"${SOURCE}\")")
```

If source already exists, ask user:
- **Re-capture** — Update existing source content
- **Skip** — Keep existing, don't re-capture
</step>

<step name="validate_source">
Match source name from the source catalog above.
If source is not recognized, show the catalog and ask user to pick one.
</step>

<step name="create_source_directory">
Create source directory in intake (inside release):

```bash
# Intake lives inside the release directory
INTAKE_DIR="releases/${TARGET_RELEASE}/intake/${INTAKE_VERSION}"
mkdir -p "${INTAKE_DIR}/${SOURCE}"
```

Structure (intake inside release):
```
releases/2026-02-04-mvp/
├── release.yaml
├── requirements.md
├── intake/                            # Release-scoped intake
│   ├── mvp-v1/                        # Version with release slug prefix
│   │   ├── manifest.yaml
│   │   ├── figma/
│   │   │   └── digest.md
│   │   ├── notion/
│   │   │   └── digest.md
│   │   └── notes/
│   │       └── digest.md
│   └── mvp-v1.1/                      # Patch version
├── features/
└── output/
```
</step>

<!-- ═══════════════════════════════════════════════════ -->
<!-- MCP SOURCES                                       -->
<!-- ═══════════════════════════════════════════════════ -->

<step name="capture_figma" condition="source == figma">
**Figma** — design files via MCP.

1. List available files/projects
2. Extract screens/frames, components, design tokens
3. Save raw data to `figma/` as `.md` files
</step>

<step name="capture_notion" condition="source == notion">
**Notion** — pages and databases via MCP.

1. Search pages: `mcp__notionApi__API-post-search`
2. Extract page content: `mcp__notionApi__API-get-block-children`
3. Extract databases: `mcp__notionApi__API-query-data-source`
4. Save raw content to `notion/` as `.md` files

If no pages accessible, advise: Settings → Connections → share pages with integration.
</step>

<step name="capture_linear" condition="source == linear">
**Linear** — issues and projects via MCP.

1. List projects / teams
2. Extract issues (title, description, status, assignee, labels)
3. Save to `linear/issues.md` — raw issue data
</step>

<step name="capture_jira" condition="source == jira">
**Jira** — issues and boards via MCP.

1. Ask user for project key or JQL filter
2. Extract issues (summary, description, status, type, priority)
3. Save to `jira/issues.md` — raw issue data
</step>

<step name="capture_confluence" condition="source == confluence">
**Confluence** — wiki pages via MCP.

1. Ask user for space key or page title
2. Extract page content (body, child pages)
3. Save to `confluence/` as `.md` files — raw page content
</step>

<step name="capture_slack" condition="source == slack">
**Slack** — channel messages via MCP.

1. Ask user for channel name
2. Extract recent messages (or thread)
3. Save to `slack/channel-{name}.md` — raw message log
</step>

<step name="capture_miro" condition="source == miro">
**Miro** — board content via MCP.

1. List available boards
2. Extract frames, sticky notes, shapes, connections
3. Save to `miro/board-{name}.md` — raw board content
</step>

<!-- ═══════════════════════════════════════════════════ -->
<!-- WEBFETCH SOURCES                                   -->
<!-- ═══════════════════════════════════════════════════ -->

<step name="capture_gdocs" condition="source == gdocs">
**Google Docs/Sheets** — via WebFetch. Link sharing must be enabled.

Ask for URL if not provided. Detect type from URL:
- `docs.google.com/document/d/{ID}` → Google Doc
- `docs.google.com/spreadsheets/d/{ID}` → Google Sheet

**Google Doc:**
```
WebFetch(url: ".../document/d/${ID}/export?format=txt", ...)
```
Follow 307 redirects. Save to `gdocs/{title}.md`.

**Google Sheet:**
1. Discover all tabs:
   ```
   WebFetch(url: ".../spreadsheets/d/${ID}/htmlview",
     prompt: "Find ALL sheet/tab names and gid values")
   ```
2. Fetch each sheet as CSV:
   ```
   WebFetch(url: ".../spreadsheets/d/${ID}/gviz/tq?tqx=out:csv&gid=${GID}",
     prompt: "Return complete raw CSV data with headers")
   ```
3. Fetch in parallel (up to 5 at a time)
4. Save to `gdocs/sheet-{name}.md`
</step>

<step name="capture_swagger" condition="source == swagger">
**Swagger / OpenAPI from URL** — fetch live API spec.

1. Ask for URL if not provided (e.g., `https://api.example.com/swagger.json`)
2. Common paths to try: `/swagger.json`, `/openapi.json`, `/api-docs`, `/v3/api-docs`
3. WebFetch the URL
4. Save raw spec to `swagger/spec.md` (JSON/YAML in code block)
5. If spec is large, also extract a summary: endpoints list, schemas
</step>

<step name="capture_graphql" condition="source == graphql">
**GraphQL schema** — via introspection query on a live endpoint.

1. Ask for GraphQL endpoint URL if not provided
2. Fetch introspection:
   ```
   WebFetch(url: "${URL}",
     prompt: "Send introspection query and return the full schema:
              types, queries, mutations, subscriptions")
   ```
   Or if WebFetch can't POST, ask user to run:
   ```bash
   curl -X POST ${URL} -H "Content-Type: application/json" \
     -d '{"query":"{ __schema { types { name fields { name type { name kind ofType { name } } } } } }"}' \
     > schema.json
   ```
   Then use `/intake add schema.json --as graphql`
3. Save to `graphql/schema.md`
</step>

<step name="capture_website" condition="source == website">
**Website** — scrape any web page for reference content.

1. Ask for URL(s) if not provided
2. WebFetch each URL — extract text content
3. Save to `website/{sanitized-domain-path}.md` — raw content in code block
4. Useful for: competitor UIs, documentation pages, reference APIs, design systems
</step>

<!-- ═══════════════════════════════════════════════════ -->
<!-- CLI SOURCES                                        -->
<!-- ═══════════════════════════════════════════════════ -->

<step name="capture_github" condition="source == github">
**GitHub** — issues, PRs, repo info via `gh` CLI.

1. Ask what to capture:
   - Issues (open, with labels/milestone filter)
   - Pull requests (open or recent merged)
   - Repo metadata (description, topics, languages)
   - Releases / tags

2. Run via Bash:
   ```bash
   gh issue list --json number,title,body,labels,state,assignees --limit 100
   gh pr list --json number,title,body,state,labels --limit 50
   gh repo view --json description,topics,languages
   ```

3. Save raw JSON output to `github/issues.md`, `github/prs.md`, etc.
</step>

<step name="capture_db" condition="source == db">
**Live database** — dump schema from a running database.

1. Ask for connection details: type (postgres/mysql/sqlite), host, database name
2. Dump schema only (no data):

   **PostgreSQL:**
   ```bash
   pg_dump --schema-only --no-owner --no-privileges "${CONNECTION_STRING}"
   ```

   **MySQL:**
   ```bash
   mysqldump --no-data --routines --triggers -h ${HOST} -u ${USER} -p ${DB}
   ```

   **SQLite:**
   ```bash
   sqlite3 "${DB_PATH}" ".schema"
   ```

3. Save raw SQL output to `db/schema.md`

**IMPORTANT:** Never store credentials in intake files.
Use env vars or ask user to run the command and pipe output.
If the connection string is provided, use it only for the dump command,
do NOT write it to any file.
</step>

<!-- ═══════════════════════════════════════════════════ -->
<!-- LOCAL FILE SOURCES                                 -->
<!-- ═══════════════════════════════════════════════════ -->

<step name="capture_openapi" condition="source == openapi">
**OpenAPI / Swagger local file** — parse local YAML/JSON spec.

1. Ask for file path if not provided
2. Read the file
3. Save raw content to `openapi/spec.md` in a code block
</step>

<step name="capture_postman" condition="source == postman">
**Postman / Insomnia collection** — local export file.

1. Ask for file path (`.json`)
2. Read the collection JSON
3. Save raw content to `postman/collection.md` in a code block
</step>

<step name="capture_protobuf" condition="source == protobuf">
**Protocol Buffers** — local `.proto` files.

1. Ask for path (file or directory)
2. Read all `.proto` files
3. Concatenate into `protobuf/schemas.md` — each file as a section
</step>

<step name="capture_graphql_schema" condition="source == graphql-schema">
**GraphQL schema files** — local `.graphql` / `.gql` files.

1. Ask for path (file or directory)
2. Read all `.graphql` / `.gql` files
3. Concatenate into `graphql/schema.md` — each file as a section
</step>

<step name="capture_pdf" condition="source == pdf">
**PDF document** — specs, contracts, requirements.

1. Ask for file path
2. Read with Read tool (supports PDF)
3. Save extracted text to `pdf/{filename}.md`
</step>

<step name="capture_csv" condition="source == csv">
**CSV / TSV data** — tabular data files.

1. Ask for file path
2. Read the file
3. Save raw content to `csv/{filename}.md` in a code block
</step>

<step name="capture_sql" condition="source == sql">
**SQL dump / schema** — local SQL files.

1. Ask for file path (file or directory)
2. Read `.sql` files
3. Concatenate into `sql/schema.md` — each file as a section
</step>

<step name="capture_har" condition="source == har">
**HAR file** — browser network recording for API discovery.

1. Ask for file path
2. Read the HAR JSON
3. Save raw content to `har/{filename}.md` in a code block

Note: HAR files can be large. If too big, extract just the
entries list (method, URL, status, request/response content types).
</step>

<step name="capture_docker" condition="source == docker">
**Docker / Compose** — service topology and infrastructure.

1. Ask for path (defaults to project root)
2. Read `Dockerfile`, `docker-compose.yml`, `docker-compose.*.yml`
3. Concatenate into `docker/topology.md` — each file as a section
</step>

<step name="capture_terraform" condition="source == terraform">
**Terraform / OpenTofu** — infrastructure as code.

1. Ask for path (defaults to project root or `infra/` / `terraform/`)
2. Read `*.tf` files
3. Concatenate into `terraform/infra.md` — each file as a section
</step>

<step name="capture_envfile" condition="source == envfile">
**Environment file** — config shape (secrets stripped).

1. Ask for file path (`.env`, `.env.example`, `.env.local`)
2. Read the file
3. **Strip all values** — keep only keys:
   `DATABASE_URL=postgres://...` → `DATABASE_URL=`
   Unless the file is `.env.example` (values are safe to keep)
4. Save to `envfile/env.md`
</step>

<!-- ═══════════════════════════════════════════════════ -->
<!-- INTERACTIVE SOURCES                                -->
<!-- ═══════════════════════════════════════════════════ -->

<step name="capture_manual" condition="source == manual">
**Manual** — interactive dialog, user dictates domain info.

1. Ask user what type of content to add:
   domain entities, API contracts, business flows, constraints
2. For each item, prompt for name, description, key attributes
3. Save to `manual/content.md`
</step>

<step name="capture_notes" condition="source == notes">
**Notes** — free-form notes and observations.

1. Ask user to type or paste their notes
2. Save as-is to `notes/content.md`
</step>

<step name="update_manifest">
Update manifest.yaml in release's intake:

```yaml
# releases/${TARGET_RELEASE}/intake/${INTAKE_VERSION}/manifest.yaml
version: "${INTAKE_VERSION}"          # {slug}-v{N} format (e.g., mvp-v1.1)
type: patch                           # major | patch
created: ${ORIGINAL_TIMESTAMP}
release: "${TARGET_RELEASE}"          # Parent release

sources:
  - name: figma
    captured_at: {EARLIER_TIMESTAMP}
    files: 5
    digest: figma/digest.md
  - name: notion                    # ← newly added
    captured_at: {TIMESTAMP}
    files: 3
    digest: notion/digest.md

parent: "mvp-v1"                      # For patch versions

stats:
  total_files: 8
  sources: 2
```
</step>

<step name="update_state">
# XC-001: Acquire lock before modifying state.yaml
```bash
LOCK_FILE=".planning/state.yaml.lock"
if ! mkdir "$LOCK_FILE" 2>/dev/null; then
  echo "ERROR: state.yaml is locked by another operation. Try again."
  exit 1
fi
trap "rmdir '$LOCK_FILE' 2>/dev/null" EXIT
```

Update state.yaml with new intake version for the release:

```yaml
# .planning/state.yaml
schema_version: 2
updated_at: {TIMESTAMP}
updated_by: intake-capture

focus:
  release: "${TARGET_RELEASE}"        # Stays the same

releases:
  - id: "${TARGET_RELEASE}"
    slug: "${RELEASE_SLUG}"
    status: ${RELEASE_STATUS}
    intake:
      current: "${INTAKE_VERSION}"    # ← Updated to new version
      locked: false

session:
  last_activity: {TIMESTAMP}
  last_action: "Captured ${SOURCE} to ${TARGET_RELEASE} intake"
  last_error: null
```

# XC-002: Compute checksum after state.yaml write
```bash
_checksum=$(sha256sum .planning/state.yaml | cut -d' ' -f1)
yq -i ".meta._checksum = \"${_checksum}\"" .planning/state.yaml
```

```bash
# Release lock
rmdir "$LOCK_FILE" 2>/dev/null
```
</step>

<step name="report_success">
```
═══════════════════════════════════════════════════════════════
INTAKE UPDATED: ${INTAKE_VERSION}
═══════════════════════════════════════════════════════════════

Release: ${TARGET_RELEASE} (${RELEASE_STATUS})
Added:   ${SOURCE} (${COUNT} files)

Location: releases/${TARGET_RELEASE}/intake/${INTAKE_VERSION}/

Current sources:
  - figma:  5 files
  - notion: 3 files    ← new
  ─────────────────
  Total:    8 files

───────────────────────────────────────────────────────────────
NEXT STEPS:
  /intake capture [source]  — Add another source
  /intake status            — Review intake
  /release start            — Start release (if pending)
═══════════════════════════════════════════════════════════════
```
</step>

</process>

<notes>
- REQUIRES pending or active release
- Intake lives INSIDE release at releases/<id>/intake/
- Version format: {slug}-v{N} (e.g., mvp-v1, mvp-v1.1)
- Uses focused release by default, override with --release flag
- Multiple sources accumulate in same version
- Intake stays open during pending AND active release
- Intake closes (locked) when release ends
- Each release has independent intake
- All captured content saved as .md files with raw content in fenced code blocks
- Never store credentials or secrets in intake files
- gdocs: link sharing required; sheets via /htmlview + /gviz/tq?tqx=out:csv&gid={GID}
- db: schema-only dump, never store connection strings in files
- envfile: strip secret values, keep only key names
</notes>
