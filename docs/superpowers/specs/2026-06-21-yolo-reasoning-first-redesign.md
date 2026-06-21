# YOLO Reasoning-First Redesign

**Date:** 2026-06-21
**Status:** Design — approved in brainstorming, pending implementation plan
**Supersedes the direction of:** the heavyweight v2 spec (`.claude/yolo/spec.md`, 858 lines)

---

## 1. Problem

YOLO is strong at project *inception* — `init` → `intake` → `release` → `feature` gives real structure when starting from zero. But once a project is established and work becomes incremental ("add one feature to a mature codebase"), the framework becomes friction, and the author reaches for **superpowers** instead because it is *atomic, isolated, and conversational*.

The root causes, established during analysis:

1. **The release is a mandatory container.** A feature is never atomic — it must belong to an `active` release, inherits release-level research, and is gated by a release-wide dependency DAG. Adding one feature drags the entire inception ceremony into the job.
2. **A heavyweight tracked-state machine.** `state.yaml` / `release.yaml` / `feature.yaml` carry ~30 fields each with explicit status lifecycles, locks, TOCTOU guards, retry counters, and reconciliation. Much of this machinery is **compensation for not trusting the model to reason** — it exists because the design assumes the model will drift.
3. **Pull-based, command-driven interaction.** You must type `/yolo:feature ...`. Nothing tells the model to reach for YOLO's methodology on its own, the way superpowers' SessionStart mandate + skill descriptions do.

## 2. Key insight

**Superpowers is not a framework — it is skills + the model's reasoning + git.** It *teaches* a process and gets out of the way, rather than *encoding* a process as a state machine the model executes by rote.

On Opus 4.8 (2026), a large fraction of YOLO's machinery is dead weight: the model can already hold a plan, decide what's next, drive subagents, self-verify, and recover from a half-done state by *looking* at what exists. The irreducible things the model genuinely cannot do from reasoning alone are narrow:

- **Memory across sessions** (the model has zero recall next week → needs durable state on disk)
- **Hard gates on billed/irreversible acts** (spawning Opus agents, merging to main)
- **An audit trail** (what was built, was it verified)

> **Therefore: the right amount of framework is the *minimum durable spine* + the *maximum model reasoning*.** YOLO today has that ratio inverted. This redesign flips it.

## 3. Design principles

1. **Derive state, don't track it.** Status is computed from git + committed artifacts at the moment it is asked, never stored in a field that can drift. State that is computed cannot get out of sync — this deletes the entire reconciliation / lock / retry-counter apparatus.
2. **Git is the source of truth.** Branches, commits (+ light trailers), merge state, and tags hold the state. Markdown artifacts (brief, plan, verification) hold the content. Everything travels with the branch automatically.
3. **Methodology lives in skills, not a pipeline.** The model reaches for YOLO's *how* by intent-matching, the way superpowers decomposes into brainstorming / writing-plans / TDD / verification skills.
4. **Conversation is auto-triggered and cheap; execution is gated and explicit.** The model freely enters "let's figure out this feature" from a plain sentence, but *stops and shows the plan* before anything billed runs.
5. **Structure is adaptive, applied by judgment.** Heavy tools (worktrees, releases, intake digests, PR review) are reached for when their benefit is real and stay invisible when it isn't — not fixed pipeline phases.
6. **A few hard gates protect billed/irreversible acts.** Everything else is a model judgment call.

## 4. Architecture

### 4.1 The unit of work

**A feature = a brief (committed markdown) + a branch.** Atomic and isolated by construction. No container required.

- **Brief** — `goal`, `success_criteria`, optional intake references. Committed markdown. *Its existence = "planned."*
- **Branch** — `feature/<slug>`. *Its existence = "in progress."*
- **Merged** — *= "done."*

Three states, all derivable from git. No status field.

### 4.2 Git as the source of truth

Most of today's YAML is already redundant with git:

| YAML field today | Git-native equivalent |
|---|---|
| `branch_point` | `git merge-base <branch> main` — literally redundant |
| `status` | no branch = planned · branch w/ commits, unmerged = in progress · merged = done |
| `tasks.completed_ids` | `git log` on the branch — each task is a commit |
| `tasks.current` | plan tasks **minus** tasks present in `git log` = remaining |
| `depends_on` | a commit trailer or one line in the brief |
| verification passed | a commit trailer / the committed `verification.md` |
| goal / criteria | the brief markdown |

