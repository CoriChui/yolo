# Intake Layer

## Purpose

Intake is **auxiliary** raw materials from external sources. Optional context for releases, scoped to each release.

## Key Concept

**Intake = Optional context, not source of truth**

Codebase is the source of truth. Intake provides additional context when useful (Figma designs, requirements docs, briefs).

**Intake is release-scoped**: Each release has its own intake directory.

## When to Use Intake

| Scenario | Use Intake? |
|----------|-------------|
| Building UI from Figma designs | Yes — capture Figma |
| Adding feature from requirements doc | Yes — capture doc |
| Refactoring existing code | No — explore codebase |
| Fixing bugs | No — explore codebase |
| Continuing previous work | No — explore codebase |

## Sources

26+ source types across 4 categories. See `intake-capture.md` workflow for full catalog.

### MCP sources (require MCP server)

| Source | MCP Server | What It Captures |
|--------|------------|------------------|
| `figma` | figma | Frames, components, tokens |
| `notion` | notionApi | Pages, databases |
| `linear` | linear | Issues, projects, cycles |
| `jira` | jira | Issues, epics, sprints |
| `confluence` | confluence | Pages, spaces |
| `slack` | slack | Channel messages, threads |
| `miro` | miro | Boards, frames, sticky notes |

### WebFetch sources (need URL, no MCP)

| Source | What It Captures |
|--------|------------------|
| `gdocs` | Google Docs/Sheets (via htmlview + gviz endpoints) |
| `swagger` | OpenAPI/Swagger spec from a live URL |
| `graphql` | GraphQL schema via introspection endpoint |
| `website` | Any web page content |

### CLI sources (run commands locally)

| Source | What It Captures |
|--------|------------------|
| `github` | Issues, PRs, repo metadata via `gh` CLI |
| `db` | Live database schema via `psql`, `mysql`, `sqlite3` |

### Local file sources (read from disk)

| Source | What It Captures |
|--------|------------------|
| `openapi` | Local OpenAPI/Swagger YAML/JSON spec |
| `postman` | Postman/Insomnia collection export |
| `protobuf` | `.proto` files — services, messages, enums |
| `graphql-schema` | Local `.graphql` / `.gql` schema files |
| `pdf` | PDF documents |
| `csv` | CSV/TSV data files |
| `sql` | SQL dump files, schema scripts |
| `har` | HAR files (browser network recordings) |
| `docker` | Dockerfile + docker-compose |
| `terraform` | Terraform/OpenTofu |
| `envfile` | `.env` / `.env.example` (secrets stripped) |

### Interactive (no external source)

| Source | What It Captures |
|--------|------------------|
| `manual` | Interactive dialog — user dictates domain info |
| `notes` | Free-form notes and observations |

## Location

Intake lives **inside the release directory**:

```
releases/2026-02-04-mvp/
├── release.yaml
├── requirements.md
├── intake/                            # Release-scoped intake
│   ├── mvp-v1/                        # Version with release slug prefix
│   │   ├── manifest.yaml
│   │   ├── figma/
│   │   └── notion/
│   └── mvp-v1.1/
├── features/
└── output/
```

## Version Structure

Intake contains **only `.md` digest files** — raw content wrapped in fenced code blocks, no raw source files.

```
releases/2026-02-04-mvp/intake/mvp-v1/
├── manifest.yaml              # Version metadata
│
├── figma/                     # From Figma MCP
│   ├── components.md          # Raw component data in fenced blocks
│   ├── tokens.md              # Design tokens
│   └── screens.md             # Screen descriptions
│
├── gdocs/                     # From Google Sheets via WebFetch
│   └── sheets-digest.md       # All sheets as CSV in fenced blocks
│
├── lovable-project/           # From /intake add ./path-to-project
│   ├── file-tree.md           # Directory structure
│   ├── stack.md               # Package manifest, build config
│   ├── types.md               # Domain models, interfaces, DTOs
│   ├── schema.md              # DB migrations, ORM schemas
│   ├── routes.md              # Router config, endpoints
│   └── api.md                 # Service layer, controllers
│
└── notes/                     # Manual additions
    └── content.md
```

