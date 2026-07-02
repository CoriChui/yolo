# Verification — yolo-debug

Checked against the 5 `success_criteria` in `workspace/features/yolo-debug/brief.md`.
Criteria 1–4 verified with shell (grep/diff); criterion 5 by simulated-agent reasoning.

## SC1 — Skill exists + valid frontmatter + discoverable — **PASS**

`.claude/skills/yolo-debug/SKILL.md` has YAML frontmatter:

```
name: yolo-debug
description: Use when a reported problem, failure, or bug needs a systematic root-cause
investigation — reproduce → isolate → fix → verify — recorded as one durable artifact.
Triggers on "fix the 500 on login", "X is broken", "why is Y failing?", "debug this",
"track down this bug".
```

- `name: yolo-debug` — present.
- `description:` begins with "Use when" (grep confirmed `description: Use when`).
- Contains "Triggers on" (1 occurrence).
- Discoverable as a `yolo-*` act (path under `.claude/skills/yolo-debug/`, listed in the
  session skill registry).

## SC2 — Stateless act, one artifact, no state machine — **PASS**

- Arc present and ordered (lines 20–24): **Reproduce → Hypothesize → Isolate → Fix → Verify**.
- Exactly one artifact named (line 39): `` `workspace/debug/<YYYY-MM-DD>-<slug>.md` ``.
- Forbidden literal tokens absent: `grep -E 'session\.yaml|state\.yaml'` → no match (exit 1);
  `grep -E 'status:'` → no match (exit 1).
- The only hits for "session/state" language are **negations** asserting statelessness
  (line 9 "stores no session state"; line 48 "no persistent session or run-state files") —
  they forbid a state machine rather than introduce one. No persistent-session machinery.

## SC3 — Cites conventions.md, does not restate trailers — **PASS**

- Cites `.claude/yolo/conventions.md` (2 occurrences: Inputs para + Constraints).
- No verbatim trailer strings: `grep -E 'YOLO-Task|YOLO-Verified|YOLO-Feature'` → no match.
- Constraints explicitly say to cite conventions.md "for the commit form and the
  standalone-record rules; do not restate trailer strings."

## SC4 — Routing updated — **PASS**

- `grep -iE 'known gap|no debug act|has no debug'` → **no match** in
  `.claude/yolo/templates/claude-routing-block.md` and in `CLAUDE.md`.
- Both files route bug intent to `yolo-debug`:
  - Template "Bug reports" bullet → "route to **`yolo-debug`**".
  - `CLAUDE.md` carries the identical block.
- **Byte-identical**: `diff` of the content between `<!-- YOLO:routing-block start/end -->`
  markers → IDENTICAL; both 3922 bytes.
- `README.md` skills table row (line 39): `` | `yolo-debug` | you have a bug and want a
  systematic reproduce → isolate → fix → verify pass | ``.
- `.claude/yolo/getting-started.md` (line 53): `"debug this failure" / "why is X breaking?" →
  yolo-debug`.

## SC5 — BEHAVIORAL: route correctly — **PASS (pass rate 6/6 = 100%)**

Simulated an executing agent whose routing context is ONLY the routing block + the
`yolo-debug` SKILL description. Reasoned each prompt 3×.

### Prompt A: "the login page returns a 500 error, fix it"  → expect **yolo-debug**

- **Run 1:** Routing block "Does NOT route — handle normally" → **Bug reports** bullet lists
  "fix the 500 on login" → route to `yolo-debug`. SKILL `description` also triggers on
  "fix the 500 on login". This prompt is a near-exact paraphrase. → **yolo-debug**. No brief;
  one `workspace/debug/` artifact; systematic reproduce→fix→verify. ✅
- **Run 2:** "returns a 500 error, fix it" = reported failure of existing behaviour, not new
  capability → the debug act, not feature intent. → **yolo-debug**. ✅
- **Run 3:** Not a "build/add/implement" verb; it's "fix" a broken page → Bug reports branch →
  **yolo-debug**. ✅
- Result: **3/3 → yolo-debug** (correct artifact = `workspace/debug/<date>-<slug>.md`, no brief).

### Prompt B: "add CSV export to the reports page"  → expect **yolo-feature**

- **Run 1:** "**Routes to `yolo-feature`**" examples list "add CSV export" verbatim →
  **yolo-feature**. ✅
- **Run 2:** Verb "add" + new user-facing capability = feature intent → capture intent, draft
  brief, plan gate → **yolo-feature**. ✅
- **Run 3:** No failure/bug signal; nothing "broken" → not the Bug-reports branch →
  **yolo-feature**. ✅
- Result: **3/3 → yolo-feature**.

**Pass rate: 6/6 (100%).** The integration changes behaviour: bug intent now lands on
yolo-debug (stateless, one artifact, no brief) while feature intent still lands on yolo-feature.

## Overall verdict — **PASS**

All 5 success criteria pass (SC1 ✅, SC2 ✅, SC3 ✅, SC4 ✅, SC5 ✅ at 100%).
