# Human Action 05 — macOS Compatibility and Private ABI Validation

## Purpose

Validate Tab-List's real window behavior on exact Apple Silicon macOS 15 and
macOS 26 builds and produce the evidence required before enabling any
unsupported WindowServer capability for those builds.

The source currently keeps separate empty allowlists for:

- Space inventory and per-window Space queries.
- Exact window activation.
- Accessibility element to WindowServer ID mapping.

That is intentional. Symbol presence or a macOS major version is not evidence
that a private calling convention is safe.

## Why this needs a human

This matrix needs interactive Macs, user-created Spaces, full-screen windows,
Stage Manager, display reconfiguration, sleep and lock, permission prompts, and
deliberate Debug-only invocation of unsupported system APIs. macOS 15 hardware
is not available in the current workspace. Accessibility and Screen Recording
permission must be granted or revoked by a person.

## Prerequisites

- [Full Xcode and passing automated tests](01_INSTALL_FULL_XCODE.md).
- A reviewed Debug build from a known commit.
- Apple Silicon test hosts on:
  - The currently supported macOS 15 point release.
  - The currently supported macOS 26 point release.
- A throwaway local user account on each host.
- The `WindowFixture` app and only synthetic documents.
- At least two displays for the multi-display portion.
- Firefox, Chrome, Safari, Finder, TextEdit, and one Electron app.
- A way to return the test host to a known state.

Do not start private-ABI validation until Codex confirms that each capability
has a separate gated adapter, structural self-test, failure path, and public
fallback. The macOS 15 private thumbnail backend must also exist behind its own
gate before it can be validated.

## Safety rules

- Use a throwaway macOS account with no private documents open.
- Save unrelated work and close sensitive apps.
- Run only a Debug build.
- Never add unverified environment flags to Release, CI publication, login
  items, or a normal user build.
- Test one private capability at a time before testing combinations.
- Stop immediately after a crash, unexpected logout, focus corruption, Window
  Server instability, or unexplained app termination.
- Do not guess or copy AltTab private constants or wrappers.
- Do not add a build to an allowlist merely because calls did not crash.

## Record the exact test identity

Before each run, save these non-secret values in the result sheet:

```sh
git rev-parse HEAD
sw_vers
sysctl -n kern.osversion
uname -m
xcodebuild -version
xcrun swift --version
```

Record display count, display scale, Stage Manager state, “Displays have
separate Spaces” state, app versions, and Mac model class/chip/RAM.

Do not record serial numbers, provisioning UDIDs, hardware UUIDs, Apple Account
details, user names, or real window titles.

## Human action

### A. Establish the public-fallback baseline

1. Build and launch Tab-List without private opt-in environment variables.
2. Grant Accessibility only when prompted.
3. Skip Screen Recording and verify App Icon and Title modes.
4. Confirm current-Space switching, reverse cycling, release-to-activate,
   Escape, Delete, mouse activation, temporary disable, and Quit.
5. Confirm native `Command-Tab` returns immediately after disable and Quit.
6. Switch to Thumbnail mode, test denied state, then grant Screen Recording and
   relaunch if macOS requires it.
7. Export redacted diagnostics.
8. Confirm degraded-mode warnings are accurate and the app does not crash.

### B. Build the synthetic window matrix

Use `WindowFixture` and real test applications to create:

- 10, 50, and, where practical, 100 standard windows.
- Multiple windows from one process.
- Duplicate, empty, and very long titles.
- A native tab group.
- Utility, modal, unclosable, minimized, hidden-app, and full-screen windows.
- Windows on several Spaces and displays.
- An unsaved-document close confirmation.

Exercise creation, close, move, resize, minimize, restore, retitle, app launch,
app termination, and display disconnection while the switcher is visible.

### C. Validate private capabilities separately

In Xcode, edit the TabList Debug scheme's Run environment. Enable only one of
these at a time:

```text
TABLIST_ENABLE_UNVERIFIED_SPACE_APIS=1
TABLIST_ENABLE_UNVERIFIED_EXACT_ACTIVATION=1
TABLIST_ENABLE_UNVERIFIED_AX_WINDOW_ID=1
```

For each flag:

1. Rebuild from the recorded commit.
2. Confirm the capability report distinguishes detected from operational.
3. Run its complete fixture cases at least twice.
4. Force stale windows, terminated processes, missing symbols where testable,
   and permission loss.
