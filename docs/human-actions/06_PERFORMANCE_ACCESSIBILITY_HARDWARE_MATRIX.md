# Human Action 06 — Performance, Accessibility, and Hardware Matrix

## Purpose

Prove that the optimized Tab-List release candidate meets its latency, CPU,
memory, capture, layout, and accessibility requirements on representative
Apple Silicon hardware.

Compilation and unit tests cannot prove these requirements. Results must come
from real release builds under controlled, reproducible conditions.

## Why this needs a human

The matrix requires physical displays, pointer movement, VoiceOver listening,
visual inspection, system Accessibility settings, user-granted permissions,
high window counts, and prolonged Instruments observation. Codex can automate
measurements once a test host is available, but it cannot independently supply
the physical hardware, grant TCC permissions, or judge audible and visual
accessibility quality.

## Prerequisites

- [Compatibility task passed for the exact build](05_MACOS_COMPATIBILITY_AND_PRIVATE_ABI.md).
- A known commit with all automated tests passing.
- An optimized Release build. Do not use Debug performance results.
- A representative base or lower-resource supported Apple Silicon Mac.
- A second Mac or display configuration where practical.
- One 1× and one 2× display path.
- A small/notched laptop display and a multi-display setup.
- Synthetic fixture windows for 10, 50, and 100-window cases.
- Accessibility and Screen Recording permission states that can be reset.
- Xcode Instruments and enough free disk space for temporary traces.

Record the Mac model class, chip family, RAM, OS version/build, display scale,
Xcode build, and commit SHA. Do not record serial numbers, hardware UUIDs,
Apple Account details, or real window titles.

## Measurement rules

- Reboot or return the host to a documented baseline before the measured run.
- Disconnect unrelated development tools and high-CPU background tasks.
- Use synthetic fixture content only.
- Measure cold and cached cases separately.
- Run each case at least five times unless the duration is explicitly five
  minutes.
- Report median, P95 where required, maximum, and any discarded run with its
  reason.
- Preserve raw samples until the redacted summary has been reviewed.
- Do not average away a release-budget failure.
- Exclude macOS Space animation time only where the specification explicitly
  permits it.

## Required performance budgets

| Metric | Release budget |
|---|---:|
| Cached overlay appearance | P95 below 75 ms |
| Selection movement | Inside one 16 ms frame |
| Current-Space activation | Normally below 250 ms |
| Cross-Space activation | Below 750 ms, excluding macOS Space animation |
| Idle CPU | Average below 0.5% over five minutes |
| Icon/Title memory, 50 windows | Below 60 MB |
| Thumbnail memory, 50 windows | Below 200 MB |
| Thumbnail image cache | Hard maximum 128 MiB |
| Capture shutdown after dismissal | Idle within one second |

The test must also cover 10, 50, and 100 windows and confirm that repeated
opening/dismissal does not create unbounded CPU or memory growth.

## Human action

### A. Prepare the test host

1. Record:

   ```sh
   git rev-parse HEAD
   sw_vers
   sysctl -n kern.osversion
   xcodebuild -version
   ```

2. Record Mac class/chip/RAM manually without serial or device identifiers.
3. Quit unrelated applications and disable optional third-party overlays.
4. Launch `WindowFixture` and create the required synthetic window count.
5. Verify the candidate is a Release build and private capabilities match the
   compatibility evidence for this exact Darwin build.
6. Test each presentation mode independently:
   - Thumbnails.
   - App Icons.
   - Titles.

### B. Measure overlay and selection latency

1. Use the `switcher-performance` signpost category and Instruments Points of
   Interest or `os_signpost` tooling.
2. Measure first invocation after launch separately from cached invocations.
3. For cached appearance, collect at least 30 invocations for each window
   count.
4. Rapidly cycle forward and backward, including key repeat.
5. Confirm each selection update completes within one 16 ms frame.
6. Test pointer-display placement and auto-scroll at the maximum item count.
7. Retain the signpost export with titles redacted.

### C. Measure activation and AX isolation

1. Measure current-Space activation for:
   - A normal window.
   - A minimized window.
   - A hidden application.
   - Several windows from the same application.
2. Measure cross-Space, full-screen Space, and other-display activation.
3. Pause or intentionally block only the synthetic fixture process to simulate
   an unresponsive AX application.
4. Confirm the unresponsive process does not block selection, the event tap,
   the main actor, or actions for another process.
5. Confirm stale and closed windows return typed failures.

### D. Measure CPU, memory, and capture

1. With the panel hidden and no window activity, record five minutes of idle CPU
   in every presentation mode.
