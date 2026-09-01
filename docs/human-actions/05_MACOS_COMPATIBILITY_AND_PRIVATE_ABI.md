# Human Action 05 — macOS Compatibility and Private ABI Validation

## Purpose

Validate Tab-List's real window behavior on exact Apple Silicon macOS 15 and
macOS 26 builds, and confirm that the two unsupported read-only WindowServer
capabilities behave correctly — and degrade correctly — on those builds.

## What the source actually does

`WindowServerBridge` resolves four symbols and enables each only after a
harmless runtime probe succeeds on the running system:

| Capability | Symbol | Probe | Consequence if the probe fails |
|---|---|---|---|
| Main connection | `SLSMainConnectionID` | Non-zero connection | Space queries are unavailable |
| Space inventory | `SLSCopyManagedDisplaySpaces` | At least one current Space is reported | Space queries are unavailable |
| Window Space query | `SLSCopySpacesForWindows` | Space IDs are returned for a real window | Space queries are unavailable |
| Window identifier | `_AXUIElementGetWindow` | An identifier reported for a real Accessibility window also appears in the public window list for that process | Windows get process-scoped ordinals instead |

There is **no private activation path**. Window discovery uses only the public
Accessibility API, and window activation uses `AXRaise` plus
`NSRunningApplication.activate()`. If every private capability is off, the only
user-visible loss is the "Visible now" scope, which stops narrowing by desktop.

The window-identifier probe stays pending until Accessibility is trusted, so it
runs on the first discovery after the permission is granted rather than at
launch.

## Why this needs a human

This matrix needs interactive Macs, user-created Spaces, full-screen windows,
Stage Manager, display reconfiguration, sleep and lock, permission prompts, and
the real third-party applications whose Accessibility window lists diverge from
a plain AppKit app. macOS 15 hardware is not available in the development
workspace, and Accessibility permission must be granted or revoked by a person.

## Prerequisites

- [Full Xcode and passing automated tests](01_INSTALL_FULL_XCODE.md).
- A reviewed Debug build from a known commit.
- Apple Silicon test hosts on the currently supported macOS 15 and macOS 26
  point releases.
- A throwaway local user account on each host.
- The `WindowFixture` app and only synthetic documents.
- At least two displays for the multi-display portion.
- Firefox, Chrome, Safari, Finder, TextEdit, and one Electron app.
- A way to return the test host to a known state.

## Safety rules

- Use a throwaway macOS account with no private documents open.
- Save unrelated work and close sensitive apps.
- Run only a Debug build.
- Stop immediately after a crash, unexpected logout, focus corruption, Window
  Server instability, or unexplained app termination.
- Do not guess or copy AltTab private constants or wrappers.

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

Record display count, display scale, Stage Manager state, "Displays have
separate Spaces" state, app versions, and Mac model class/chip/RAM.

Do not record serial numbers, provisioning UDIDs, hardware UUIDs, Apple Account
details, user names, or real window titles.

## Human action

### A. Establish the baseline

1. Build and launch Tab-List.
2. Grant Accessibility when prompted.
3. Confirm that after granting, the switcher populates without a relaunch.
4. Confirm switching, reverse cycling, hold-to-repeat, release-to-activate,
   Escape, Delete, mouse activation, temporary disable, and Quit.
5. Confirm native `Command-Tab` returns immediately after disable and Quit.
6. Export redacted diagnostics and check `windowServerCapabilities` for the
   detected and operational masks.
7. Confirm any compatibility warning shown in Settings and the menu bar matches
   the operational mask.

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

### C. Application-specific discovery checks

For each of Firefox, Chrome, Safari, Finder, TextEdit, and the Electron app:

1. Open three windows and confirm all three appear as separate rows.
2. Confirm each row's title matches the window's real title.
3. Move one window to another Space and confirm the row remains, and that
   selecting it switches Spaces and focuses that exact window.
4. Minimize one window and confirm the row stays, is marked Minimized, and
   restores on activation.
5. Hide the application and confirm its rows stay, are marked Hidden, and
   activate correctly.
6. Open a native tab group where the application supports one, and confirm the
   group appears once rather than once per tab.

A missing row for any of these applications is a defect in discovery, not a
configuration problem, and must be reported with a redacted diagnostics export.

### D. Validate degraded behavior

The private capabilities are probe-gated rather than flag-gated, so degradation
is verified by removing the conditions the probes depend on:

1. Confirm the diagnostics export lists both detected and operational masks.
2. Where a capability's probe fails naturally on a host, confirm the app still
   discovers and activates every window, and that only the "Visible now" scope
   is affected.
3. Set the scope to **Visible now** on a host without Space queries and confirm
   the list still shows windows rather than emptying.
4. Confirm the compatibility warning appears only when Space queries are
   unavailable.

### E. Exercise system transitions

- Connect and disconnect a display during a session.
- Toggle Stage Manager.
- Test "Displays have separate Spaces" on and off. Follow macOS's logout
  requirement when it changes.
- Sleep/wake and lock/unlock.
- Fast-user switch using non-sensitive accounts.
- Revoke Accessibility while running, then grant it again.
- Test secure input and at least one alternate keyboard layout.
- Hold keys for repeat and perform rapid `Command-Tab` bursts.
- Hang or pause the synthetic fixture process to confirm that its Accessibility
  lane times out without stalling discovery for other applications.

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
| Detected capability mask | |
| Operational capability mask | |
| Discovery result per test application | Pass / Fail |
| Cross-Space activation result | Pass / Fail |
| Minimized and hidden-app result | Pass / Fail |
| Degraded-scope result | Pass / Fail |
| Redacted diagnostics reviewed | Yes / No |
| Tester and date | |

Attach sanitized logs and synthetic-only screenshots if necessary. Keep raw
Instruments traces or diagnostics outside the public repository until reviewed.

## Exit criteria

- The full matrix passes twice on each exact build.
- Every test application's windows appear and activate correctly.
- The app remains fully usable when every private capability is off.
- No private content appears in the evidence.
- The exact Darwin build, commit, and test result are unambiguous.

## Official references

- [Apple Accessibility API](https://developer.apple.com/documentation/applicationservices/axuielement)
- [`AXIsProcessTrustedWithOptions`](https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions)
- [Use multiple Spaces on Mac](https://support.apple.com/guide/mac-help/work-in-multiple-spaces-mh14112/mac)
- [Use Stage Manager on Mac](https://support.apple.com/guide/mac-help/use-stage-manager-mchl534ba392/mac)
