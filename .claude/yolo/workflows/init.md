<purpose>
Initialize the YOLO workflow system in a project.
Creates the .planning/ directory structure, state.yaml, and config.yaml.
Detects project type and commits the initial setup.
</purpose>

<triggers>
- `/yolo:init` - Initialize YOLO in the current project
- `/init --recover` - Recover corrupted state from backup or filesystem scan
</triggers>

<process>

<step name="check_existing">
Check if YOLO is already initialized:

```bash
if [ -d ".planning" ]; then
  echo "YOLO is already initialized in this project."
  echo ""
  echo "Directory: .planning/"
  echo ""
  echo "Options:"
  echo "  [reinitialize] — Destroy existing .planning/ and start fresh (DESTRUCTIVE)"
  echo "  [skip]         — Keep existing, skip initialization"
  echo "  [abort]        — Cancel operation"
  echo ""
  echo "Choose an option:"
fi
```

**If reinitialize chosen:**
```bash
echo "WARNING: This will delete all existing planning data."
echo "This includes releases, features, debug sessions, and state."
echo ""
echo "Type 'confirm-reinit' to proceed:"

# Wait for confirmation
if [ "$CONFIRM" == "confirm-reinit" ]; then
  rm -rf .planning/
  echo "Existing .planning/ removed."
else
  echo "Reinitialize cancelled."
  exit 0
fi
```

**If skip or abort chosen:**
```bash
echo "Initialization skipped."
exit 0
```
</step>

<step name="detect_project">
Detect project type and name from common project files:

```bash
PROJECT_NAME=""
PROJECT_TYPE=""

# Node.js / TypeScript
if [ -f "package.json" ]; then
  PROJECT_NAME=$(cat package.json | yq -p json '.name // ""')
  if [ -f "tsconfig.json" ]; then
    PROJECT_TYPE="typescript"
  else
    PROJECT_TYPE="javascript"
  fi
fi

# Go
if [ -f "go.mod" ]; then
  PROJECT_NAME=$(head -1 go.mod | awk '{print $2}' | xargs basename)
  PROJECT_TYPE="go"
fi

# Rust
if [ -f "Cargo.toml" ]; then
  PROJECT_NAME=$(cat Cargo.toml | yq -p toml '.package.name // ""')
  PROJECT_TYPE="rust"
fi

# Python
if [ -f "pyproject.toml" ]; then
  PROJECT_NAME=$(cat pyproject.toml | yq -p toml '.project.name // .tool.poetry.name // ""')
  PROJECT_TYPE="python"
elif [ -f "setup.py" ] || [ -f "setup.cfg" ]; then
  PROJECT_TYPE="python"
fi

# Fallback to directory name
if [ -z "$PROJECT_NAME" ]; then
  PROJECT_NAME=$(basename "$(pwd)")
fi

if [ -z "$PROJECT_TYPE" ]; then
  PROJECT_TYPE="unknown"
fi

echo "Detected project: ${PROJECT_NAME} (${PROJECT_TYPE})"
```
</step>

<step name="create_directories">
Create all required YOLO directories:

```bash
mkdir -p .planning/releases
mkdir -p .planning/features
mkdir -p .planning/do
mkdir -p .planning/debug
mkdir -p .planning/archive
mkdir -p .planning/decisions

echo "Created directory structure:"
echo "  .planning/"
echo "  .planning/releases/"
echo "  .planning/features/"
echo "  .planning/do/"
echo "  .planning/debug/"
echo "  .planning/archive/"
echo "  .planning/decisions/"
```
</step>

<step name="create_state">
Create `.planning/state.yaml` with the full initial template:

```bash
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
```

```yaml
# .planning/state.yaml — YOLO project state
# Created by /yolo:init

lock:
  held_by: null
  acquired_at: null
  expires_at: null

releases: []

focus:
  release: null
  feature: null
  feature_release: null

feature:
  id: null
  release: null
  status: null
  started_at: null
  tasks:
    total: 0
    completed: 0
    current: null

session:
  last_activity: ${TIMESTAMP}
  last_action: "init"
  last_error: null
  resume:
    context: null

_checksum: ${COMPUTED}
updated_at: ${TIMESTAMP}
updated_by: init
```

