# YOLO Git-as-Truth Conventions

YOLO stores **no tracked status**. Feature state is **derived** from git and on-disk
artifacts at the moment it is asked. This file is the single source of truth for the
naming, trailers, derivation, gating, and config rules every `yolo-*` skill relies on. Do
not paraphrase these strings elsewhere — cite this file.

## The unit of work

A feature = a **brief** (`workspace/features/<slug>/brief.md`) + a **branch**
(`feature/<slug>`). Alongside the brief, as the work progresses:
- `research.md` — read-only context (written by `yolo-research`, optional)
- `plan.md` — tasks (written by `yolo-plan`)
- `verification.md` — evidence (written by `yolo-verify`)

Standalone records live outside the feature folder:
- `workspace/decisions/<slug>.md` — decision records (written by `yolo-decide`)
- `workspace/intake/<source>/` — persisted intake digests (written by `yolo-intake`)

A brief carrying front-matter `cancelled: true` is an **abandoned** feature: excluded from
the active status view (see *Deriving status*), kept on disk for provenance.

## Naming

- Branch: `feature/<slug>`
- Worktree (only when isolation is needed): `../.<repo-name>-worktrees/<slug>`
- Done tag: `yolo/done/<slug>` — an annotated tag created by `yolo-finish` when the feature
  lands. This is the **durable** done-marker: it survives feature-branch deletion and
  squash merges, where the branch and its trailers do not.
- Milestone grouping (optional, replaces "release"): a `milestone:` value in the brief.
  Shipping a milestone tag/forge-milestone is optional and user-driven — YOLO does not
  create one automatically.

## Commit trailers

Append with `git commit --trailer` (or write directly in the message footer):

| Trailer | Where | Meaning |
|---|---|---|
| `YOLO-Task: <id>` | the commit completing a plan task | that `plan.md` task is done (`<id>` is its kebab-case id, matching the `id` field in `plan.md`) |
| `YOLO-Verified: true` | the single verification commit | `success_criteria` passed (`yolo-verify`) |
| `YOLO-Feature: <slug>` | the commit that lands the feature on `base_branch` (the merge commit, or the squash commit) | this feature shipped — the **durable**, base-resident done-signal that survives branch deletion |

Trailers are the **greppable machine signal**; `verification.md` is the **human-readable
audit**. Both are written — neither alone is sufficient. Trailer matching is exact and
case-sensitive: write `YOLO-Verified: true` verbatim (not `True`/`yes`). Caveat:
`rebase`/`squash` can drop the `YOLO-Task`/`YOLO-Verified` trailers that live on
feature-branch commits — which is exactly why "done" is anchored on the base-resident
`YOLO-Feature` trailer and the `yolo/done/<slug>` tag, not on branch-local evidence.
Uncommitted work never counts.

## Commit message conventions

- **Framework / artifact commits** use the form `yolo: <act> [<arg>]` —
  `yolo: init`, `yolo: brief <slug>`, `yolo: research <slug>`, `yolo: plan <slug>`,
  `yolo: verify <slug>`, `yolo: decision <slug>`, `yolo: intake <source>`,
  `yolo: merge feature/<slug>`.
- **Task commits** (during execute) use a normal, descriptive subject in the project's own
  style — *not* the `yolo:` prefix — plus the `YOLO-Task: <id>` trailer.

## base_branch

The merge target. Configured in `workspace/config.yaml` `project.base_branch`. To detect a
default when unset: `git symbolic-ref --short refs/remotes/origin/HEAD` (strip the
`origin/` prefix); else the first of `main`, `master` that exists. Skills that derive
status MUST guard every ref before using it — `git rev-parse --verify -q <ref>` — and
surface a clear config error rather than hard-failing if `base_branch` does not resolve.

## Deriving status (no stored field)

Resolve `base_branch` first (above). A brief with `cancelled: true` is reported as
**cancelled** and otherwise excluded. For an active feature `<slug>`, evaluate in order
(first match wins):

- **done** — ANY of these (the first two are durable: they survive branch deletion and
  squash merges, so a shipped feature stays done even after cleanup):
  - the tag `yolo/done/<slug>` exists, OR
  - `base_branch` history contains a commit trailered `YOLO-Feature: <slug>`, OR
  - `feature/<slug>` exists and its tip carries `YOLO-Verified: true` with a committed
    `verification.md` (verified locally, awaiting landing).
  (Note: `git branch --merged` is deliberately NOT a done signal — a freshly-cut branch
  with no commits yet is "merged" into base and would false-positive as done. Every real
  landing writes the tag + `YOLO-Feature` trailer, which makes `--merged` redundant anyway.)
- **in-progress** — `feature/<slug>` exists and the feature is not done.
- **planned** — `brief.md` exists, there is NO done-evidence above, AND `feature/<slug>`
  does not exist.
- **untracked-branch** (surfaced by `yolo-status`, not a feature state) — a `feature/<slug>`
  branch exists with no matching `brief.md`. Flagged so orphan branches aren't lost.

Done-evidence commands (run the branch-dependent ones only after the ref verifies):

