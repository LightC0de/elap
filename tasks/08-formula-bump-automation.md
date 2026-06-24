# Task 08 — Formula bump automation

**Goal:** When a new ELAP release is tagged, automatically open a PR on the tap that updates the
formula's `url` and `sha256`, so updates don't require manual editing.

**Depends on:** 04 (release workflow), 06 (formula exists)

**Files to create/edit:**
- `.github/workflows/bump-tap.yml` (in the main `elap` repo)
- A repo secret: `HOMEBREW_TAP_TOKEN` (PAT with `repo` scope on `homebrew-elap`)

## Steps

1. Create a fine-grained/classic PAT with write access to `LightC0de/homebrew-elap` and add it as
   the secret `HOMEBREW_TAP_TOKEN` in the `elap` repo settings.
2. Create `.github/workflows/bump-tap.yml`:
   ```yaml
   name: Bump Homebrew formula
   on:
     release:
       types: [published]
   jobs:
     bump:
       runs-on: macos-14
       steps:
         - name: Set up Homebrew
           uses: Homebrew/actions/setup-homebrew@master
         - name: Bump formula PR
           env:
             HOMEBREW_GITHUB_API_TOKEN: ${{ secrets.HOMEBREW_TAP_TOKEN }}
           run: |
             brew tap LightC0de/elap
             brew bump-formula-pr --no-browse --no-fork \
               --tag="${GITHUB_REF_NAME}" \
               --url="https://github.com/LightC0de/elap/archive/refs/tags/${GITHUB_REF_NAME}.tar.gz" \
               LightC0de/elap/elap
   ```
   `brew bump-formula-pr` downloads the new tarball, computes the sha256, and opens the PR.
3. Validate YAML (`actionlint .github/workflows/bump-tap.yml`).

## Acceptance criteria

- Publishing a release triggers the workflow and opens a PR on `homebrew-elap` with updated
  `url` + `sha256`.
- The bumped formula still passes `brew audit` / `brew test` (task 07) on the PR.

## Notes / gotchas

- The default `GITHUB_TOKEN` **cannot** push to another repo — a separate PAT is required.
- `brew bump-formula-pr` computes the sha256 itself, so no manual hashing is needed per release.
- Alternative: a hand-run `brew bump-formula-pr` command documented for manual releases.