**Encoding policy: light conventions** (chosen over pure derivation). A small, disciplined set of machine-legible markers makes `status` unambiguous and greppable, while failing gracefully (worst case the model re-derives "what's done" by diffing the committed plan against `git log`):

- **Commit trailers** for task completion and verification, e.g.:
  - `YOLO-Task: setup-auth-middleware`
  - `YOLO-Verified: true`
- **Annotated tags** are the *only* surviving form of "release" — an optional label over a span of merges, applied when you genuinely ship a cohesive body of work. Never required.

**What git cannot hold — and the answer for each:**

| Gap | Resolution |
|---|---|
| "Planned but not started" | A committed brief file. File exists = planned; branch exists = started; merged = done. |
| Fast "list everything" lookup | `/yolo:status` becomes a *computed view* (a few git commands), not a cached index. Slower, but can never be stale. |
| Live run coordination (locks) | Never durable state — per-session runtime. Handled in-memory by TodoWrite / team-task tools; correctly dies with the session. |
| "Where was I" resume | Last commit message + `git log`, read by the model. No `session.resume` field. |

**One real cost, named:** commit conventions become load-bearing — the execute agent must reliably stamp trailers. This is a *soft* contract, far smaller than the current state machine, and degrades gracefully. Gotchas to respect: `rebase`/`squash` can drop trailers; uncommitted work doesn't count (both are healthy discipline).

### 4.3 Intake → project-level reference shelf + just-in-time fetch

The release was never the right owner of intake — proof: intake captured for release A is siloed and invisible to release B today. Decoupling *improves* it.

- **Promote to a project-level library** — `workspace/intake/<source>/` (or a `docs/` knowledge folder), owned by nobody, citable by any brief. Capture once, reuse everywhere.
- **Prefer just-in-time fetch.** Batch-capturing materials upfront was itself compensation for a model that couldn't reach Figma/Notion/DB mid-task. Now it can, live, via MCP/WebFetch. **Persist a digest only when the source is expensive, rate-limited, or offline** (a huge Figma, a DB you don't want to hammer, a PDF). Everything cheap and live is fetched on demand and not persisted.

### 4.4 Methodology as skills

YOLO's *how* is carried by skills the model invokes by reasoning, not a fixed phase pipeline:

- `yolo-research` — explore the codebase / cited intake, gather context
- `yolo-plan` — break a goal into tasks with a committed `plan.md`
- `yolo-verify` — check work against `success_criteria`, emit `verification.md`
- `yolo-finish` — the finishing policy (§4.6)
- *(optional)* `yolo-release` — only when genuinely scoping a large cohesive body of work (becomes a tag over merges)
- *(optional)* `yolo-decide` — multi-perspective design decision (largely intact from today)

The model orchestrates with TodoWrite + subagents. Slash commands survive as **escape hatches** (`/yolo:verify` right now), not the primary interface.

### 4.5 Conversational entry, gated execution

- **Trigger wiring:** a routing block in the project `CLAUDE.md` — *"This project uses YOLO. When the user expresses intent to build/add/implement a feature, capture intent → draft goal+criteria → confirm before spawning agents."* Always in context, zero new infra, per-project. **Upgrade path:** a SessionStart hook + `yolo-router` skill if CLAUDE.md triggering proves unreliable.
- **Precedence:** in a YOLO-initialized repo, feature-intent routes to YOLO; superpowers' own brainstorming yields. This must be stated explicitly wherever the trigger lives.
- **The safety rule:** auto-trigger the *conversation* (cheap — intent capture, drafting), gate the *execution* (billed — research/plan/execute agents, merges). The model drafts and **stops to confirm** before anything billed runs.

### 4.6 Finishing policy (merge vs PR)

**Default: branch → PR/MR → CI as a hard gate → auto-merge on green.** With one escape hatch and one risk rule.

- **PR + CI on everything** — buys a clean-room CI check (catches "works on my machine" bugs a local merge hides) and a durable record (which, solo, *is* your memory). A PR adds **zero YOLO state**: forge holds PR status (queryable via `gh` / `glab`), git holds the branch.
- **Auto-merge on green for routine work** — cuts the one source of real friction (the human review bottleneck). The model pushes, CI runs, it merges on green, async. No babysitting.
- **Human review only on flagged risk** — the model triages like an engineer: trivial diff + green CI + clear criteria → merge; touches auth/payments/migrations/deploy config, or fuzzy criteria, or red CI → stop and show the user.
- **Escape hatch — fast-local:** throwaway spikes or offline → branch → local `yolo-verify` → `--no-ff` merge, no forge. Explicitly invoked, never default.
- **Adaptive fallback:** if a repo has no CI configured, the hard gate degrades to YOLO's own semantic verify (`verification.md`). Works in a bare repo *and* a full GitLab pipeline with no extra configuration.
- **The PR description is the summary** — generated from brief (what) + plan (how) + diff (the work) + verification (evidence). Collapses the separate `summary.md`. For the local-merge path, the condensed version goes in the `--no-ff` merge-commit message.

