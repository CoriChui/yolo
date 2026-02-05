<purpose>
Display release-scoped intake version status and contents.
Uses focused release by default, can override with --release flag.
Intake is auxiliary context — codebase is the source of truth.
</purpose>

<triggers>
- `/intake status` - Show intake state for focused release
- `/intake status --release 2026-02-04-mvp` - Show intake for specific release
</triggers>

<process>

<step name="determine_target_release">
Determine which release to show intake for:

```bash
# Check for --release flag override
if [ -n "$RELEASE_FLAG" ]; then
  TARGET_RELEASE="$RELEASE_FLAG"
else
  # Use focused release from state
  TARGET_RELEASE=$(cat .planning/state.yaml 2>/dev/null | yq '.focus.release')
fi

# Validate release exists
RELEASE_ENTRY=$(cat .planning/state.yaml | yq ".releases[] | select(.id == \"${TARGET_RELEASE}\")")
if [ -z "$RELEASE_ENTRY" ]; then
  # Show error - release not found
  exit 1
fi
```
</step>

<step name="load_state">
# Note: RELEASE_ENTRY is resolved in determine_target_release and reused here
Read release intake state:

```bash
RELEASE_ENTRY=$(cat .planning/state.yaml | yq ".releases[] | select(.id == \"${TARGET_RELEASE}\")")
RELEASE_SLUG=$(echo "$RELEASE_ENTRY" | yq '.slug')
INTAKE_VERSION=$(echo "$RELEASE_ENTRY" | yq '.intake.current')
INTAKE_LOCKED=$(echo "$RELEASE_ENTRY" | yq '.intake.locked')
```
</step>

<step name="load_manifest">
Read current version manifest from release's intake directory:

```bash
# Intake lives inside release directory
INTAKE_DIR="releases/${TARGET_RELEASE}/intake/${INTAKE_VERSION}"
cat "${INTAKE_DIR}/manifest.yaml"
```

Extract:
- `type` - major | patch
- `created` - creation date
- `sources` - source list
- `stats` - counts
- `parent` - parent version (for patches)
</step>

<step name="count_contents">
Count files in each source:

```bash
INTAKE_DIR="releases/${TARGET_RELEASE}/intake/${INTAKE_VERSION}"
for source in figma notion notes; do
  COUNT=$(ls -1 "${INTAKE_DIR}/${source}/" 2>/dev/null | wc -l)
  echo "${source}: ${COUNT} files"
done
```
</step>

<step name="display_status">
Format and display status:

```
═══════════════════════════════════════════════════════════════
INTAKE STATUS
═══════════════════════════════════════════════════════════════

Release:  ${TARGET_RELEASE}
Version:  ${INTAKE_VERSION} (patch from ${PARENT})
Created:  2026-02-10
Locked:   $([ "$INTAKE_LOCKED" = "true" ] && echo "yes (release completed)" || echo "no")

Location: releases/${TARGET_RELEASE}/intake/${INTAKE_VERSION}/

Sources:
  figma/:   12 files
  notion/:  5 files
  notes/:   3 files
  ─────────────────────
  Total:    20 files

This intake is AUXILIARY context.
Codebase remains the source of truth.

═══════════════════════════════════════════════════════════════
COMMANDS:
  /intake diff ${SLUG}-v1 ${INTAKE_VERSION}  — Compare with previous
  /intake list                               — List all versions
  /intake capture                            — Capture new source
═══════════════════════════════════════════════════════════════
```
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
       /intake status --release 2026-02-04-mvp

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

**No intake captured:**
```
═══════════════════════════════════════════════════════════════
NO INTAKE FOR RELEASE
═══════════════════════════════════════════════════════════════

Release ${TARGET_RELEASE} has no intake captured yet.

Intake is OPTIONAL auxiliary context.
Releases can work directly from codebase.

Use /intake capture to create intake:
  /intake capture notion     — From Notion pages
  /intake capture figma      — From Figma MCP
═══════════════════════════════════════════════════════════════
```

**Manifest missing:**
```
Intake ${INTAKE_VERSION} directory exists but manifest.yaml is missing.
The intake may be corrupted. Consider:
  /intake capture    — Create fresh intake
```

</error_handling>

<notes>
- Intake is optional — releases work without it
- Intake is RELEASE-SCOPED at releases/<id>/intake/
- Version format: {slug}-v{N} (e.g., mvp-v1, mvp-v1.1)
- Uses focused release by default, override with --release flag
- Codebase is the source of truth
- Intake provides auxiliary context (designs, requirements)
- Each release has independent intake
</notes>