2. For each of 10, 50, and 100 windows, record:
   - Resident memory before opening.
   - Peak memory while visible.
   - Memory after dismissal.
   - Memory after a pressure event.
3. In Thumbnail mode:
   - Confirm no more than three captures execute concurrently.
   - Fill and evict the cache.
   - Confirm calculated thumbnail cost never exceeds 128 MiB.
   - Dismiss during capture and verify work becomes idle within one second.
   - Revoke Screen Recording and verify displayed/cached previews are purged.
4. In App Icon and Title modes:
   - Confirm ScreenCaptureKit is never initialized or queried.
5. Repeat open/cycle/dismiss at least 100 times and check for a rising baseline.
6. Search the app's Caches and Application Support locations for window image
   files. Finding any is a release failure.

### E. Inspect layout and accessibility

Run every presentation mode in Small, Medium, Large, and Auto sizes, using
System, Light, and Dark themes.

For each combination:

- Verify 1× and 2× rendering.
- Verify a small/notched display and each pointer display.
- Verify the selected item stays visible while scrolling.
- Verify titles truncate at the end and expose full accessible text.
- Verify no tile, text, badge, outline, or close control is clipped.
- Verify the close target is at least 24×24 points.
- Verify system accent color and keyboard focus visibility.

Then test:

- **VoiceOver:** app name, window title, state, position, and selected status are
  spoken correctly, for example “Firefox, Project plan — 2 of 8, selected.”
- **Reduce Transparency:** material is replaced by an opaque semantic
  background.
- **Reduce Motion:** animations are removed or materially reduced.
- **Increase Contrast:** the selection and focus indicator remain clear.
- **Light/Dark/System appearance:** content remains readable and native.
- **Long and empty titles:** labels remain meaningful and do not overlap.
- **Keyboard-only use:** the complete switcher session and close action remain
  operable.

## Evidence to retain

Create a redacted summary with one row per configuration:

| Commit | OS build | Hardware class | Mode | Windows | Metric | Median | P95 | Max | Budget | Pass |
|---|---|---|---|---:|---|---:|---:|---:|---:|---|
| | | | | | | | | | | |

Also retain:

- Instruments trace names and hashes.
- Measurement commands or Instruments templates.
- Screenshots made only from synthetic fixture content.
- VoiceOver checklist and tester notes.
- Reduce Motion, Reduce Transparency, and Increase Contrast results.
- Evidence that Icon/Title modes performed no capture.
- Evidence that no screenshots were persisted.

Keep raw traces outside the public repository until checked for user names,
paths, titles, process arguments, and device identifiers. Commit only sanitized
summaries if the project chooses to preserve them.

## Exit criteria

- Every numeric budget passes.
- Both 50-window memory budgets pass.
- The 128 MiB thumbnail hard limit is never exceeded.
- Capture becomes idle within one second after dismissal.
- Idle CPU passes in all three modes.
- No screenshot content is written to disk or transmitted.
- Icon and Title modes do not invoke ScreenCaptureKit.
- All accessibility and layout combinations pass.
- Results are reproduced in a second clean run.

A failed budget is a code defect. Do not waive it by changing the measurement
method or removing the worst run.

## Security and privacy cautions

- Never profile real work documents or personal browser windows.
- Instruments traces can contain paths, process names, and signpost data.
- Review every export before sharing or committing it.
- Do not post unredacted screenshots in GitHub Issues.
- Use the fixture to reproduce failures.
- Purge temporary traces securely after the redacted record is accepted.

## What Codex can do afterward

Codex can:

1. Run scripted benchmarks and extract signpost intervals.
2. Build deterministic CSV and Markdown summaries from reviewed samples.
3. Diagnose latency, concurrency, cache, AX, or memory failures.
4. Add regression tests and performance assertions.
5. Repair visual or accessibility defects.
6. Compare a new candidate against the retained baseline.

The human must repeat any affected physical or perceptual checks after a fix.

## Official references

- [Performance and metrics in Xcode](https://developer.apple.com/documentation/xcode/performance-and-metrics)
- [`OSSignposter`](https://developer.apple.com/documentation/os/ossignposter)
- [Measuring performance using tests](https://developer.apple.com/documentation/xctest/performance_tests)
- [Accessibility for AppKit](https://developer.apple.com/documentation/appkit/accessibility-for-appkit)
- [VoiceOver User Guide for Mac](https://support.apple.com/guide/voiceover/welcome/mac)
- [Change Display accessibility settings](https://support.apple.com/guide/mac-help/change-display-settings-for-accessibility-unac089/mac)
