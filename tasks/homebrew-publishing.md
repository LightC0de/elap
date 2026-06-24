# Homebrew Publishing & Update Plan — ELAP

This folder breaks down the work to publish `elap` on Homebrew and keep it updated.
Each task file is self-contained, yields a concrete result, and is small enough to be
completed in a single session.

## Decisions

- **Channel: Both.** Ship a custom tap (`LightC0de/homebrew-elap`) now; keep a deferred
  checklist for a future homebrew-core submission.
- **Install method: build from source.** The formula runs `swift build`. Avoids
  Gatekeeper/notarization issues for the private-SkyLight binary and is reusable for
  homebrew-core later.
- **Automation: yes.** GitHub Actions for release-on-tag and auto formula version-bump.

## Goal (definition of done)

```sh
brew tap LightC0de/elap
brew install elap        # builds from source, installs `elap`
elap --version           # prints the released version
brew upgrade elap        # picks up new releases
```
…and cutting a new git tag automatically opens a formula-bump PR on the tap.

## Prerequisites

- macOS 13+ with Xcode Command Line Tools (`xcode-select --install`).
- Homebrew installed (`brew --version`).
- GitHub CLI authenticated (`gh auth status`).
- Push access to `github.com/LightC0de/elap` and ability to create `homebrew-elap`.

> Project rule: the developer runs all `git` commands. Tasks that need git/repo creation
> are written as **instructions to run**, not actions to execute automatically.

## Task order & dependencies

| # | Task | Depends on | Result |
|---|------|-----------|--------|
| 01 | [Add `--version` support](01-add-version-support.md) | — | `elap --version` prints a version |
| 02 | [Changelog & release metadata](02-add-changelog-and-release-metadata.md) | 01 | `CHANGELOG.md`, clean metadata |
| 03 | [Cut the first release](03-cut-first-release.md) | 01, 02 | `v0.1.0` tag + GitHub release + sha256 |
| 04 | [Release CI workflow](04-release-ci-workflow.md) | 01 | `release.yml` builds/tests on tag |
| 05 | [Create the tap repo](05-create-tap-repo.md) | — | `homebrew-elap` repo with `Formula/` |
| 06 | [Write the formula](06-write-formula.md) | 03, 05 | `Formula/elap.rb` (build from source) |
| 07 | [Test & audit the formula](07-test-and-audit-formula.md) | 06 | `brew install`/`test`/`audit` pass |
| 08 | [Formula bump automation](08-formula-bump-automation.md) | 04, 06 | New tag → formula-bump PR |
| 09 | [Document installation](09-document-installation.md) | 07 | README Homebrew instructions |
| 10 | [homebrew-core checklist (later)](10-homebrew-core-submission-checklist.md) | 07 | Go/no-go checklist |

## Phases

- **A. Prep the tool** — 01, 02
- **B. First release + CI** — 03, 04
- **C. Tap + formula** — 05, 06, 07
- **D. Update automation & docs** — 08, 09
- **E. Later: homebrew-core** — 10

## Status & Issues (assessed 2026-06-24, updated 2026-06-24)

Per-task assessment so the assignee can pick up each item independently. Tasks with no
blocker are marked **No issues**. Verified against repo state (source, workflows, metadata,
tests, git tags). `swift test`: all 33 tests pass.

### Developer action required (in order)

Run these commands to unblock the critical path:

```sh
# Step 1 — commit the staged workflow files BEFORE pushing the tag
git add .github/workflows/release.yml .github/workflows/bump-tap.yml
git commit -m "ci: add release and formula-bump workflows"
git push

# Step 2 — cut the first release
git tag -a v0.1.0 -m "ELAP 0.1.0"
git push origin v0.1.0
# (release.yml CI fires here; wait for it to go green)
# Optionally create the release manually if CI is not yet trusted:
# gh release create v0.1.0 --title "ELAP 0.1.0" --notes-from-tag

# Step 3 — capture sha256 for the formula
curl -fsSL https://github.com/LightC0de/elap/archive/refs/tags/v0.1.0.tar.gz | shasum -a 256
# → paste output into Formula/elap.rb (task 06)

# Step 4 — create/verify the tap repo
gh repo view LightC0de/homebrew-elap || \
  gh repo create LightC0de/homebrew-elap --public --description "Homebrew tap for ELAP" --clone

# Step 5 — create the PAT secret for formula bump automation
# In GitHub UI: Settings → Secrets → Actions → New secret
# Name: HOMEBREW_TAP_TOKEN
# Value: a classic PAT with repo scope on LightC0de/homebrew-elap
```

After the tag is pushed, tasks 06 → 07 → 08 proceed in the tap repo (`homebrew-elap`).

Quick view:

| # | Task | Status |
|---|------|--------|
| 01 | `--version` support | ✅ Done |
| 02 | Changelog & metadata | ✅ Done |
| 03 | Cut first release | ⛔ Not done — primary blocker |
| 04 | Release CI workflow | ⚠️ File correct, unverified (uncommitted) |
| 05 | Create tap repo | ❓ Unverifiable from this repo |
| 06 | Write the formula | ❌ Blocked by 03; unverifiable |
| 07 | Test & audit formula | ❌ Blocked by 03 + 06 |
| 08 | Bump automation | ⚠️ File correct; secret unverified (uncommitted) |
| 09 | Document installation | ✅ Done |
| 10 | homebrew-core checklist | ⏸️ Deferred (by design) |