Compute initial checksum:

```bash
_checksum=$(sha256sum .planning/state.yaml | cut -d' ' -f1)
yq -i "._checksum = \"${_checksum}\"" .planning/state.yaml
```
</step>

<step name="create_config">
Create `.planning/config.yaml` with the default balanced profile:

```yaml
# .planning/config.yaml — YOLO configuration
# Created by /yolo:init

project:
  name: "${PROJECT_NAME}"
  type: "${PROJECT_TYPE}"

profile: balanced

# Profile settings (balanced defaults)
settings:
  research:
    depth: deep
    include_external: true
  planning:
    max_tasks: 5
    require_verification: true
  execution:
    atomic_commits: true
    auto_fix: true
    max_retries: 1
  verification:
    strict: false
    run_tests: true

# Git settings
git:
  auto_commit: true
  commit_prefix: true
  branch_per_feature: false

# Constraints
constraints:
  max_active_do_tasks: 3
  max_active_debug_sessions: 3
  max_tasks_per_plan: 5
```
</step>

<step name="git_check">
Verify git is initialized before committing:

```bash
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "WARNING: Not a git repository."
  echo "Initialize git first with: git init"
  echo ""
  echo "YOLO directory structure created but not committed."
  echo "Run 'git init && git add .planning/ && git commit -m \"chore: initialize YOLO workflow system\"' when ready."
  exit 0
fi
```
</step>

<step name="git_commit">
Stage and commit the initialization:

```bash
git add .planning/state.yaml
git add .planning/config.yaml

# Add .gitkeep files to preserve empty directories
touch .planning/releases/.gitkeep
touch .planning/features/.gitkeep
touch .planning/do/.gitkeep
touch .planning/debug/.gitkeep
touch .planning/archive/.gitkeep
touch .planning/decisions/.gitkeep

git add .planning/releases/.gitkeep
git add .planning/features/.gitkeep
git add .planning/do/.gitkeep
git add .planning/debug/.gitkeep
git add .planning/archive/.gitkeep
git add .planning/decisions/.gitkeep

git commit -m "chore: initialize YOLO workflow system"
```
</step>

<step name="display_success">
Display initialization success and next steps:

```
═══════════════════════════════════════════════════════════════
YOLO INITIALIZED
═══════════════════════════════════════════════════════════════

Project:  ${PROJECT_NAME} (${PROJECT_TYPE})
Profile:  balanced
Location: .planning/

Structure created:
  .planning/
  ├── state.yaml          — Project state tracking
  ├── config.yaml         — YOLO configuration
  ├── releases/           — Release planning
  ├── features/           — Standalone features
  ├── do/                 — Ad-hoc tasks
  ├── debug/              — Debug sessions
  ├── archive/            — Completed work
  └── decisions/          — Decision records

───────────────────────────────────────────────────────────────
NEXT STEPS:
  /yolo:release new <name>  — Create a release (for planned work)
  /yolo:do <task>           — Quick ad-hoc task
  /yolo:debug <issue>       — Start debugging an issue
═══════════════════════════════════════════════════════════════
```
</step>

<step name="recover_state">
**Recovery mode (--recover flag):**

```bash
# Check if --recover flag is set
if [ "$RECOVER_FLAG" != "true" ]; then
  # Skip — normal init path
  continue
fi

echo "═══════════════════════════════════════════════════════════════"
echo "STATE RECOVERY"
echo "═══════════════════════════════════════════════════════════════"
```

**Step 1: Try backup restoration**

