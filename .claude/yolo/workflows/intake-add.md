<purpose>
Add local files or projects into release's intake as digested markdown.
Unlike `intake capture`, this reads local paths rather than fetching from external services.
NEVER copies raw source files — always produces .md digest files only.
REQUIRES a pending or active release — intake is release-scoped.
</purpose>

<triggers>
- `/intake add <path>` - Add file or directory to intake (focused release)
- `/intake add ./designs/mockup.png` - Add single file
- `/intake add ./docs/` - Add entire directory
- `/intake add ./spec.pdf --as api-spec` - Add with custom name
- `/intake add <path> --release 2026-02-04-mvp` - Add to specific release
</triggers>

<process>

<step name="parse_arguments">
**Parse command arguments:**

```bash
# Required: path to file or directory
SOURCE_PATH="$1"

# Optional flags
CUSTOM_NAME="${AS_FLAG}"        # --as <name> for custom directory name
TARGET_RELEASE="${RELEASE_FLAG}" # --release <id> override
```

**Validate source path exists:**

```bash
if [ ! -e "$SOURCE_PATH" ]; then
  echo "ERROR: Path not found: $SOURCE_PATH"
  exit 1
fi

# Determine if file or directory
if [ -d "$SOURCE_PATH" ]; then
  SOURCE_TYPE="directory"
  FILE_COUNT=$(find "$SOURCE_PATH" -type f | wc -l | tr -d ' ')
else
  SOURCE_TYPE="file"
  FILE_COUNT=1
fi
```
</step>

<step name="determine_target_release">
**Determine which release to add to:**

```bash
# Check for --release flag override
if [ -n "$TARGET_RELEASE" ]; then
  true  # Use provided value
else
  # Use focused release from state
  TARGET_RELEASE=$(cat .planning/state.yaml 2>/dev/null | yq '.focus.release')
fi

if [ -z "$TARGET_RELEASE" ] || [ "$TARGET_RELEASE" = "null" ]; then
  # ERROR: No release — show guidance
  exit 1
fi

# Load release details
RELEASE_ENTRY=$(cat .planning/state.yaml | yq ".releases[] | select(.id == \"${TARGET_RELEASE}\")")
RELEASE_STATUS=$(echo "$RELEASE_ENTRY" | yq '.status')
RELEASE_SLUG=$(echo "$RELEASE_ENTRY" | yq '.slug')
INTAKE_VERSION=$(echo "$RELEASE_ENTRY" | yq '.intake.current')
INTAKE_LOCKED=$(echo "$RELEASE_ENTRY" | yq '.intake.locked')
```
</step>

<step name="validate_release">
**Check release is valid for intake:**

```bash
# Release must exist
if [ -z "$RELEASE_ENTRY" ]; then
  echo "ERROR: Release not found: ${TARGET_RELEASE}"
  exit 1
fi

# Release must be pending or active
if [ "$RELEASE_STATUS" != "pending" ] && [ "$RELEASE_STATUS" != "active" ]; then
  echo "ERROR: Release ${TARGET_RELEASE} is ${RELEASE_STATUS} — intake only works on pending/active releases"
  exit 1
fi

# Intake must not be locked
if [ "$INTAKE_LOCKED" = "true" ]; then
  echo "ERROR: Intake for ${TARGET_RELEASE} is locked"
  exit 1
fi
```

**If no release focused:**
```
═══════════════════════════════════════════════════════════════
NO RELEASE FOCUSED
═══════════════════════════════════════════════════════════════

No release is currently focused, and no --release flag provided.

Options:
  1. Focus a release:
       /yolo:release focus 2026-02-04-mvp

  2. Specify release explicitly:
       /yolo:intake add ./file.png --release 2026-02-04-mvp

  3. Create a new release:
       /yolo:release new <name>

═══════════════════════════════════════════════════════════════
```
</step>

<step name="determine_destination">
**Determine where files go in intake:**

