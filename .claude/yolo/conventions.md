# YOLO Git-as-Truth Conventions

YOLO stores **no tracked status**. Feature state is **derived** from git and on-disk
artifacts at the moment it is asked. This file is the single source of truth for the
naming, trailers, and derivation rules every `yolo-*` skill relies on. Do not paraphrase
these strings elsewhere — cite this file.

## The unit of work

A feature = a **brief** (`workspace/features/<slug>/brief.md`) + a **branch**
(`feature/<slug>`). Alongside the brief, as the work progresses:
- `plan.md` — tasks (written by `yolo-plan`)
- `verification.md` — evidence (written by `yolo-verify`)

## Naming

- Branch: `feature/<slug>`
- Worktree (only when isolation is needed): `../.<repo-name>-worktrees/<slug>`
- Milestone grouping (optional, replaces "release"): a `milestone:` value in the brief,
  and at ship time an annotated git tag and/or a forge milestone.

## Commit trailers

Append with `git commit --trailer` (or write directly in the message footer):

| Trailer | Where | Meaning |
|---|---|---|
| `YOLO-Task: <task-id>` | the commit completing a plan task | that `plan.md` task is done (`<task-id>` is its kebab-case id) |
| `YOLO-Verified: true`  | the single verification commit | `success_criteria` passed (`yolo-verify`) |

Trailers are the **greppable machine signal**; `verification.md` is the **human-readable
audit**. Both are written — neither alone is sufficient. Caveat: `rebase`/`squash` can
drop trailers; uncommitted work never counts.

## Deriving status (no stored field)

Given a feature `<slug>` and the configured `base_branch`:

- **planned** — `workspace/features/<slug>/brief.md` exists AND `feature/<slug>` does not.
- **in-progress** — `feature/<slug>` exists AND is not merged into `base_branch`.
- **done** — `feature/<slug>` is merged into `base_branch`
  (`git branch --merged <base_branch>` lists it), OR the branch tip carries
  `YOLO-Verified: true` with a committed `verification.md`.

Completed tasks for an in-progress feature:

```sh
git log <base_branch>..feature/<slug> \
  --format='%(trailers:key=YOLO-Task,valueonly)' | sed '/^$/d'
```

Verified check:

```sh
git log <base_branch>..feature/<slug> \
  --format='%(trailers:key=YOLO-Verified,valueonly)' | grep -qx true
```

## Why derived beats tracked

A computed view cannot drift, so there is nothing to reconcile. This is why the v2
`state.yaml`/`release.yaml`/`feature.yaml` status machine, its locks, TOCTOU guards,
and retry counters are deleted (Plan 4).
