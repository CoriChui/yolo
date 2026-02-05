<purpose>
Compare two intake versions within a release.
Versions must belong to the same release (same slug prefix).
Uses focused release by default.
</purpose>

<triggers>
- `/intake diff <v1> <v2>` - Compare two versions within focused release
- `/intake diff mvp-v1 mvp-v1.1` - Compare mvp-v1 to mvp-v1.1
- `/intake diff mvp-v1 mvp-v1.1 --release 2026-02-04-mvp` - Explicit release
</triggers>

<process>

<step name="determine_target_release">
Determine which release the versions belong to:

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
RELEASE_SLUG=$(echo "$RELEASE_ENTRY" | yq '.slug')
INTAKE_BASE="releases/${TARGET_RELEASE}/intake"
```
</step>

<step name="validate_versions">
Verify both versions exist in the release's intake:

```bash
V1="mvp-v1"
V2="mvp-v1.1"

if [ ! -d "${INTAKE_BASE}/${V1}" ]; then
  echo "Version ${V1} not found in release ${TARGET_RELEASE}"
  exit 1
fi

if [ ! -d "${INTAKE_BASE}/${V2}" ]; then
  echo "Version ${V2} not found in release ${TARGET_RELEASE}"
  exit 1
fi
```
</step>

<step name="compare_file_lists">
# Note: Temp file usage is a read-only implementation detail
Get file lists for both versions:

```bash
# Use mktemp for safe temp file paths
V1_FILES=$(mktemp)
V2_FILES=$(mktemp)
trap "rm -f $V1_FILES $V2_FILES" EXIT

# List all files in each version
find "${INTAKE_BASE}/${V1}" -type f | sed "s|${INTAKE_BASE}/${V1}/||" | sort > "$V1_FILES"
find "${INTAKE_BASE}/${V2}" -type f | sed "s|${INTAKE_BASE}/${V2}/||" | sort > "$V2_FILES"

# Find differences
ADDED=$(comm -23 "$V2_FILES" "$V1_FILES")     # In v2 but not v1
REMOVED=$(comm -13 "$V2_FILES" "$V1_FILES")   # In v1 but not v2
COMMON=$(comm -12 "$V2_FILES" "$V1_FILES")    # In both
```
</step>

<step name="detect_modifications">
For files in both versions, check for content differences:

```bash
MODIFIED=""
while read file; do
  if ! diff -q "${INTAKE_BASE}/${V1}/${file}" "${INTAKE_BASE}/${V2}/${file}" > /dev/null 2>&1; then
    MODIFIED="${MODIFIED}${file}\n"
  fi
done <<< "$COMMON"
```
</step>

<step name="display_diff">
Format and display differences:

```
═══════════════════════════════════════════════════════════════
DIFF: ${V1} → ${V2}
═══════════════════════════════════════════════════════════════

Release: ${TARGET_RELEASE}
Location: releases/${TARGET_RELEASE}/intake/

ADDED (1 file):
  + notes/new-requirement.md

MODIFIED (1 file):
  ~ figma/digest.md

REMOVED (0 files):
  (none)

───────────────────────────────────────────────────────────────
SUMMARY:
  ${V1}:   20 files
  ${V2}:   21 files (+1)
───────────────────────────────────────────────────────────────
```
</step>

<step name="show_file_diff" condition="--verbose or specific file requested">
Show actual content diff for a file:

```bash
diff --color=always "${INTAKE_BASE}/${V1}/${FILE}" "${INTAKE_BASE}/${V2}/${FILE}"
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
       /intake diff mvp-v1 mvp-v1.1 --release 2026-02-04-mvp

Use /release list to see all releases.
═══════════════════════════════════════════════════════════════
```

**Version not found:**
```
═══════════════════════════════════════════════════════════════
VERSION NOT FOUND: ${VERSION}
═══════════════════════════════════════════════════════════════

Version '${VERSION}' not found in release ${TARGET_RELEASE}.

Available versions for ${TARGET_RELEASE}:
  mvp-v1      (2026-02-03)
  mvp-v1.1    (2026-02-10) ← current

Use /intake list to see all versions.
═══════════════════════════════════════════════════════════════
```

**Same version:**
```
Cannot diff version with itself.
Usage: /intake diff <version1> <version2>
```

**Wrong release prefix:**
```
═══════════════════════════════════════════════════════════════
VERSION MISMATCH
═══════════════════════════════════════════════════════════════

Versions must belong to the same release.

Provided: mobile-v1, mvp-v1.1
These belong to different releases.

To compare versions within a release:
  /intake diff mvp-v1 mvp-v1.1
═══════════════════════════════════════════════════════════════
```

</error_handling>

<options>
- `--release <id>` - Compare versions in specific release
- `--verbose` - Show full file diffs, not just summary
- `--file <path>` - Show diff for specific file only
</options>

<notes>
- Versions must belong to the same release
- Version format: {slug}-v{N} (e.g., mvp-v1, mvp-v1.1)
- Intake lives at releases/<id>/intake/
- Uses focused release by default
</notes>
