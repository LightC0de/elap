# Task 06 — Write the formula

**Goal:** Author `Formula/elap.rb` in the tap repo that builds ELAP from source and installs
the `elap` binary.

**Depends on:** 03 (needs tarball URL + sha256), 05 (tap repo exists)

**Files to create/edit:**
- `Formula/elap.rb` (in the `homebrew-elap` tap repo)

## Steps

1. Create `Formula/elap.rb`:
   ```ruby
   class Elap < Formula
     desc "Fully disable the MacBook built-in display while an external monitor is in use"
     homepage "https://github.com/LightC0de/elap"
     url "https://github.com/LightC0de/elap/archive/refs/tags/v0.1.0.tar.gz"
     sha256 "PASTE_SHA256_FROM_TASK_03"
     license "MIT"
     head "https://github.com/LightC0de/elap.git", branch: "main"

     depends_on :macos
     depends_on xcode: ["15.0", :build]

     def install
       system "swift", "build", "--disable-sandbox", "-c", "release"
       bin.install ".build/release/elap"
     end

     test do
       assert_match version.to_s, shell_output("#{bin}/elap --version")
     end
   end
   ```
2. Fill `sha256` with the value captured in task 03.
3. Confirm `desc` matches the ≤ 80-char string from task 02 (no leading article, no trailing period).

## Acceptance criteria

- `ruby -c Formula/elap.rb` reports `Syntax OK`.
- `url`/`sha256` reference the real `v0.1.0` tarball; `version` resolves to `0.1.0` from the URL.

## Notes / gotchas

- `--disable-sandbox` is required because Homebrew's build sandbox blocks SwiftPM's network/cache access.
- `version` is inferred from the tagged URL; the `test do` block compares it to `elap --version`
  (works only because task 01 added `--version`).
- Keep a `head` block so `brew install --HEAD elap` builds from `main` for testing.
