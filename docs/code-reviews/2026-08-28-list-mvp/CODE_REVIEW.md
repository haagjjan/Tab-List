# Code Review — Tab-List list MVP

- **Date:** 2026-08-28
- **Scope:** complete tree (`Sources`, `Tests`, `Scripts`, `Config`, `.github`, `docs`)
- **Baseline:** the AX-first rework that replaced the three-mode switcher
- **Build state after fixes:** `swift test` 248 passing, Xcode unit suites passing, Debug and Release builds clean, CLT validation clean, benchmarks inside budget

## Summary

The architecture is sound and the risky parts are in the right places. The
domain layer is pure and heavily tested; the macOS adapters are isolated behind
one file each; the single private-API surface is read-only and probe-gated.

Eight defects were found and fixed. Five of them were regressions introduced by
the rework itself. The stale window count was the direct user-destructive path;
the bundle-identifier normalization fix also strengthens the redundant guards
around application termination.

Six further findings are recorded as accepted risk with rationale.

| Severity | Found | Fixed | Accepted |
|---|---:|---:|---:|
| High | 1 | 1 | 0 |
| Medium | 4 | 4 | 0 |
| Low | 7 | 3 | 4 |
| Informational | 2 | 0 | 2 |

## Fixed

### F1 · High · A stale window count could quit an application

`WindowActionService.close(_:)` read the owning application's window count from
`registry.snapshot(forceRefreshIfStale: true)`. That call still reuses a
snapshot younger than the registry's staleness interval. `WindowClosePolicy`
uses the count to choose between closing one window and terminating the whole
application.

The registry's staleness window is 750 ms. If the user opened a second window
of an application and pressed Delete inside that window, the count read as `1`
and the policy chose `.quitApplication` — terminating an application the user
only meant to take one window from, with whatever unsaved-document prompts that
implies.

The close path now bypasses the 750 ms snapshot cache and performs an
unconditional refresh. One discovery on a rare, user-initiated, irreversible
action is the correct trade. The target and its incarnation are revalidated
from that same snapshot, so a selected window that disappeared during the
refresh cannot cause the remaining window of its application to be quit.

```swift
let snapshot = await registry.refreshSnapshot()
guard let record = snapshot.window(for: target.key),
      target.matches(record) else {
    return .targetMissing
}
```

`WindowClosePolicyTests` covers the protected-bundle, own-process, and
unknown-count paths that must never quit. Registry tests pin the unconditional
refresh behavior.

### F2 · Medium · Invalidating cached elements re-keyed every window of a process

`AccessibilityBridge.invalidate(pid:)` cleared the per-process identity table
along with the cached `AXUIElement`s. `WindowActionService` calls it on its
retry path, so the retry then looked for a `WindowKey` that no longer mapped to
anything: activation and close would fail on exactly the attempt meant to
recover from a stale element.

The identity table also remembered only fallback ordinals. A window could
therefore change keys when the WindowServer mapping became available after an
earlier probe failure, or when a previously available mapping transiently
failed. It now preserves the first identity assigned to every surviving
Accessibility element, regardless of its source.

Split into two operations with distinct contracts:

- `invalidate(pid:)` — drop cached elements so they are resolved again. Keeps
  identity. Safe mid-action.
- `forget(pid:)` — drop everything. Only correct once the process has
  terminated; called from the workspace termination notification.

