# Task 05 — Create the tap repo

**Goal:** Create the separate `LightC0de/homebrew-elap` GitHub repository with the structure
Homebrew expects for a tap.

**Depends on:** none

**Files to create/edit:** none in this repo (a **new, separate** repo is created)

## Steps

> The tap **must** be its own repo named `homebrew-<name>`. Homebrew maps
> `brew tap LightC0de/elap` → `github.com/LightC0de/homebrew-elap`.

1. Create the repo (developer runs):
   ```sh
   gh repo create LightC0de/homebrew-elap --public \
     --description "Homebrew tap for ELAP" --clone
   ```
2. Add the expected structure:
   ```sh
   cd homebrew-elap
   mkdir Formula
   ```
3. Add a short `README.md` to the tap:
   ```markdown
   # homebrew-elap

   Homebrew tap for [ELAP](https://github.com/LightC0de/elap).

   ```sh
   brew tap LightC0de/elap
   brew install elap
   ```
   ```
4. Commit and push the initial structure (developer runs git).

## Acceptance criteria

- `github.com/LightC0de/homebrew-elap` exists, is public, and contains a `Formula/` directory.
- `brew tap LightC0de/elap` succeeds (even before the formula exists).

## Notes / gotchas

- The repo name **must** start with `homebrew-`; the tap name omits that prefix.
- The formula filename in task 06 (`elap.rb`) determines the installed command name (`elap`).
- Keep this tap repo separate from the main `elap` source repo.