```bash
if [ -f ".planning/state.yaml.bak" ]; then
  echo "Found backup: .planning/state.yaml.bak"

  # Validate backup checksum
  BAK_CHECKSUM=$(cat .planning/state.yaml.bak | yq '._checksum')
  COMPUTED=$(cat .planning/state.yaml.bak | yq 'del(._checksum, .lock)' | sha256sum | cut -d' ' -f1)

  if [ "sha256:${COMPUTED}" = "${BAK_CHECKSUM}" ]; then
    echo "Backup is valid — restoring"
    cp .planning/state.yaml.bak .planning/state.yaml
    echo "State restored from backup"
    # Done — skip filesystem scan
    exit 0
  else
    echo "Backup checksum invalid — falling back to filesystem scan"
  fi
fi
```

**Step 2: Filesystem scan (if no valid backup)**

```bash
echo "Scanning filesystem to rebuild state..."

# Scan releases
RELEASES=()
for dir in .planning/releases/*/; do
  if [ -f "${dir}release.yaml" ]; then
    RELEASE_ID=$(basename "$dir")
    RELEASE_STATUS=$(cat "${dir}release.yaml" | yq '.status')
    RELEASES+=("${RELEASE_ID}:${RELEASE_STATUS}")
    echo "  Found release: ${RELEASE_ID} (${RELEASE_STATUS})"
  fi
done

# Scan standalone features
STANDALONE=()
for dir in .planning/features/*/; do
  if [ -f "${dir}feature.yaml" ]; then
    FEATURE_ID=$(basename "$dir")
    FEATURE_STATUS=$(cat "${dir}feature.yaml" | yq '.status')
    STANDALONE+=("${FEATURE_ID}:${FEATURE_STATUS}")
    echo "  Found standalone feature: ${FEATURE_ID} (${FEATURE_STATUS})"
  fi
done

# Scan release features for progress
for dir in .planning/releases/*/; do
  RELEASE_ID=$(basename "$dir")
  TOTAL=0
  COMPLETED=0
  for fdir in "${dir}features/*/"; do
    if [ -f "${fdir}feature.yaml" ]; then
      TOTAL=$((TOTAL + 1))
      STATUS=$(cat "${fdir}feature.yaml" | yq '.status')
      if [ "$STATUS" = "completed" ]; then
        COMPLETED=$((COMPLETED + 1))
      fi
    fi
  done
done
```

**Step 3: Rebuild state.yaml**

Build state.yaml from discovered data:
- Set `focus.release` to null (user must re-focus)
- Set `focus.feature` to null
- Populate `releases[]` from discovered releases
- Populate `standalone_features` from discovered features
- Clear `session` context
- Compute and set `_checksum`

**Step 4: Report**

```
═══════════════════════════════════════════════════════════════
STATE RECOVERED
═══════════════════════════════════════════════════════════════

Method: ${backup_restored ? "Backup" : "Filesystem scan"}
Releases: ${RELEASE_COUNT} found
Features: ${FEATURE_COUNT} standalone found

⚠ Focus has been cleared. Re-focus with:
  /yolo:release focus <release-id>

═══════════════════════════════════════════════════════════════
```
</step>

</process>

<error_handling>

On any failure path, record `session.last_error` in state.yaml with the error details before exiting (XC-003).
Note: If state.yaml does not yet exist (failure during creation), log the error to stderr instead.

**Git not initialized:**
```
WARNING: Not a git repository.

YOLO directory structure was created at .planning/ but not committed.

To complete setup:
  1. git init
  2. git add .planning/
  3. git commit -m "chore: initialize YOLO workflow system"
```

**Permission errors:**
```
ERROR: Cannot create .planning/ directory.

Check file system permissions for the current directory:
  ls -la .

Ensure you have write access to: $(pwd)
```

**Already initialized (without confirmation):**
```
YOLO is already initialized.

Location: .planning/

To check status:  /yolo:status
To reinitialize:  /yolo:init (then choose "reinitialize")
```

</error_handling>

<invariants>
- Never overwrite existing .planning/ without explicit user confirmation ("confirm-reinit")
- state.yaml always created with valid initial structure and computed checksum
- config.yaml always created with balanced profile defaults
- Empty directories preserved via .gitkeep files
- Git commit only attempted if inside a git repository
- Project type detection is best-effort — falls back to "unknown"
</invariants>
