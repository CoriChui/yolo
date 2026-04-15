# Init Workflow
# Command: /yolo:init

Initialize YOLO in the current project. Check if `.planning/state.yaml` exists. If it exists, validate it is valid YAML and proceed to the repair/reinitialize flow (step 1). If not, proceed with fresh initialization (step 2+).

---

## /init

### Process

1. **Check existing:** If `.planning/` exists, check for partial state (e.g., `state.yaml` missing but `releases/` present). If partial, warn user and ask: repair (fill missing files), reinitialize (destructive), or skip. **On repair:** fill missing files with defaults, then also run the schema validation from step 6 on `state.yaml` (whether existing or newly created) to catch corruption or missing fields. Also validate `config.yaml` schema. If fully intact, validate `config.yaml` schema — check for missing fields (e.g., `limits.max_teammates`, `intake.max_files`) and add them with defaults if absent. Then ask: reinitialize (destructive) or skip.

2. **Detect project:** Read the project's build config (e.g., `package.json`, `go.mod`, `Cargo.toml`, `pyproject.toml`, `Makefile`, etc.) for name and type. Fallback to directory name.

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
     run_active: false
     run_started_at: null
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
     debug: opus
   limits:
     max_tasks_per_feature: 5
     max_features_per_release: 12
     max_teammates: 4
   intake:
     max_files: 200
   ```

   **Validate config.yaml:** Verify agent model names are from the known set (`opus`, `sonnet`, `haiku`). If any model name is unrecognized, warn user: "Unknown model name '{name}' in config.yaml agents.{key}. Valid models: opus, sonnet, haiku. Fix before running workflows." via AskUserQuestion.

6. **Validate state.yaml:** Re-read `state.yaml` and verify all required fields exist: `updated_at`, `focus.release`, `focus.feature`, `releases` (array), `session.run_active`, `session.run_started_at`, `session.last_action`, `session.resume`. If any field is missing, add it with default value, set `updated_at` to a fresh timestamp, and re-write.

7. **Git commit (if changes exist):** Check `git status --porcelain .planning/` — if no changes, skip commit. Otherwise: `chore: initialize YOLO workflow system`

8. **Report** with next steps: `/yolo:release new <name>`.

---

## Notes

- Never overwrite existing `.planning/` without explicit user confirmation
- Git commit only attempted if inside a git repository
- Project type detection is best-effort — falls back to "unknown"
