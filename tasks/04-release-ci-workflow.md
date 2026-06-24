# Task 04 — Release CI workflow

**Goal:** On every `v*` tag push, build and test ELAP on macOS in CI and publish a GitHub
release, so releases are reproducible and gated on a green build.

**Depends on:** 01

**Files to create/edit:**
- `.github/workflows/release.yml` (new)

## Steps

1. Create `.github/workflows/release.yml`:
   ```yaml
   name: Release
   on:
     push:
       tags:
         - 'v*'
   permissions:
     contents: write
   jobs:
     build:
       runs-on: macos-14
       steps:
         - uses: actions/checkout@v4
         - name: Show toolchain
           run: swift --version
         - name: Build (release)
           run: swift build -c release
         - name: Test
           run: swift test
         - name: Create release
           env:
             GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
           run: gh release create "${GITHUB_REF_NAME}" --title "ELAP ${GITHUB_REF_NAME#v}" --notes-from-tag || gh release edit "${GITHUB_REF_NAME}"
   ```
2. Validate the YAML locally if `actionlint` is available:
   ```sh
   actionlint .github/workflows/release.yml
   ```

## Acceptance criteria

- Workflow file is valid YAML / passes `actionlint`.
- A subsequent tag push produces a green run and a GitHub release.

## Notes / gotchas

- `macos-14` provides a recent Swift toolchain; bump if the project needs a newer one.
- The release step is idempotent (falls back to `gh release edit`) so re-runs don't fail if the
  release already exists (e.g. created manually in task 03).
- This workflow does **not** attach prebuilt binaries — installs build from source via the tap.
