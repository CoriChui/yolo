# Init Workflow
# Command: /init

Initialize YOLO in the current project. Read `.planning/state.yaml` before any operation — if it exists, validate it is valid YAML.

---

## /init

### Process

1. **Check existing:** If `.planning/` exists, check for partial state (e.g., `state.yaml` missing but `releases/` present). If partial, warn user and ask: repair (fill missing files), reinitialize (destructive), or skip. If fully intact, ask: reinitialize (destructive) or skip.

2. **Detect project:** Read `package.json`, `go.mod`, `Cargo.toml`, or `pyproject.toml` for name and type. Fallback to directory name.

3. **Create structure:**
   ```
   .planning/
   ├── state.yaml
   ├── config.yaml
   ├── decisions/
   └── releases/
   ```

4. **Write state.yaml:**
   ```yaml
   updated_at: {timestamp}
   focus:
     release: null
     feature: null
   releases: []
   session:
     last_action: "init"
     resume: null
   ```

5. **Write config.yaml:**
   ```yaml
   project:
     name: "{name}"
     type: "{type}"
   agents:
     research: opus
     plan: opus
     execute: sonnet
     verify: haiku
     feature-breakdown: opus
     decide: opus
   limits:
     max_tasks_per_feature: 5
     max_features_per_release: 12
     estimated_tasks_range: [2, 8]
   intake:
     max_files: 200
   ```

6. **Git commit:** `chore: initialize YOLO workflow system`

7. **Report** with next steps: `/yolo:release new <name>`.

---

## Notes

- Never overwrite existing `.planning/` without explicit user confirmation
- Git commit only attempted if inside a git repository
- Project type detection is best-effort — falls back to "unknown"