```bash
# Intake directory for current version
INTAKE_DIR=".planning/releases/${TARGET_RELEASE}/intake/${INTAKE_VERSION}"

# Determine destination name
if [ -n "$CUSTOM_NAME" ]; then
  DEST_NAME="$CUSTOM_NAME"
elif [ "$SOURCE_TYPE" = "directory" ]; then
  DEST_NAME=$(basename "$SOURCE_PATH")
else
  DEST_NAME="manual"
fi

DEST_DIR="${INTAKE_DIR}/${DEST_NAME}"
```
</step>

<step name="check_existing">
**Check if destination already has content:**

```bash
if [ -d "$DEST_DIR" ] && [ "$(ls -A "$DEST_DIR" 2>/dev/null)" ]; then
  # Destination exists and is non-empty — ask user
  EXISTING_COUNT=$(find "$DEST_DIR" -type f | wc -l | tr -d ' ')
  echo "Destination ${DEST_NAME}/ already has ${EXISTING_COUNT} files."
  # AskUserQuestion: Merge (add alongside), Replace (overwrite), Cancel
fi
```
</step>

<step name="collect_to_md">
**IMPORTANT: Never copy raw source files into intake.**
Intake only contains `.md` files — raw content grouped by category.

No analysis, no summarization. Read files, concatenate raw content into
a few categorized `.md` files with fenced code blocks.

```bash
mkdir -p "$DEST_DIR"
```

**Detect what was given** — single file, a plain directory, or a code project:

- **Single file** → one `.md` with the raw content
- **Directory without a package manifest** → plain directory (not a project)
- **Directory with a package manifest** (package.json, go.mod, pom.xml, *.csproj, Cargo.toml, Gemfile, composer.json, pyproject.toml, etc.) → code project

---

### Single file

Read the file. Write `${DEST_DIR}/${filename}.md`:

````markdown
# {filename.ext}

```{ext}
{raw file content as-is}
```
````

Done. One file in, one `.md` out.

---

### Plain directory (not a project)

Read every file in the directory (skip binary files).
Concatenate all into one `content.md`:

````markdown
# {relative/path/to/file1.ext}

```{ext}
{raw content}
```

# {relative/path/to/file2.ext}

```{ext}
{raw content}
```
````

If the directory is large (50+ files), also generate `file-tree.md`
and only include the files that look relevant to the release.

---

### Code project

Produce categorized `.md` files — each concatenates raw content
of files that serve the same purpose:

| Output file | What to collect |
|-------------|----------------|
| `file-tree.md` | Directory structure (skip dependency/build/output dirs) |
| `stack.md` | Package manifest, build config, runtime config, env examples |
| `types.md` | Domain models, entities, interfaces, DTOs, enums — the data shapes |
| `schema.md` | Database migrations, ORM schemas, SQL files |
| `routes.md` | Router/URL config, endpoint definitions |
| `api.md` | Service layer, repositories, controllers, data-fetching logic |

Skip any category if no matching files found.
Explore the project with Glob/Read to find files by purpose.
Projects vary across frameworks and versions — use judgement, not hardcoded paths.

**Format** — same as above: header with relative path, fenced code block, no commentary.

**Always skip:** dependency dirs, build output, lock files, generated UI
primitives, binary files, images, fonts.

```bash
COPIED_COUNT=$(find "$DEST_DIR" -type f -name '*.md' | wc -l | tr -d ' ')
```
</step>

<step name="update_manifest">
**Update manifest.yaml in intake:**

```bash
MANIFEST="${INTAKE_DIR}/manifest.yaml"
```

If manifest doesn't exist yet, create it:

```yaml
# ${INTAKE_DIR}/manifest.yaml
version: "${INTAKE_VERSION}"
type: patch
created: ${TIMESTAMP}
release: "${TARGET_RELEASE}"

sources: []

stats:
  total_files: 0
  sources: 0
```

Then append the new source:

