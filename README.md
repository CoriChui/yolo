# YOLO — You Only Live Once

A reasoning-first, feature-aware workflow framework for Claude Code. YOLO turns "I want X"
into a planned, executed, verified, and landed change — driven by conversation and git, not
by tracked status files.

## Core ideas

- **Git is the source of truth.** A feature is a **brief** (`workspace/features/<slug>/brief.md`)
  plus a **branch** (`feature/<slug>`). Progress is recorded as commit trailers
  (`YOLO-Task`, `YOLO-Verified`, `YOLO-Feature`) and a `yolo/done/<slug>` tag at landing.
- **Status is derived, never stored.** Every "where do things stand" is recomputed from git
  and the briefs on demand, so it can't drift. There is no `state.yaml`.
- **The methodology lives in skills.** The workflow has no slash commands and no scripts —
  each act is a `yolo-*` skill that Claude routes to from plain intent. (The lone
  `.claude/commands/yolo-validate.md` is maintainer tooling, explicit-invoke only, not part
  of the workflow.)
- **Cheap is free; billed is reviewed at two gates.** Capturing intent and drafting a brief
  run freely; YOLO then confirms at exactly two points — the **plan gate** (before any code
  is written) and the **ship gate** (before the irreversible merge) — and lets everything
  between them flow.

The precise, authoritative rules — naming, trailers, status derivation, gating, config
fallbacks — live in [`.claude/yolo/conventions.md`](.claude/yolo/conventions.md), the single
source of truth every skill cites.

## The skills

| Skill | Use it when… |
|---|---|
| `yolo-feature` | you want to build/add/implement a feature (the main entry point) |
| `yolo-research` | you want to understand the code before changing it |
| `yolo-plan` | you want a goal broken into testable, committable tasks |
| `yolo-verify` | you want work checked against its `success_criteria` |
| `yolo-finish` | you want to land verified work (PR + CI check, or fast-local) |
| `yolo-status` | you want a derived view of where every feature stands |
| `yolo-roadmap` | you want a large goal decomposed into several feature briefs |
| `yolo-decide` | you want a recorded, multi-perspective decision (X vs Y) |
| `yolo-debug` | you have a bug and want a systematic reproduce → isolate → fix → verify pass |
| `yolo-intake` | you want a feature to draw on the project's docs for context (yolo reads the `docs/` folder; connectors/docs-engine fill it — yolo never fetches) |
| `yolo-init` | you want to set up (or repair) YOLO in a repo |

`yolo-feature` composes the lifecycle: capture intent → brief → research → plan →
**plan gate** → execute → verify → **ship gate**. Any step is also invokable on its own.

## Quick start

1. Copy `.claude/` into your project root.
2. Say **"set up YOLO here"** (runs `yolo-init`): it scaffolds `workspace/config.yaml` and
   `workspace/{features,decisions,debug}/` (plus `docs/`), and installs the routing block into your
   `CLAUDE.md`.
3. Describe what you want to build. Claude drafts a brief, confirms, then drives the loop.

### What one feature looks like

```
you:    add CSV export to the reports page
yolo:   (drafts brief: workspace/features/csv-export/brief.md → status "planned")
        git switch -c feature/csv-export                  → status "in-progress"
        research → plan.md
        Here's what I found + the plan. Approve?          ← plan gate (before any code)
you:    yes
yolo:   execute (test-first, one commit per task)
        verify: all success_criteria met → YOLO-Verified: true
        Open PR and merge on green?                       ← ship gate (irreversible)
you:    ship it
yolo:   merges, tags yolo/done/csv-export                 → status "done"
```

See [`.claude/yolo/getting-started.md`](.claude/yolo/getting-started.md) for the full
walkthrough and a glossary.

## Configuration

`workspace/config.yaml` (scaffolded by `yolo-init`) holds genuine config — never tracked
state. The groups:

- `project` — `name`, `base_branch`.
- `agents` — model tier per billed step (`research`/`plan`/`execute`/`verify`/`finish`,
  plus `roadmap`/`decide`).
- `finish` — landing policy: `mode` (`pr`|`local`), `ci` (`auto`|`require`|`off`), and
  `auto_merge_on_green` (headless/unattended runs only — off by default).
- `risk` — risk-classifier inputs: `sensitive_paths`, `max_diff_lines`, `max_diff_files`.

Confirmation is **not** a config knob: YOLO always confirms at the two gates (plan + ship);
say *"just ship it"* or *"walk me through each step"* per-feature in prose. See
`conventions.md` → *The two gates*.

If `workspace/config.yaml` is absent, YOLO falls back to safe defaults (see
`conventions.md` → *Config-absent fallback*).

## Design history

`docs/superpowers/` holds the original design spec and implementation plans (historical
records of how YOLO was built). They are reference, not current instructions — the live
contract is `conventions.md` and the skills.
