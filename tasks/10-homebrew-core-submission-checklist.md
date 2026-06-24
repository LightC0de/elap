# Task 10 — homebrew-core submission checklist (later)

**Goal:** Capture a go/no-go checklist for moving ELAP from the personal tap into homebrew-core,
so `brew install elap` works with no tap. **Defer until the tool meets notability.**

**Depends on:** 07 (a clean, audited formula exists)

**Files to create/edit:** none now (future PR to `Homebrew/homebrew-core`)

## Notability gate (check before attempting)

homebrew-core rejects niche/new software. Confirm the project meets the maintainers' bar, roughly:
- [ ] Reasonable popularity (commonly cited: ~30+ GitHub stars/forks/watchers, not vanity).
- [ ] Maintained, with tagged stable releases (not just `HEAD`).
- [ ] Not trivially duplicated by an existing formula.
- [ ] Builds from a stable source tarball (already true — task 03).

> If these are not met, **stay on the tap** (tasks 05–09). Revisit later.

## Differences from the tap formula

- No custom tap namespace — the file goes in `Homebrew/homebrew-core/Formula/e/elap.rb`.
- Stricter audit: `brew audit --new --strict --online elap` must be clean.
- Private-API usage may draw maintainer questions; be ready to justify (it works without SIP
  changes and degrades gracefully — see README "Private-API notice").
- Bottles are built by Homebrew CI, not by you.

## Submission steps (when ready)

1. `brew tap-new` is **not** needed; fork `Homebrew/homebrew-core`.
2. Use `brew bump-formula-pr` or `brew create <url>` to generate the core formula from the
   working tap formula.
3. Run `brew audit --new --strict --online elap` and `brew test elap`; fix all findings.
4. Open a PR to `Homebrew/homebrew-core` and respond to CI + maintainer review.
5. After acceptance, keep the tap as a fallback or deprecate it pointing users to core.

## Acceptance criteria

- A documented decision (go/no-go) on core submission based on the notability gate.
- If "go": a checklist completed through audit before opening the core PR.

## Notes / gotchas

- Keep the tap and core formulas in sync if both exist (same version/sha per release).
- homebrew-core review can be slow; the tap remains the reliable install path meanwhile.