```yaml
sources:
  - name: "${DEST_NAME}"
    type: local
    captured_at: ${TIMESTAMP}
    files: ${COPIED_COUNT}          # count of .md digest files only
    digest: "${DEST_NAME}/digest.md"
    original_path: "${SOURCE_PATH}"
```

Update stats:

```yaml
stats:
  total_files: ${TOTAL_FILES}   # Sum of all sources
  sources: ${SOURCE_COUNT}       # Number of source entries
```
</step>

<step name="update_state">
**Acquire lock and update state.yaml:**

```bash
# XC-001: Acquire lock
LOCK_FILE=".planning/state.yaml.lock"
if ! mkdir "$LOCK_FILE" 2>/dev/null; then
  echo "ERROR: state.yaml is locked by another operation. Try again."
  exit 1
fi
trap "rmdir '$LOCK_FILE' 2>/dev/null" EXIT
```

Update session fields:

```yaml
session:
  last_activity: ${TIMESTAMP}
  last_action: "Added ${COPIED_COUNT} files to ${TARGET_RELEASE} intake (${DEST_NAME})"
  last_error: null
```

```bash
# XC-002: Compute checksum
_checksum=$(sha256sum .planning/state.yaml | cut -d' ' -f1)
yq -i "._checksum = \"${_checksum}\"" .planning/state.yaml

# Release lock
rmdir "$LOCK_FILE" 2>/dev/null
```
</step>

<step name="git_commit">
**Commit added files:**

```bash
git add "${DEST_DIR}/" "${INTAKE_DIR}/manifest.yaml" .planning/state.yaml
git commit -m "chore(intake): add ${DEST_NAME} to ${TARGET_RELEASE} intake

Files: ${COPIED_COUNT}
Source: ${SOURCE_PATH}"
```
</step>

<step name="report_success">
```
═══════════════════════════════════════════════════════════════
INTAKE ADD: ${DEST_NAME}
═══════════════════════════════════════════════════════════════

Release:  ${TARGET_RELEASE} (${RELEASE_STATUS})
Source:   ${SOURCE_PATH}
Digests:  ${COPIED_COUNT} .md files → ${DEST_NAME}/

Location: .planning/releases/${TARGET_RELEASE}/intake/${INTAKE_VERSION}/

Current sources:
${for each source in manifest:}
  - ${name}: ${files} files
${endfor}
  ─────────────────
  Total: ${TOTAL_FILES} files

───────────────────────────────────────────────────────────────
NEXT STEPS:
  /yolo:intake add <path>        — Add more files
  /yolo:intake capture <source>  — Capture from MCP source
  /yolo:intake status            — Review intake
═══════════════════════════════════════════════════════════════
```
</step>

</process>

<error_handling>

**Path not found:**
```
═══════════════════════════════════════════════════════════════
FILE NOT FOUND
═══════════════════════════════════════════════════════════════

Path does not exist: ${SOURCE_PATH}

Check the path and try again.
═══════════════════════════════════════════════════════════════
```

**Empty directory:**
```
═══════════════════════════════════════════════════════════════
EMPTY DIRECTORY
═══════════════════════════════════════════════════════════════

Directory is empty: ${SOURCE_PATH}

Nothing to add.
═══════════════════════════════════════════════════════════════
```

**Large file warning (> 10MB):**
```
═══════════════════════════════════════════════════════════════
LARGE FILE WARNING
═══════════════════════════════════════════════════════════════

${FILENAME} is ${SIZE}MB. Large files increase repository size.

Options:
  1. Add anyway
  2. Skip this file
  3. Add to .gitignore and keep local only
═══════════════════════════════════════════════════════════════
```

</error_handling>

<invariants>
- REQUIRES pending or active release with unlocked intake
- NEVER copy raw source files — intake contains ONLY .md digest files
- Source is analyzed in-place, digests are written to intake
- Original files remain untouched at their source path
- Manifest is always updated atomically
- State.yaml lock acquired before any state writes
- Checksum computed after state.yaml modification
- Git commit includes digest .md files, manifest, and state
</invariants>
