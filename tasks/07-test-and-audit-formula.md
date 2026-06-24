# Task 07 — Test & audit the formula

**Goal:** Verify the formula installs, runs, passes Homebrew's test block, and passes a strict
audit — fixing any findings.

**Depends on:** 06

**Files to create/edit:**
- `Formula/elap.rb` (fix findings as needed)

## Steps

1. Install from source using the local/tap formula:
   ```sh
   brew install --build-from-source elap        # or: brew install --build-from-source ./Formula/elap.rb
   ```
2. Smoke-test the installed binary:
   ```sh
   elap --version
   elap --help
   ```
3. Run Homebrew's formula test block:
   ```sh
   brew test elap
   ```
4. Run a strict audit and fix every finding:
   ```sh
   brew audit --strict --online elap
   # for a brand-new formula also try:
   brew audit --new --strict --online elap
   ```
5. Reinstall after edits and re-run audit until clean:
   ```sh
   brew reinstall --build-from-source elap && brew audit --strict --online elap
   ```

## Acceptance criteria

- `brew install --build-from-source elap` completes and `elap --version` works.
- `brew test elap` passes.
- `brew audit --strict --online elap` reports no errors.

## Notes / gotchas

- Common audit fixes: `desc` wording, missing `license`, component ordering in the formula.
- If the sandbox blocks SwiftPM, confirm `--disable-sandbox` is present (task 06).
- `brew audit --new` is only needed if you later submit to homebrew-core (task 10).
