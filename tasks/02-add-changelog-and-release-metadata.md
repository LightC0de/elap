# Task 02 — Changelog & release metadata

**Goal:** Add a `CHANGELOG.md` and confirm the metadata Homebrew will reuse (`desc`,
`license`, homepage) is accurate and stable.

**Depends on:** 01

**Files to create/edit:**
- `CHANGELOG.md` (new)
- `README.md` (verify only)
- `LICENSE` (verify only)

## Steps

1. Create `CHANGELOG.md` in [Keep a Changelog](https://keepachangelog.com) format:
   ```markdown
   # Changelog

   All notable changes to ELAP are documented here.
   The format is based on Keep a Changelog, and this project adheres to Semantic Versioning.

   ## [0.1.0] - 2026-06-24
   ### Added
   - Initial public release: `list`, `status`, `on`, `off`, `toggle`, `watch`, `daemon`.
   - Built-in display disconnect via private SkyLight APIs (no SIP changes required).
   ```
   (Match the version to `elapVersion` from task 01 and use today's date.)
2. Verify `LICENSE` shows `MIT` and the correct author/year (`Danil Lukyanenko`, 2026).
3. Verify `README.md` has a single concise one-line description usable as Homebrew's `desc`
   (≤ 80 chars, no leading "A"/"An", no trailing period — Homebrew audit rules). Suggested:
   `Fully disable the MacBook built-in display while an external monitor is in use`.

## Acceptance criteria

- `CHANGELOG.md` exists with a `0.1.0` entry whose version equals `elapVersion`.
- A description string ≤ 80 chars is identified and noted for use in task 06.

## Notes / gotchas

- Homebrew `desc` must not start with the formula name or an article, and must not end with a period.
- No code changes here, so no `swift test` needed.