```sh
# durable tag
git rev-parse --verify -q "refs/tags/yolo/done/<slug>"

# durable landing trailer on base history
git log <base_branch> --format='%(trailers:key=YOLO-Feature,valueonly)' \
  | sed '/^$/d' | grep -qx '<slug>'

# verified-but-not-yet-landed (only if feature/<slug> exists): the TIP commit must carry the
# trailer AND a committed verification.md must exist (the trailer alone — e.g. hand-added —
# is not enough). Check the TIP, not the <base>..branch range: a range scan also matches an
# older verification commit that later work has invalidated, so a reworked branch would read done.
git log -1 feature/<slug> --format='%(trailers:key=YOLO-Verified,valueonly)' | grep -qx true \
  && git cat-file -e "feature/<slug>:workspace/features/<slug>/verification.md" 2>/dev/null
```

Completed-task progress for an in-progress feature (advisory only — never gate "done" on a
count; dedup by id because one task may span several trailered commits, and a
rebase/squash may drop trailers):

```sh
git log <base_branch>..feature/<slug> \
  --format='%(trailers:key=YOLO-Task,valueonly)' | sed '/^$/d' | sort -u
```

## The two gates — how much to confirm

YOLO confirms at exactly **two** boundaries — the points where a mistake is expensive or
irreversible — and lets everything between them flow. Adding gates beyond these two buys
latency and babysitting, not safety: the work in between lives on a throwaway branch and is
fully recoverable.

1. **The plan gate** — after `yolo-research` + `yolo-plan`, BEFORE execute. The agent
   presents what it found and the task plan (with rough scope/cost); the human approves or
   redirects. This is the single cheap moment to catch a wrong approach before execution
   makes it expensive, and it doubles as the authorization for the whole execute → verify
   run. The user's original "build X" request authorizes the cheap intent → research → plan
   work that *leads up to* this gate — there is no separate pre-research gate.
2. **The ship gate** — landing on `base_branch` (local merge OR PR merge) is the
   irreversible boundary, always explicitly confirmed. The `yolo-finish` risk classifier
   may additionally HARD-stop here (sensitive paths, vague verification, public-API
   removal); those stops fire regardless of any pre-consent.

**Per-feature overrides are prose, not config.** "Just go" pre-consents the **plan gate**
(skip straight to execution); "just ship it, don't ask" pre-consents the **ship gate** for
THIS feature (risk hard-triggers still stop) — the trailing "don't ask" stays scoped to the
ship gate and does NOT skip the plan gate; only the blanket "don't ask me anything" pre-consents
both. "Walk me through each step" *adds* intermediate confirmations for THIS feature. These
are scoped to the feature in front of you. There is deliberately **no sticky global "confirm
nothing" mode** — set-and-forget consent to an irreversible merge is a footgun, so unattended
pre-consent is a per-run choice (prose) or, for genuinely headless runs only,
`finish.auto_merge_on_green` (default off).

**Why only two gates is safe.** The interior (execute → verify) runs without a *confirmation*
gate because it is cheaply reversible — every task is one commit on a throwaway
`feature/<slug>` branch, so a wrong turn is `git`-undoable without ever touching
`base_branch`. The one interior stop is **failure-escalation**, not a confirmation gate: the
execute → verify loop is bounded to **~2–3 attempts**, after which the agent halts and hands
to the human rather than looping. That reversibility is what *earns* the loosened interior;
the two gates guard the points the safety net doesn't reach —
the plan (where a bad assumption cascades into the whole build) and the merge (irreversible).
An autonomy choice is safe only when it (a) cannot remove the stop on irreversible /
high-blast-radius actions — YOLO's risk hard-triggers always fire — (b) is scoped, not a
sticky global toggle, and (c) is backstopped by cheap rollback. The per-feature prose
overrides satisfy all three.

Standalone confirm-once skills (`yolo-roadmap`, `yolo-decide`) have a single confirmation of
their own — the framing/feature-list — which is the plan-gate analogue for that act.

## Cheap vs billed

- **Cheap** — run freely: intent capture, brief drafting, `yolo-status`, just-in-time
  `yolo-intake`, and any read-only inspection.
- **Billed** — `yolo-research`, `yolo-plan`, execute, `yolo-verify`, `yolo-finish`, and the
  `yolo-roadmap`/`yolo-decide` analyses. The user's feature request authorizes the billed
  research + plan that lead to the **plan gate**; the plan gate authorizes execute + verify;
  the **ship gate** authorizes landing (see *The two gates*).

## Config-absent fallback

If `workspace/config.yaml` is missing or a key is unset, treat as: model tiers **inherit**
(no per-step override), `finish.mode: pr`, `finish.ci: auto`, `finish.auto_merge_on_green:
false` (the ship gate always asks a human), `base_branch` = detected default. The two gates
always apply regardless of config. Suggest running `yolo-init` to scaffold the file.

## Why derived beats tracked

A computed view cannot drift, so there is nothing to reconcile. This is why the v2
`state.yaml`/`release.yaml`/`feature.yaml` status machine, its locks, TOCTOU guards,
and retry counters are deleted (Plan 4). The cost — that completion evidence must be made
durable at landing — is paid by the `YOLO-Feature` trailer and the `yolo/done/<slug>` tag.
