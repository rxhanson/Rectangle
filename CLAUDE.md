# Divvy-2 / Chiva — Agent Guide

> **Lean by design.** This file holds load-bearing rules + orientation only.
> Detail lives in `docs/` (dated `YYYY-MM-DD-<Type>-<Name>.md`). Follow the
> **See Also** pointers for the full plan.

## What this is

A native Apple-Silicon window snapper (**Chiva**) to replace Mizage Divvy
(Intel-only, losing support). Built by **forking `rxhanson/Rectangle`** (MIT,
Swift/AppKit). MVP = keyboard layouts: hotkeys that snap the focused window to
user-saved arbitrary screen fractions ("Custom Layouts") — a parallel subsystem
that bypasses Rectangle's fixed `WindowAction` enum.

**Identity:** bundle ID `com.perg593.chiva`, product/display name **Chiva**,
install path **`/Applications/Chiva.app`**. URL scheme `chiva`. (Repo folder is
still `divvy-2`; Xcode targets/module remain `Rectangle*` internally.)

**Status:** M0–M0.5 complete; custom layouts + prefs present. Identity cutover
plan: [`docs/2026-08-03-Plan-Chiva-Identity.md`](docs/2026-08-03-Plan-Chiva-Identity.md).

## MANDATORY: Plan → Codex green-gate → checkpoint reviews

Before any significant implementation work: a plan doc must exist in `docs/`,
and it must pass **adversarial Codex review** (`codex exec ... -s read-only`).
**Do not proceed until the verdict is GREEN — partial green is not green.** Each
milestone (M0, M0.5, M1, …) gets its own Codex checkpoint review before the next
begins. Never skip or shortcut the gate. (This mirrors the global workflow rule.)

## MANDATORY: Branch before any edits

This repo becomes a git clone at M0. After that: never edit on `main`. Branch
off the canonical base — `git fetch origin main && git checkout -b
feature/<task> origin/main` (always include `origin/main`). Commit messages
follow **conventional commits**: `type(scope): summary` (feat / fix / docs /
chore), e.g. `feat(layouts): add CustomLayout store + JSON persistence`.

## Conventions

- **Plan/design docs:** `docs/YYYY-MM-DD-<Type>-<Name>.md` with a `Status:`
  header (Proposed / Reviewed). Types: Plan, Design, Reference, Findings, QA-Report.
- **QA gate before "done":** the Swift equivalent of a green build — `swift
  build` / `xcodebuild build` + `swift test` (and SwiftLint once added) must pass
  before marking work complete. Fix root causes; don't route around failures.
- **Dev install:** `scripts/dev-signing-setup.sh` (once; identity **Chiva Dev**)
  then `scripts/build-install.sh` → `/Applications/Chiva.app`. One-time Divvy2
  cutover: `scripts/chiva-cutover.sh`.
- **Secrets:** never commit credentials, signing identities, or `.env`. Use
  1Password (`op read`) at use-time if any secret is ever needed.
- **Memory:** per-project file-based memory lives in this repo's project memory
  dir (`~/.claude/projects/-Users-projas-divvy-2/memory/`), indexed by `MEMORY.md`.

## See Also

- **The plan (Codex-GREEN):** [`docs/2026-06-23-Plan-Divvy2-Window-Snapper.md`](docs/2026-06-23-Plan-Divvy2-Window-Snapper.md)
- **Identity cutover (Codex-GREEN):** [`docs/2026-08-03-Plan-Chiva-Identity.md`](docs/2026-08-03-Plan-Chiva-Identity.md)
- Architecture spike output: `SPIKE.md`