### Task 01 — Add `--version` support
**No issues — complete.** Implemented with the constant in `Sources/ELAP/Version.swift`
(single source of truth). Wired at `main.swift:420`; `testVersionIsSemver` passes.
Task file updated to point at `Version.swift` so future bumps (03/08) edit the right file.
- **Action:** none.

### Task 02 — Changelog & release metadata
**No issues — complete.** `CHANGELOG.md` has the `[0.1.0] - 2026-06-24` entry; `LICENSE` is
MIT / "Copyright (c) 2026 Danil Lukyanenko". An extra `testVersionMatchesChangelog` test
enforces version↔changelog sync.
- **Action:** confirm the `desc` string for task 06:
  `Fully disable the MacBook built-in display while an external monitor is in use`
  (77 chars, no leading article, no trailing period — passes audit rules).

### Task 03 — Cut the first release ⛔ Primary blocker
**Issue: not done.** `git tag -l` is empty — no `v0.1.0` tag, so no GitHub release and no
captured sha256. Tasks 06/07 and the end-to-end automation (04/08) all depend on this.
- **Secondary issue:** `gh` is not installed / not on PATH in this environment.
- **Fix (developer runs git):**
  ```sh
  git tag -a v0.1.0 -m "ELAP 0.1.0"
  git push origin v0.1.0
  gh release create v0.1.0 --title "ELAP 0.1.0" --notes-from-tag
  curl -fsSL https://github.com/LightC0de/elap/archive/refs/tags/v0.1.0.tar.gz | shasum -a 256
  ```
  Record the sha256 (task 06 needs it). Install/auth `gh` first (`brew install gh && gh auth status`).

### Task 04 — Release CI workflow
**Issue: file correct but unverified, and uncommitted.** `.github/workflows/release.yml`
matches the spec verbatim but has never run (no `v*` tag pushed). It is currently staged but
uncommitted, and must exist on the default branch **before** the tag is pushed or the tag
won't trigger it.
- **Fix:** commit the workflow, push `v0.1.0` (task 03), then confirm a green run in Actions.

### Task 05 — Create the tap repo ❓ Unverifiable
**Issue: cannot confirm.** The tap is the separate `LightC0de/homebrew-elap` repo; `gh` is
unavailable here, so existence / public / `Formula/` can't be verified.
- **Fix / verify:**
  ```sh
  gh repo view LightC0de/homebrew-elap
  brew tap LightC0de/elap   # should succeed even before a formula exists
  ```
  Create per the task steps if missing. Repo name must start with `homebrew-`.

### Task 06 — Write the formula ❌ Blocked by 03 + unverifiable
**Issues:** (1) needs the real sha256 from task 03, which doesn't exist yet; (2) `Formula/elap.rb`
lives in the tap repo, so it can't be verified from here.
- **Fix:** after task 03, create `Formula/elap.rb` in the tap, paste the sha256, set `desc` to
  the task-02 string. Verify `ruby -c Formula/elap.rb`. Keep `head` and `--disable-sandbox`.

### Task 07 — Test & audit the formula ❌ Blocked
**Issue: cannot start.** Depends on a published tarball (03) and a written formula (06).
`brew install --build-from-source` / `brew test` / `brew audit --strict --online` not yet run.
- **Fix:** once 03+06 are done, run the install/smoke-test/audit loop and fix findings (common:
  `desc` wording, component ordering). Acceptance = audit clean and `brew test elap` passes.

### Task 08 — Formula bump automation
**Issues:** (1) repo secret `HOMEBREW_TAP_TOKEN` (PAT with write access to `homebrew-elap`) is
unverified — without it the bump job fails at runtime; (2) untested end-to-end (can't fire until
03 + 06). The `.github/workflows/bump-tap.yml` file matches the spec but is uncommitted.
- **Fix:** create the PAT, add it as `HOMEBREW_TAP_TOKEN` in the `elap` repo settings, commit the
  workflow, publish a release, and confirm a bump PR opens on `homebrew-elap`.

### Task 09 — Document installation
**No issues — complete.** `README.md:32` has "Install via Homebrew (recommended)" with
tap/install/upgrade/uninstall; the manual "From source" section is preserved below. Tap name
matches `LightC0de/elap`.
- **Action:** none.

### Task 10 — homebrew-core checklist
**Issue (by design): no decision recorded.** Deferred "later" task; checklist exists but no
go/no-go logged against the notability gate.
- **Fix:** none now. Revisit once the tap path (05–09) is proven and the project clears the
  notability bar (~30+ stars, tagged releases, not duplicating an existing formula).

### Cross-cutting issue (affects 04 & 08)
Both workflow files are **staged but not committed** (`git status` shows `A`). The release
workflow must exist on the default branch **before** the `v0.1.0` tag is pushed, or the tag
won't trigger CI. Commit the workflows first, then cut the tag.

### Critical path
**03 (tag + release + sha256) → 05 (tap repo) → 06 (formula) → 07 (audit) → publishing the
release exercises 04 & 08.** Everything else is done (01, 02, 09) or deferred (10).

## Task file template

Every task file follows this shape:

```
# Task NN — <title>
**Goal:** one sentence.
**Depends on:** <tasks or none>
**Files to create/edit:** explicit paths.
## Steps
## Acceptance criteria
## Notes / gotchas
```
