# Plan — yolo-debug (a stateless debugging act)

Turns the committed brief + research into executable tasks. This is a **docs/skill
framework**: "tests" are objective consistency/behavioral checks (frontmatter validity,
routing-text assertions, template↔CLAUDE.md parity, a behavioral routing scenario), leaning
on `docs/validation/` — not unit tests. The one code-level harness
(`docs/validation/git-acceptance/run.sh`) is a **regression guard**: debug does not touch
status derivation, so it must stay green (26/26), and no new assertion is added to it.

## Decisions resolved (carried into the tasks; confirm at the plan gate)

- **Artifact path:** `workspace/debug/<YYYY-MM-DD>-<slug>.md` — a *standalone record* sibling
  to `workspace/decisions/`, per research (`research.md:199-212`, `conventions.md:16-18`).
  One file. NO new trailer, NO status field, invisible to status derivation
  (`research.md:222-237`).
- **Commit:** the record commits `yolo: debug <slug>` (framework form,
  `conventions.md:54-58`); the actual fix lands as ordinary descriptive task commit(s) — no
  per-phase framework commits (`research.md:88`).
- **Branch policy:** yolo-debug operates on the **current branch**. There is deliberately NO
  `debug/<slug>` branch convention (`conventions.md` only defines `feature/<slug>`); a fix is
  usually wanted immediately on whatever branch. Offer a branch only if the fix is large
  (`research.md:243-248`).
- **Slug, no brief:** bug intent gets a **slug** (for the artifact filename, kebab-case per
  `yolo-feature/SKILL.md:13`) but **NO brief** — a brief implies a feature with
  `success_criteria`. The debug record IS the artifact (`research.md:253-256`).
- **Hand-off:** when a fix balloons into new capability, yolo-debug **hands off to
  yolo-feature** rather than growing the fix. Stated crisply in both the skill and the
  routing block (`brief.md:38-39`, `research.md:249-252`).
- **Config tier (`agents.debug`):** RECOMMEND adding a `debug:` tier to config for
  enumeration consistency with the other standalone acts that carry tiers (`decide`,
  `roadmap`). Cheap, and it documents the intended model for the investigation. See
  `open_questions_for_gate` — this is the one genuinely optional task (config-debug-tier).
- **Init scaffold:** RECOMMEND yolo-init also create `workspace/debug/` (one line) so the dir
  exists in fresh/repaired repos; the skill also `mkdir -p`s defensively so it never depends
  on a re-init. (`research.md:265-267`.)

## Open questions for the plan gate

1. **`agents.debug` tier — add or run inline?** Recommend add (consistency); drop
   `config-debug-tier` if you prefer inline-at-caller's-tier like a bare invocation. Low cost
   either way.
2. **Init scaffold vs lazy mkdir only.** Recommend both (init adds the dir; skill mkdir -p as
   backstop). If you want the smallest surface, drop `init-scaffold-debug-dir` and rely on the
   skill's mkdir alone.
3. **Failing-test-first strictness.** Skill uses a strong default ("write the failing test")
   with an explicit documented escape for non-unit-testable bugs (config/perf/flaky),
   recorded in the artifact (`research.md:268-271`). Confirm this degradation is intended.

