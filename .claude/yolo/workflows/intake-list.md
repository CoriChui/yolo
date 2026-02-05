<purpose>
List all intake versions for a release.
Intake is release-scoped, uses focused release by default.
</purpose>

<triggers>
- `/intake list` - List versions for focused release
- `/intake list --release 2026-02-04-mvp` - List versions for specific release
</triggers>

<process>

<step name="determine_target_release">
Determine which release to list intake for:

```bash
# Check for --release flag override
if [ -n "$RELEASE_FLAG" ]; then
  TARGET_RELEASE="$RELEASE_FLAG"
else
  # Use focused release from state
  TARGET_RELEASE=$(cat .planning/state.yaml 2>/dev/null | yq '.focus.release')
fi

# Validate and get release info
RELEASE_ENTRY=$(cat .planning/state.yaml | yq ".releases[] | select(.id == \"${TARGET_RELEASE}\")")
RELEASE_SLUG=$(echo "$RELEASE_ENTRY" | yq '.slug')
CURRENT_VERSION=$(echo "$RELEASE_ENTRY" | yq '.intake.current')
```
</step>

<step name="find_versions">
Find all intake version directories in the release:

```bash
# Intake lives inside release directory
INTAKE_BASE="releases/${TARGET_RELEASE}/intake"
ls -d "${INTAKE_BASE}/${RELEASE_SLUG}-v"* 2>/dev/null | sort -V
```

Sort by version number (mvp-v1, mvp-v1.1, mvp-v2, etc.)
</step>

<step name="load_manifests">
For each version, load manifest:

```bash
INTAKE_BASE="releases/${TARGET_RELEASE}/intake"
for VERSION_DIR in "${INTAKE_BASE}/${RELEASE_SLUG}-v"*; do
  VERSION=$(basename "$VERSION_DIR")
  MANIFEST="${VERSION_DIR}/manifest.yaml"

  if [ -f "$MANIFEST" ]; then
    TYPE=$(cat "$MANIFEST" | yq '.type')
    CREATED=$(cat "$MANIFEST" | yq '.created')
    SOURCES=$(cat "$MANIFEST" | yq '.sources[].name' | tr '\n' ',')
    FILE_COUNT=$(cat "$MANIFEST" | yq '.stats.total_files')
  fi
done
```
</step>

<step name="display_list">
Format and display version list:

```
═══════════════════════════════════════════════════════════════
INTAKE VERSIONS: ${TARGET_RELEASE}
═══════════════════════════════════════════════════════════════

Location: releases/${TARGET_RELEASE}/intake/

VERSION      DATE         TYPE    SOURCES         FILES
───────────────────────────────────────────────────────────────
mvp-v1       2026-02-03   major   figma,notion   20
mvp-v1.1     2026-02-10   patch   +notes          21     ← current

───────────────────────────────────────────────────────────────
Total: 2 versions

Intake is AUXILIARY context.
Codebase remains the source of truth.

COMMANDS:
  /intake status                    — Current version details
  /intake diff mvp-v1 mvp-v1.1      — Compare versions
  /intake capture                   — Capture new source
═══════════════════════════════════════════════════════════════
```

Mark current version with ← current
</step>

</process>

<error_handling>

**No release focused:**
```
═══════════════════════════════════════════════════════════════
NO RELEASE FOCUSED
═══════════════════════════════════════════════════════════════

No release is currently focused.

Options:
  1. Focus a release:
       /release focus 2026-02-04-mvp

  2. Specify release explicitly:
       /intake list --release 2026-02-04-mvp

Use /release list to see all releases.
═══════════════════════════════════════════════════════════════
```

**Release not found:**
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

**No versions exist:**
```
═══════════════════════════════════════════════════════════════
NO INTAKE VERSIONS: ${TARGET_RELEASE}
═══════════════════════════════════════════════════════════════

No intake versions found for release ${TARGET_RELEASE}.

Intake is OPTIONAL auxiliary context.
Releases can work directly from codebase.

Use /intake capture to create intake:
  /intake capture notion     — From Notion pages
  /intake capture figma      — From Figma MCP
═══════════════════════════════════════════════════════════════
```

**Manifest missing for version:**
```
VERSION      DATE         TYPE    SOURCES         FILES
───────────────────────────────────────────────────────────────
mvp-v1       2026-02-03   major   figma           20
mvp-v1.1     (manifest missing)                        ⚠ corrupted
```

</error_handling>

<options>
- `--release <id>` - Show intake for specific release
- `--verbose` - Show full details for each version
- `--json` - Output as JSON for scripting

# TODO: --verbose and --json options are declared but not yet implemented
</options>

<notes>
- Intake is release-scoped at releases/<id>/intake/
- Version format: {slug}-v{N} (e.g., mvp-v1, mvp-v1.1)
- Uses focused release by default
- Each release has independent intake versions
</notes>