## .md Digest Format

Intake files contain **raw content in fenced code blocks** — no analysis or summarization.

For single files:
````markdown
# filename.ext

```ext
{raw file content as-is}
```
````

For projects (categorized by purpose):
````markdown
# src/models/user.ts

```ts
{raw file content}
```

# src/models/order.ts

```ts
{raw file content}
```
````

For captured data (e.g. Google Sheets CSV):
````markdown
# Sheet: Users

```csv
id,name,email,role
1,Alice,alice@example.com,admin
2,Bob,bob@example.com,user
```
````

## manifest.yaml

```yaml
version: "mvp-v1"                     # {slug}-v{number}
type: major                           # major | patch
created: 2026-02-03T15:00:00Z
release: "2026-02-04-mvp"             # Parent release

capture_status: complete              # complete | partial | failed
last_capture:
  at: 2026-02-03T16:00:00Z
  source: notes
  status: complete
  error: null

sources:
  - name: figma
    captured_at: 2026-02-03T15:00:00Z
    files: 42
    digest: figma/digest.md
  - name: notes
    captured_at: 2026-02-03T16:00:00Z
    files: 3
    digest: null

# For patch versions
parent: null                          # "mvp-v1" for mvp-v1.1

stats:
  total_files: 45
  sources: 2
```

> **Note:** See templates/manifest.yaml for the complete field reference (including trigger, contents, changes_from_parent). The fields above are the core required fields.

## Versioning

### Version Format

Intake versions use the release slug as prefix:

```
{release-slug}-v{major}[.{patch}]
```

Examples:
- `mvp-v1` — first version for "mvp" release
- `mvp-v1.1` — patch to mvp-v1
- `mvp-v2` — major re-capture for mvp release
- `mobile-v1` — first version for "mobile" release

### Major Versions ({slug}-v1, {slug}-v2)

Created when:
- Initial capture (automatic with `/release new`)
- Major re-capture from sources

### Patch Versions ({slug}-v1.1, {slug}-v1.2)

Created when:
- Adding new material
- Updating existing source

### Rules

1. **Full snapshots** — each version contains everything
2. **Immutable** — once created, never changes
3. **Optional** — releases can work without intake
4. **Release-scoped** — intake belongs to exactly one release

## Commands

All intake commands operate within the focused release context, or accept an explicit release ID:

```bash
# Capture (uses focused release by default)
/intake capture <source>
/intake capture figma          # MCP source
/intake capture gdocs          # WebFetch source
/intake capture db             # CLI source
/intake capture openapi        # Local file source

# Capture for specific release
/intake capture figma --release 2026-02-04-mvp

# Add local files/projects as .md digests
/intake add <path>
/intake add <path> --as <name>
/intake add <path> --release 2026-02-04-mvp

# Viewing
/intake status                         # Shows focused release intake
/intake status --release 2026-02-04-mvp
/intake list                           # List versions for focused release
/intake list --release 2026-02-04-mvp
/intake diff mvp-v1 mvp-v1.1          # Compare versions

# Maintenance
/intake prune                          # Remove intermediate versions, keeping first and latest
/intake prune --release 2026-02-04-mvp
```

## Integration with Release

Intake is created automatically with the release:

```
/release new mvp
    │
    ├── Creates release: 2026-02-04-mvp
    │
    ├── Creates intake directory: releases/2026-02-04-mvp/intake/
    │
    └── Creates initial version: mvp-v1 (empty, ready for capture)
```

Release reads intake during research:

```
/release start 2026-02-04-mvp
    │
    ├── Explores codebase (required)
    │
    ├── Reads intake/mvp-v1/ (optional)
    │   └── If doing UI work → read figma/
    │   └── If new feature → read notes/
    │
    └── Defines features
```

**Intake provides context. Codebase provides truth.**

## Flow: Multiple Releases

With parallel releases, each has independent intake:

```
releases/
├── 2026-02-04-mvp/
│   └── intake/
│       ├── mvp-v1/          # MVP's intake
│       └── mvp-v1.1/
│
└── 2026-02-10-mobile/
    └── intake/
        └── mobile-v1/       # Mobile's intake (separate)
```