```yaml
tasks:
  - id: conventions-debug-record
    title: "Register the debug record as a standalone artifact in conventions.md"
    description: >
      Add the debug record to the "Standalone records live outside the feature folder" list
      in conventions.md: `workspace/debug/<YYYY-MM-DD>-<slug>.md` — debug records (written by
      yolo-debug). State explicitly that a debug record has no brief, no feature/<slug>
      branch, no status field and no trailer, so it is invisible to and independent of status
      derivation. Add a one-line note that yolo-debug runs on the current branch (no
      `debug/<slug>` branch convention). This is the cite target the skill points at instead
      of paraphrasing.
    files: [".claude/yolo/conventions.md"]
    test_spec: >
      Consistency assertion: conventions.md "Standalone records" section now lists a
      workspace/debug/ path AND names yolo-debug as its writer; grep confirms the phrase
      "no `debug/` branch" (or equivalent) is present; the Trailers table is UNCHANGED (no
      new trailer added).
    relevant_tests: ["docs/validation/git-acceptance/run.sh"]
    verification: "grep shows workspace/debug/ in the Standalone records list; trailer table untouched"
    depends_on: []

  - id: debug-skill
    title: "Write the yolo-debug SKILL.md (the stateless act)"
    description: >
      Create .claude/skills/yolo-debug/SKILL.md mirroring the yolo-decide / yolo-research
      shape (research.md:97-136). Frontmatter: only name + description; description opens
      "Use when…" and ends with concrete "Triggers on" quotes (e.g. "fix the 500 on login",
      "why is X breaking?", "debug this failure"). Body (~20-25 lines, terse/imperative,
      second person): one-line purpose; ## Inputs (a bug report / failing behaviour; derive a
      kebab-case slug, NO brief); ## Procedure = reproduce → hypothesize → isolate → fix →
      verify, carrying the v2 "Iron Law" evidence-chain discipline (no root-cause claim
      without a file:line evidence chain; no fix without a failing reproducer; no
      symptom-fixing — research.md:76-81) and a CONDENSED Discipline block adapting v2's
      rationalizations table + Red Flags (research.md:31-35,82) — the value v4 currently
      lacks. Failing-test-first is the strong default with a documented escape for
      non-unit-testable bugs, recorded in the artifact. ## Output: write exactly ONE artifact
      workspace/debug/<YYYY-MM-DD>-<slug>.md (mkdir -p defensively) with symptom+reproducer,
      evidence chain (file:line), one-sentence root cause + confidence, the fix
      (files/minimal change/over-scope traps avoided), and verification evidence (failing
      test now green, reproducer no longer reproduces, suite green); commit `yolo: debug
      <slug>`; the fix lands as ordinary task commit(s). ## Constraints: cite conventions.md
      for commit form + cite-don't-paraphrase + the standalone-record path (NO restated
      trailer strings); NO status field, NO new trailer, NO persistent session state; runs on
      the current branch; HAND OFF to yolo-feature when the fix becomes new capability.
    files: [".claude/skills/yolo-debug/SKILL.md"]
    test_spec: >
      Objective checks: file parses as valid Markdown with a YAML frontmatter block carrying
      exactly `name: yolo-debug` and a `description:` that starts with "Use when" and contains
      "Triggers on"; body contains the five-step arc (reproduce/hypothesize/isolate/fix/
      verify); body contains at least one literal ".claude/yolo/conventions.md" citation and
      does NOT restate any `YOLO-*` trailer string verbatim; body contains "yolo: debug"; body
      contains NO "session.yaml", "status:", or "state.yaml" (stateless assertion); body
      names a yolo-feature hand-off. Behavioral (Layer 3): an agent given only this SKILL +
      conventions, handed "fix the 500 on login", runs the arc and writes ONE
      workspace/debug/ artifact + `yolo: debug` commit — no brief, no status file.
    relevant_tests: [".claude/skills/yolo-decide/SKILL.md", ".claude/skills/yolo-research/SKILL.md"]
    verification: "Frontmatter valid + description auto-triggers; body is stateless, cites conventions, one artifact, hand-off stated"
    depends_on: ["conventions-debug-record"]

  - id: routing-bug-line
    title: "Flip the routing block 'Bug reports' line to a positive route to yolo-debug"
    description: >
      In BOTH the template (.claude/yolo/templates/claude-routing-block.md) AND the synced
      CLAUDE.md block, replace the current "Bug reports … v4 has no `debug` act yet, so fix
      directly (a `yolo-debug` skill is a known gap)." negative with a POSITIVE route: bug
      reports ("X is broken", "fix the 500 on login") route to `yolo-debug` for a systematic
      reproduce→fix→verify pass; trivial one-line fixes still stay below the ceremony
      threshold; and when a fix turns out to need new capability, hand off to `yolo-feature`.
      Move it out of / reframe it within the "Does NOT route" taxonomy accordingly, and add
      `yolo-debug` to the "Other intents" enumeration. Edit BOTH files identically (yolo-init
      only re-syncs on next init/repair). Keep the two blocks byte-identical between the
      markers.
    files: [".claude/yolo/templates/claude-routing-block.md", "CLAUDE.md"]
    test_spec: >
      Assertions: neither file contains "no `debug` act" / "known gap"; both contain a
      positive "→ `yolo-debug`" route for bug intent and a "yolo-feature" hand-off mention;
      the content between the <!-- YOLO:routing-block start/end --> markers is IDENTICAL in
      template and CLAUDE.md (diff of the extracted blocks is empty). Behavioral: "fix the 500
      on login" → yolo-debug while "add CSV export" still → yolo-feature.
    relevant_tests: ["docs/validation/behavioral/scenarios.md"]
    verification: "Both blocks route bug intent to yolo-debug, are byte-identical, and no longer say 'no debug act'"
    depends_on: ["debug-skill"]

  - id: readme-getting-started
    title: "Add yolo-debug to the README skills table and getting-started"
    description: >
      README.md: add a `yolo-debug` row to the skills table (e.g. "you have a bug and want a
      systematic reproduce→fix→verify pass"); do NOT add it to the `yolo-feature` lifecycle
      composition sentence (it is standalone, like decide/status). getting-started.md: add a
      bullet under "Other things you can say" (e.g. **"debug this failure" / "why is X
      breaking?"** → yolo-debug, records under workspace/debug/), and — if init-scaffold-debug-dir
      is accepted — update the "scaffolds workspace/{features,intake,decisions}/" prose here and
      in README to include `debug`.
    files: ["README.md", ".claude/yolo/getting-started.md"]
    test_spec: >
      Assertions: README skills table contains a `yolo-debug` row; README lifecycle sentence
      does NOT list debug among the composed acts; getting-started "Other things you can say"
      contains a yolo-debug bullet naming workspace/debug/. (If init task accepted:
      "workspace/{features,intake,decisions,debug}" appears in both scaffold-mention strings.)
    relevant_tests: ["docs/validation/ab-judge/rubric.md"]
    verification: "README table + getting-started list yolo-debug as a standalone act"
    depends_on: ["debug-skill"]

  - id: init-scaffold-debug-dir
    title: "Scaffold workspace/debug/ in yolo-init"
    description: >
      Update .claude/skills/yolo-init/SKILL.md step 1 to also create `workspace/debug/` (with
      a .gitkeep where empty), alongside features/intake/decisions, so fresh and repaired
      repos have the dir. Backstop only — the skill mkdir -p's on first use regardless.
      OPTIONAL per open question 2; drop if you prefer lazy-create only.
    files: [".claude/skills/yolo-init/SKILL.md"]
    test_spec: >
      Assertion: yolo-init step 1 enumerates workspace/debug/ among the created dirs.
    relevant_tests: [".claude/skills/yolo-init/SKILL.md"]
    verification: "yolo-init creates workspace/debug/"
    depends_on: []

  - id: config-debug-tier
    title: "Add an agents.debug model tier to config"
    description: >
      Add a `debug:` key under `agents:` in BOTH .claude/yolo/templates/config.yaml and the
      scaffolded workspace/config.yaml (recommend `opus`, matching the investigation-heavy
      decide/roadmap tiers), with a one-line comment. Keeps the billed-step enumeration
      complete. OPTIONAL per open question 1; drop if yolo-debug runs inline at the caller's
      tier.
    files: [".claude/yolo/templates/config.yaml", "workspace/config.yaml"]
    test_spec: >
      Assertion: both config files parse as valid YAML and contain agents.debug; the two
      agents blocks stay consistent.
    relevant_tests: [".claude/yolo/templates/config.yaml"]
    verification: "agents.debug present in template and scaffolded config"
    depends_on: []

  - id: decision-actioned-note
    title: "Note the fired revisit trigger in the auto-vs-explicit-routing decision"
    description: >
      Append a short note to workspace/decisions/auto-vs-explicit-routing.md that its
      "`yolo-debug` skill lands → update the taxonomy" revisit trigger has now fired and been
      actioned (bug intent routes to yolo-debug). Decision records are provenance
      (conventions.md:16-18); this keeps the trail honest. Low priority.
    files: ["workspace/decisions/auto-vs-explicit-routing.md"]
    test_spec: >
      Assertion: the record notes the yolo-debug revisit trigger as actioned/fired.
    relevant_tests: ["workspace/decisions/auto-vs-explicit-routing.md"]
    verification: "Decision record records the trigger firing"
    depends_on: ["routing-bug-line"]

  - id: validation-consistency
    title: "Add a bug-routing behavioral scenario and run the full consistency check"
    description: >
      Add a scenario to docs/validation/behavioral/scenarios.md: fixture = YOLO repo; intent =
      "fix the 500 on login"; expected decision = route to yolo-debug (systematic
      reproduce→fix→verify, one workspace/debug/ artifact, no brief), while feature intent
      still routes to yolo-feature — source of truth: routing block + yolo-debug SKILL. Then
      run the consistency pass mapping to brief success_criteria: (a) SKILL frontmatter valid
      & discoverable as a yolo-* act; (b) stateless — no session/status/state strings, one
      committed artifact; (c) cites conventions.md, no restated trailers; (d) routing block no
      longer says "no debug act" and routes bug intent to yolo-debug, README + getting-started
      updated; (e) the bug-prompt scenario routes to yolo-debug while feature intent routes to
      yolo-feature. Confirm git-acceptance/run.sh is still green (regression guard — debug
      doesn't touch derivation).
    files: ["docs/validation/behavioral/scenarios.md"]
    test_spec: >
      New behavioral scenario row present and passes on repeated runs; the five
      success_criteria assertions above all hold; bash docs/validation/git-acceptance/run.sh
      exits 0 (unchanged 26/26).
    relevant_tests: ["docs/validation/behavioral/scenarios.md", "docs/validation/git-acceptance/run.sh"]
    verification: "All 5 brief success_criteria assert true; git-acceptance stays green"
    depends_on: ["conventions-debug-record", "debug-skill", "routing-bug-line", "readme-getting-started", "init-scaffold-debug-dir", "config-debug-tier", "decision-actioned-note"]

# This is a prompt/skill framework, not an app. There is no lint/test toolchain; the objective
# harness below is a regression guard (debug doesn't touch status derivation, so it stays green).
lint_commands: []
test_commands: ["bash docs/validation/git-acceptance/run.sh"]
```