5. Confirm failure falls back or returns a typed error instead of crashing.
6. Quit and relaunch before testing the next flag.

Only after each capability passes independently may all validated flags be
tested together.

#### Space query evidence

- Every fixture window has the correct Space membership.
- Visible Space IDs change with each display/Space transition.
- Stage Manager and separate-Spaces configurations remain correct.
- An invalid query disables or degrades the capability without corrupting the
  registry.

#### Exact activation evidence

- The selected window, not merely its owning application, becomes focused.
- Same-Space, cross-Space, minimized, hidden-app, full-screen, and
  other-display activation work.
- Focus verification identifies failure accurately.
- A stale window ID cannot activate a different recycled window.
- A failed verification disables the exact path for the process lifetime.

#### AX-to-window-ID evidence

- Mapping is exact for duplicate titles and equal geometry.
- Mapping remains correct after retitle, move, minimize, restore, and native
  tab changes.
- Ambiguity fails closed.
- Terminated or unresponsive applications do not stall other processes.

#### Private capture evidence

When Codex has implemented a dedicated Debug-only gate:

- On macOS 15, minimized and off-Space previews capture at the requested scaled
  size.
- Preview pixels never appear in Caches, Application Support, logs, diagnostics,
  or network traffic.
- Revoking Screen Recording stops capture and purges displayed previews.
- Backend failure retains the prior frame or icon placeholder.
- The in-memory cache remains within 128 MiB.

Do not invent an environment variable for this backend. Use the exact gate
documented by its implementation.

### D. Exercise system transitions

For both public fallback and validated private paths:

- Connect and disconnect a display during a session.
- Toggle Stage Manager.
- Test “Displays have separate Spaces” on and off. Follow macOS's logout
  requirement when it changes.
- Sleep/wake and lock/unlock.
- Fast-user switch using non-sensitive accounts.
- Revoke Accessibility and Screen Recording while running.
- Test secure input and at least one alternate keyboard layout.
- Hold keys for repeat and perform rapid `Command-Tab` bursts.
- Hang or pause the synthetic fixture process to exercise AX timeouts.

## Evidence to retain

Create one result sheet per exact Darwin build:

| Field | Value |
|---|---|
| Commit SHA | |
| macOS product version | |
| Darwin build (`kern.osversion`) | |
| Xcode build | |
| Mac class/chip/RAM | |
| Display/Space configuration | |
| Public fallback result | Pass / Fail |
| Space ABI result | Pass / Fail / Not tested |
| Exact activation result | Pass / Fail / Not tested |
| AX window-ID result | Pass / Fail / Not tested |
| Private capture result | Pass / Fail / Not implemented |
| Redacted diagnostics reviewed | Yes / No |
| Tester and date | |

Attach sanitized logs and synthetic-only screenshots if necessary. Keep raw
Instruments traces or diagnostics outside the public repository until reviewed.

## Exit criteria

- The full matrix passes twice on each exact build.
- Public fallback remains usable even when every private capability is off.
- Every passing private capability has structural and behavioral evidence.
- No private content was captured in the evidence.
- Failures remain disabled and documented.
- The exact Darwin build, commit, and test result are unambiguous.

## What Codex can do afterward

Given the safe evidence, Codex can:

1. Review logs and reject incomplete validation.
2. Add only the passing exact Darwin build to the corresponding allowlist.
3. Add compatibility regression tests and evidence references.
4. Keep failed capabilities disabled.
5. Repair registry, activation, AX, capture, or fallback defects.
6. Generate a new Debug candidate for another pass.

The human should not edit private-ABI allowlists directly. Every macOS update
produces a new Darwin build and requires this process again.

## Official references

- [Apple Accessibility API](https://developer.apple.com/documentation/applicationservices/axuielement)
- [`AXIsProcessTrustedWithOptions`](https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions)
- [ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit)
- [Screen recording privacy controls](https://support.apple.com/guide/mac-help/control-access-to-screen-recording-mchld6aa7d23/mac)
- [Use multiple Spaces on Mac](https://support.apple.com/guide/mac-help/work-in-multiple-spaces-mh14112/mac)
- [Use Stage Manager on Mac](https://support.apple.com/guide/mac-help/use-stage-manager-mchl534ba392/mac)