Capturing for one release does not affect others.

## State Tracking

`state.yaml` tracks the current intake version per release:

```yaml
releases:
  - id: "2026-02-04-mvp"
    status: active
    intake:
      current: "mvp-v1.1"
      locked: false
  - id: "2026-02-10-mobile"
    status: pending
    intake:
      current: "mobile-v1"
      locked: false
```

When a release is completed, its intake is locked (no more captures).

> **Note:** HYBRID-AGENT-ARCHITECTURE.md references `intake_baseline` but the canonical fields per 04-state.md are `intake.current` and `intake.locked` as shown above.

## Capture Error Handling

### Transaction Model

Each intake capture operates as a transaction:

```yaml
# manifest.yaml tracking
capture_status: complete | partial | failed
last_capture:
  at: 2026-02-10T15:00:00Z
  source: figma
  status: complete
  error: null
```

### Failure Recovery

| Failure | Behavior | Recovery |
|---------|----------|---------|
| Source unreachable (Figma down, URL 404) | Capture aborted, no files written | Retry with `/intake capture --retry` |
| Partial capture (network error mid-fetch) | Partial .md files cleaned up, status set to `failed` | Retry captures only failed source |
| Manifest write fails | Previous manifest preserved | Manual fix or re-capture |

### Invariants

- A `failed` capture MUST NOT leave partial files in the intake directory
- Previous version is never modified during capture of new version
- `capture_status: complete` required before intake can be consumed by agents

## Intake Diff Format

`/intake diff <v1> <v2>` produces structured comparison:

### Output Format

```
═══════════════════════════════════════════════
INTAKE DIFF: mvp-v1 → mvp-v1.1
═══════════════════════════════════════════════

SOURCES CHANGED
  + openapi (new source added)
  ~ figma (3 files modified)
  - notes/old-requirements.md (removed)

FILES ADDED (3)
  figma/screens.md
  swagger/api-spec.md
  db/schema.md

FILES MODIFIED (2)
  figma/tokens.md (sizes updated)
  figma/components.md (new variants added)

FILES REMOVED (1)
  notes/old-requirements.md
```

### Diff Rules

- All intake files are `.md` — content diffs are always available
- Use `--detailed` flag for inline diff of modified files

## Agent Intake Access

Agents receive intake data as input when spawned via the Task tool by workflows/orchestrator. They do NOT directly read intake directories.

### Which Agents Consume Intake

| Agent | Intake Access | What They Use |
|-------|---------------|---------------|
| research-* | Full intake via `input.intake` | All sources, digests, manifest |
| plan-* | Intake insights via `input.intake_insights` | Pre-extracted insights from research |
| execute-* | Intake references via `input.task.intake_ref` | Specific requirement references |
| verify-* | None | Does not consume intake |
| decide-* | Intake context via `input.context` | Passed as part of decision context |

### Intake Input Schema (for research agent)

```yaml
intake:
  version: "mvp-v1"
  path: "releases/2026-02-04-mvp/intake/mvp-v1"
  sources:
    - type: figma
      path: "releases/2026-02-04-mvp/intake/mvp-v1/figma/"
      priority: high
    - type: notes
      path: "releases/2026-02-04-mvp/intake/mvp-v1/notes/"
      priority: medium
```

## Size Limits and Constraints

| Constraint | Limit | Rationale |
|------------|-------|-----------|
| Max files per version | 200 | Agent context window limits |
| Max total size per version | 100 MB | Storage and performance |
| Max digest size | 10,000 words | Agent consumption limit |
| Max versions per release | 10 | Prevent unbounded growth |
| Warning threshold | 80% of any limit | Early notification |

### Enforcement

Size limit checks run during `/intake capture` and `/intake add`:

- **Warning threshold (80%):** Logs a warning but proceeds with the operation.
- **Hard limit (100%):** Aborts the operation with an error suggesting `/intake prune` to free space.

### Cleanup

- Old versions within a release are preserved (full snapshots)
- On release completion, all intake versions are archived with the release
- `/intake prune` can remove intermediate versions, keeping first and latest
