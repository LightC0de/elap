# Working in ELAP

Supporting detail for [CLAUDE.md](CLAUDE.md). Read this before changing code.

## How to work here
- Read the relevant existing code before changing it; match the surrounding style exactly.
- For anything touching 3+ files or the architecture, propose a short plan and wait for
  approval.
- For exploration, research, or independent subtasks, delegate to a subagent so the main
  context stays focused.
- Keep changes minimal and scoped to the request. If you spot an unrelated issue, mention
  it — don't fix it unasked. Never remove working functionality unless told to.
- Always handle edge cases: no external display attached, display hot-plug/unplug mid-run,
  sleep/wake, SPI returning an error.
- Write XCTest tests for non-trivial logic (display selection, state transitions, parsing).
  Skip tests for trivial glue/config. Run `swift test` before finishing.
- Be direct and concise. On failure, give the root cause first, then the fix. When unsure,
  say so rather than guessing.

## Display-layer conventions (private SkyLight SPI)
The riskiest, most macOS-version-sensitive code. Full implementation detail in
[cli-spec.md](cli-spec.md) §2.

- The private toggle (`CGSConfigureDisplayEnabled`) takes a `CGDisplayConfigRef` from
  `CGBeginDisplayConfiguration()` as its **first argument — not** a connection-ID integer.
  Passing an integer is dereferenced as a pointer and crashes. Always wrap the private call
  inside the public `CGBeginDisplayConfiguration` → change → `CGCompleteDisplayConfiguration`
  transaction.
- Resolve the symbol at runtime via `dlsym` with the documented fallback list; never link
  SkyLight directly. Guard every private call and keep a documented fallback — these symbols
  get renamed or removed across macOS releases.
- A disabled display vanishes from `CGGetOnlineDisplayList`. Persist its ID to the state file
  before disabling, and recover it afterward by hardware probe (then state file).
- `.permanently` survives process exit but reverts on logout/reboot — that is the intended
  recovery backstop.
- Always preserve a recovery path: re-enable on SIGINT/SIGTERM, keep `elap on` working, and
  never strand the user with the built-in display off.

## Hard boundaries — NEVER do these
- **NEVER run `git commit`, `git push`, or `git add`.** The developer handles all git
  operations. (A PreToolUse hook in `.claude/settings.json` should enforce this
  deterministically — not yet configured; until it is, treat this rule as absolute.)
- Never call a private SPI without an availability/feature guard and a documented fallback.
- Never leave the user with the built-in display off and no way to turn it back on
  (always preserve a recovery path).
- Never hardcode a bundle identifier, signing identity, or team ID — read them from the
  build config.
- Never disable hardened runtime or weaken code-signing/notarization settings.
