# Task 09 — Document installation

**Goal:** Update the main README so users can discover the Homebrew install/upgrade path.

**Depends on:** 07

**Files to create/edit:**
- `README.md`

## Steps

1. In `README.md`, add a Homebrew subsection at the top of "Build & Install" (before the
   manual `make` instructions):
   ```markdown
   ### Install via Homebrew (recommended)

   ```sh
   brew tap LightC0de/elap
   brew install elap
   ```

   Upgrade and uninstall:

   ```sh
   brew upgrade elap
   brew uninstall elap
   ```

   > Builds from source; requires Xcode Command Line Tools.
   ```
2. Keep the existing `make build` / `make install` instructions as the "from source" alternative.
3. Optionally add a "Releases" link pointing to GitHub releases.

## Acceptance criteria

- README shows the Homebrew tap + install commands, matching the tap name `LightC0de/elap`.
- The manual build instructions remain intact below the Homebrew section.

## Notes / gotchas

- Tap/command names must match exactly what tasks 05–06 produced.
- No code change, so no `swift test` needed.