Rationale: this matches the actual risk gradient — CI is cheap insurance you always want; human review is expensive attention spent only on risk; worktrees (below) are isolation paid for only when something is actually concurrent.

### 4.7 Worktrees

Conditional, the model's call — not a mandatory phase. Spun up only when:

- **Parallel writers** — multiple execute agents simultaneously, or working feature A while an agent does feature B (non-negotiable isolation here), or
- **Walk-away isolation** — a long feature you want to leave dirty while doing something else.

Otherwise a plain branch in the current tree. Mirrors superpowers' `using-git-worktrees` skill. The question the model asks: "will anything else touch the tree while this runs?"

## 5. The thin durable spine (what remains)

- **Committed markdown:** the brief, `plan.md`, `verification.md`, decisions.
- **Git structure:** branches, commits (+ trailers), merge state, optional tags.
- **A tiny `config.yaml`:** genuine config only (agent models, base branch, limits, ux mode). Config doesn't drift — fine to keep.

## 6. What gets deleted vs kept

**Deleted:**

- `state.yaml` status index, `release.yaml`, the status-tracking half of `feature.yaml`
- Status lifecycle machine (`pending → researching → planning → in_progress → ...`)
- Reconciliation, advisory locks, `.task-locks/`, TOCTOU guards, `run_active`
- Retry counters (`research_retry_count`, `verify_retry_count`, `hook_gate_bypass_count`, `run_failure_count`)
- `branch_point` storage (use `git merge-base`)
- The mandatory release container and release-scoped intake
- Release-wide dependency DAG enforcement (a feature may still note a `depends_on` in its brief; the model honors it, but there is no DAG machine)

**Kept (the real value):**

- Semantic verification against explicit `success_criteria` (`verification.md`)
- An audit trail (now the PR body / merge-commit message)
- Worktree isolation (now conditional)
- `/yolo:decide` (largely intact)
- Releases — demoted to an optional tag/label over merges
- A few hard gates (§7)

## 7. The surviving hard gates

The lean design keeps deterministic gates only around billed/irreversible acts:

1. **Landing on main** (local merge *or* PR merge) — the irreversible boundary; always explicitly confirmed (auto-merge-on-green is the *configured* form of this consent for routine work).
2. **Spawning billed agents** (research/plan/execute) — the conversation drafts freely; the billed run is confirmed.
3. **Destructive ops** — covered by `settings.json` deny patterns (unchanged).

Everything else is a model judgment call.

## 8. Scope boundaries (YAGNI)

- **No promotion** of a standalone feature into a release (releases are now just optional tags anyway).
- **No two-stage spec/quality review** in execute for now — revisit as a separate follow-up.
- **No cross-feature DAG tooling** beyond honoring a manually noted `depends_on`.
- **No migration tooling** for existing v2 `workspace/` state in the first cut — this is a forward redesign; an existing-project migration path is a separate effort if needed.

## 9. Open implementation questions

1. **Trailer schema** — exact trailer keys/values and whether `yolo-verify` writes `YOLO-Verified: true` as a trailer, a `verification.md` commit, or both.
2. **Brief location** — `workspace/features/<slug>/brief.md` vs a flatter `briefs/<slug>.md`. Affects how `/yolo:status` globs.
3. **Risk classifier** — the concrete signal list and thresholds that route a PR to auto-merge vs human review.
4. **Skill boundaries** — final decomposition and the trigger `description` wording for each `yolo-*` skill (this is what makes conversational entry reliable).
5. **`config.yaml` survival** — confirm the minimal field set; verify nothing in it is actually derivable state in disguise.
6. **CLAUDE.md routing block wording** — the exact precedence statement vs superpowers, and the cheap-vs-billed boundary phrasing.

## 10. Headline

**YOLO stops being a state machine you operate and becomes a methodology the model applies — with git as memory and a few hard gates around billed/irreversible acts.** Atomic features by default (no container), conversational entry (no commands required), git as the single source of truth (no parallel bookkeeping), and a finishing policy that matches how disciplined engineers actually ship.