Covered by `WindowIdentityTableTests` (9 cases pinning identity stability,
non-collision with WindowServer ids, and that a returning window never inherits
a closed window's identifier).

### F3 · Medium · The shortcut recorder could stick on "Press shortcut…"

`ShortcutRecorderView.Coordinator.stopRecording(displaying:)` restored the
button title only when a shortcut was recorded, or when a resting label
existed. The custom reverse-key recorder has no resting label, so cancelling
with Escape left the button prompting indefinitely — SwiftUI had no state
change to trigger `updateNSView`, so nothing corrected it.

The coordinator now tracks the current shortcut and always restores a title.
Covered indirectly by `ShortcutDisplayStringTests`; the stuck-title path itself
needs a UI test.

### F4 · Medium · Synchronous Accessibility IPC on a cooperative thread

`WindowServerBridge.prepare()` ran the `_AXUIElementGetWindow` validation probe
inline on the `WindowInventory` actor's executor. The probe makes synchronous
AX calls against up to four processes with a 300 ms messaging timeout, so it
could block a Swift cooperative thread for over a second.

`prepare()` is now `async` and dispatches to a dedicated serial queue.

### F5 · Low · Unbounded probe retries

A failed window-identifier probe stayed `pending` so it could retry once
Accessibility was granted — but on a host where the symbol never validates it
re-probed on every discovery forever. Capped at five attempts, after which the
capability is disabled for the process lifetime.

### F6 · Low · Dead API

Removed with no replacement:

| Symbol | Why it was dead |
|---|---|
| `WindowRegistry.remove(_:)` | Orphaned when the focus monitor stopped emitting `windowDestroyed`; destruction now flows through `scheduleRefresh` |
| `WindowRegistry.contains(_:)` | Never called |
| `AppIconCache.removePersistentCache()` | Never called |
| `AccessibilityBridge.invalidateAll()` | Never called |

### F7 · Low · Retired Screen Recording copy remained

The app no longer requests Screen Recording or ships thumbnail presentation,
but the localized `InfoPlist.strings` still bundled the retired usage
description. The issue template, pull-request checklist, settings reset
documentation, and security policy also described the removed permission or
captured screenshots.

Removed those stale references. Historical product-review documents and
settings migration tests still name the retired modes where that context is
intentional.

### F8 · Medium · System-process protection was case-sensitive

`WindowClassifier` lowercased incoming bundle identifiers but compared them
against a mixed-case `com.apple.WindowManager` constant. The close policy also
compared protected bundle identifiers case-sensitively. A casing variation
could therefore bypass both the classification rule and the redundant
never-quit guard.

All protected identifiers are now normalized before comparison. Classification
and close-policy tests cover mixed-case inputs.

## Accepted risk

### A1 · Low · The icon disk cache is never pruned

`AppIconCache` writes one PNG per `(bundle, path, version, mtime, size)` under
Caches and never deletes. Growth is driven by application-update frequency, not
usage: roughly 30 KB per application per version. A machine with 40 applications
updating monthly accrues about 14 MB a year, in a directory macOS is free to
purge.

Not fixed because an age-based prune is new behaviour, not a defect repair.
Recommended follow-up if the app ever ships a "reset" affordance that should
include caches.

### A2 · Low · Per-process state is pruned only on the termination notification

`AccessibilityBridge.lanes` and `identityTables` are keyed by pid and removed
when `NSWorkspace.didTerminateApplicationNotification` fires. If that
notification is missed the entries persist for the process lifetime. Each entry
is a `DispatchQueue` and a small array; the notification is reliable. Bounded
and cheap enough to leave.

### A3 · Low · Settings write on every slider increment

`SettingsViewModel.binding(_:)` commits on each change, so dragging the
hold-cycle-speed slider persists to `UserDefaults` and reconfigures the shortcut
service once per 0.1 step. Correct, just chatty. A commit-on-editing-ended
binding would be better if the settings surface grows.

### A4 · Low · Synchronous LaunchServices lookups on the main actor

`SettingsViewModel.refreshExcludedApplications()` calls
`urlForApplication(withBundleIdentifier:)` for each excluded application on
every settings change, on the main actor. Fine for a handful of exclusions,
visible with dozens.

### A5 · Informational · UI test bundles cannot run headless

`TabListUITests` and `WindowFixtureUITests` fail to initialise from a
non-interactive shell with `Timed out while enabling automation mode`. This is
an environment permission, not a code fault: run `Scripts/ci.sh` from an
interactive Terminal. The two unit bundles run anywhere.

### A6 · Informational · An actor takes a non-`Sendable` `UserDefaults`

`PermissionService.init(defaults:)` stores a `UserDefaults` inside an actor.
`UserDefaults` is documented thread-safe but is not `Sendable`, so Swift 6
flags passing one across the isolation boundary; `PermissionServiceTests` uses
an explicit `nonisolated(unsafe)` local. Changing the initialiser to take a
`@Sendable` accessor would remove the escape hatch but adds indirection for no
runtime benefit.

## What the review found healthy

**`GlobalShortcutService`** is the highest-risk file in the tree — a
`CGEventTap` that suppresses native `Command-Tab` — and it holds up. Transactional
registration builds the new tap before tearing down the old one; every failure
path unwinds cleanly; the tap re-enables itself after
`tapDisabledByTimeout`; the Carbon hot key is a genuine fallback rather than a
duplicate trigger, because a consumed tap event never reaches Carbon. Its pure
half, `ShortcutEventInterpreter`, is fully tested.

**`WindowRegistry`** correctly handles the hard cases: concurrent refreshes
share one discovery; a refresh whose results were invalidated mid-flight is
discarded rather than applied; focus observations that arrive during a refresh
win over the refresh's own stale reading. All three are now pinned by tests.

**Privacy claims hold at the binary level.** The Release bundle links no
capture framework, declares no `NSScreenCaptureUsageDescription`, and contains
no activation symbol. Diagnostics omit titles entirely and salt bundle-identifier
hashes per export.

**Comment discipline is right.** Roughly 1–6% comment lines in the new code, and
they explain non-obvious decisions — why identity survives invalidation, why
probes exist, why tab groups collapse — rather than restating the code.

## Test coverage

| | Before | After |
|---|---:|---:|
| Tests | 145 | 248 |
| Suites | 21 | 37 |
| Test lines | ~3,500 | ~5,200 |

Five previously untestable decisions were extracted into pure types and covered:

| Extracted | From | Why it mattered |
|---|---|---|
| `WindowRecordAssembly` | `WindowInventory.discover()` | The exact path that used to hide Firefox |
| `WindowIdentityTable` | `AccessibilityBridge` | The stability contract everything else depends on |
| `NativeTabCollapse` | `AccessibilityBridge` | A heuristic that fails silently and invisibly |
| `ProcessStackingOrder.order(frontToBack:)` | `ProcessStackingOrder.current()` | Initial MRU seeding |
| `DisplayGeometry` | already injectable, untested | Per-display filtering |

New suites: `WindowIdentityTableTests`, `NativeTabCollapseTests`,
`WindowRecordAssemblyTests`, `ProcessStackingOrderTests`,
`DisplayGeometryTests`, `WindowClosePolicyTests`, `HoldCycleTimingTests`,
`WindowRegistryLifecycleTests`, `SettingsStoreTests`, `PermissionServiceTests`,
`SwitcherPanelSelectionTests`, `ShortcutDisplayStringTests`,
`SwitcherDisplayItemStateTests`, `DiagnosticsReportContentTests`,
`WindowFilterEdgeCaseTests`, `SettingsSchemaBoundaryTests`.

### Still not covered by automation

| Area | Why | Mitigation |
|---|---|---|
| `AccessibilityBridge` IPC | Needs a trusted process and live windows | `docs/human-actions/05`, `WindowFixture` |
| `WindowServerBridge` probes | Needs the real WindowServer | Capability masks in the diagnostics export |
| `GlobalShortcutService` tap lifecycle | Needs a real event tap | Interpreter is unit-tested; tap is manual |
| `WindowActionService` end-to-end | Concrete-typed on the bridge and registry | Would need a protocol seam; manual matrix covers it |
| Panel rendering | AppKit view hierarchy | `TabListUITests`, manual matrix |

The most valuable next investment is a protocol seam under
`WindowActionService` so activation and close retry logic — including the F1
close-policy decision — can be exercised against a fake bridge.

## Verification performed

```
swift test                                 248 tests, 37 suites, 0 failures
xcodebuild test (TabListCoreTests,
                 TabListTests)             TEST SUCCEEDED
xcodebuild build -configuration Debug      BUILD SUCCEEDED
xcodebuild build -configuration Release    BUILD SUCCEEDED
Scripts/validate_clt.sh                    passed
Scripts/benchmark_core.sh                  4/4 inside budget
otool -L / strings on the Release binary   no capture framework, no activation symbol
```
