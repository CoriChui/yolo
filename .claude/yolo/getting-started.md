# Getting started with YOLO

YOLO is a way of working, not a tool you run. You talk to Claude; Claude routes your intent
to the right `yolo-*` skill and uses **git** to remember everything. This guide gets you from
zero to a landed feature, and defines the vocabulary.

## 1. Set up

In a git repo with `.claude/` copied in, say:

> set up YOLO here

That runs **`yolo-init`**, which creates `workspace/config.yaml` and
`workspace/{features,intake,decisions,debug}/`, and installs the routing block into your
`CLAUDE.md`. Open `workspace/config.yaml` and skim it — especially `project.base_branch` and
the `agents.*` model tiers.

## 2. Build a feature (the worked example)

Say what you want:

> add CSV export to the reports page

YOLO (`yolo-feature`) walks the lifecycle:

1. **Capture intent** — a light 2-question check: what you'll be able to *do*, and how you'd
   *know* it works. From this it derives a `slug` (e.g. `csv-export`), a `goal`, and
   `success_criteria`, and writes `workspace/features/csv-export/brief.md`. → status **planned**.
2. **Branch + research + plan** — `git switch -c feature/csv-export main` (→ **in-progress**),
   then it researches the code (when non-trivial) and writes `plan.md` (tasks each = one commit).
   Your "build X" request authorizes this; there's no separate stop before research.
3. **The plan gate** — it shows you what it found and the plan of attack, then **stops**.
   This is the cheap moment to redirect before any code is written. Approving authorizes the
   rest of the run through to landing. (Say *"just go"* up front to skip this for one feature.)
4. **Execute → Verify** (flow through, no *confirmation* gate — just a bounded
   retry-then-escalate loop if a check fails) — each task commits with a `YOLO-Task: <id>`
   trailer (test-first); **Verify** runs the tests, checks each criterion, writes
   `verification.md`, and on success stamps `YOLO-Verified: true`.
5. **The ship gate** (`yolo-finish`) — opens a PR (or merges locally), runs the risk
   classifier, and **confirms before the irreversible merge**. Landing writes the durable
   done-markers — a `YOLO-Feature: csv-export` trailer on the merge commit and a
   `yolo/done/csv-export` tag — then cleans up the branch. → status **done**.

At any point, ask **"where do things stand?"** (`yolo-status`) for a derived table. Because
status is computed from git every time, it is never stale — and a shipped feature still reads
as **done** even after its branch is deleted.

## 3. Other things you can say

- **"break this epic into features"** → `yolo-roadmap` drafts several briefs at once.
- **"should we use Postgres or Mongo?"** → `yolo-decide` records a decision under
  `workspace/decisions/`.
- **"debug this failure" / "why is X breaking?"** → `yolo-debug` runs a systematic
  reproduce → isolate → fix → verify pass and records it under `workspace/debug/`.
- **"pull in this Figma / spec / schema"** → `yolo-intake` brings external material into context.
- **"just make a plan"**, **"verify this"**, **"ship it"** → invoke a single step directly.

## Controlling how much YOLO asks (the two gates)

YOLO confirms at exactly **two** points and lets everything between them flow:

- **The plan gate** — before any code is written, it shows you the plan to approve or redirect.
- **The ship gate** — before the irreversible merge to your base branch.

You change this per-feature in **prose**, not config:

- *"just ship it, don't ask"* — pre-consents the ship gate for this feature (the risk
  classifier's hard triggers — sensitive paths, vague verification, public-API removal —
  still stop).
- *"walk me through each step"* — adds intermediate confirmations for this feature.

There's no sticky "confirm nothing" mode — unattended merge to main is opt-in per run, or for
genuinely headless runs, `finish.auto_merge_on_green: true` (off by default).

## Glossary

- **Brief** — `workspace/features/<slug>/brief.md`: the goal + `success_criteria` for one feature.
- **Feature** — a brief + a `feature/<slug>` branch. The atomic unit of work.
- **Atom / act** — one step skill (research, plan, execute, verify, finish). `yolo-feature`
  composes them; each is also usable alone.
- **Trailer** — a `Key: value` line in a commit footer. YOLO uses `YOLO-Task`,
  `YOLO-Verified`, and (at landing) `YOLO-Feature` as machine-readable progress signals.
- **Done-marker** — the durable evidence a feature shipped: the `YOLO-Feature` landing
  trailer + the `yolo/done/<slug>` tag, both surviving branch deletion.
- **Derived status** — `planned` / `in-progress` / `done` (or `cancelled`), computed from git
  on demand, never stored. A feature also reads **done** the moment it's verified locally
  (`YOLO-Verified: true` + a committed `verification.md` on the branch tip), *before* landing —
  the work is complete and only the mechanical merge remains. See `conventions.md`.
- **Milestone** — an optional `milestone:` label grouping briefs that ship together. Not a
  container — just a grouping.
- **Cheap vs billed** — cheap work (intent, briefs, status) runs free; billed work (agents,
  code) is reviewed at the two gates — the plan gate (before execute) and the ship gate
  (before merge).

The exact rules behind all of this are in
[`conventions.md`](conventions.md) — the single source of truth.
