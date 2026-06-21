
<!-- YOLO:routing-block start -->
## YOLO workflow (this is a YOLO-initialized repo)

This project uses YOLO (reasoning-first). Feature state lives in **git, not in tracked
status files** — see `.claude/yolo/conventions.md`.

**Routing — when the user expresses intent to build, add, or implement a feature**, use the
`yolo-feature` skill: capture intent → draft a brief → CONFIRM → compose
research/plan/execute/verify/finish. In this repo this takes **precedence over generic
brainstorming** for feature intent.

**Cheap vs billed:** intent capture and brief drafting run freely; **STOP for confirmation
before** spawning a billed agent or writing code (unless `workspace/config.yaml`
`ux.mode: auto`).

**Other intents:** "where do things stand / where was I" → `yolo-status`; "break this epic
into features / plan a milestone" → `yolo-roadmap`; "pull in this Figma/doc/schema" →
`yolo-intake`; "help me decide X vs Y" → `yolo-decide`; "set up YOLO here" → `yolo-init`.
<!-- YOLO:routing-block end -->
