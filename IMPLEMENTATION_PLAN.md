# Tab-List — Implementation Specification

> Repository: <https://github.com/haagjjan/Tab-List>
> Scope: the shipping product, its architecture, and its acceptance criteria.

## 1. Product definition

### Vision

Tab-List is a lightweight native macOS menu-bar utility that replaces the
application-level `Command-Tab` experience with switching between individual
macOS windows.

If Firefox has three windows, all three appear as three rows. Browser tabs are
not enumerated; a browser window's active tab normally appears through the
window title macOS exposes.

### The MVP feature

**The list display is the product.** One vertical list, one row per window, in
most-recently-focused order. Earlier development explored a thumbnail grid
resembling the Windows alt-tab switcher and an icon grid resembling the native
macOS `Command-Tab` panel. Both are removed. They required Screen Recording
permission, a bounded pixel cache, a capture scheduler, a second onboarding
step, and layout code for three geometries — none of which serve the product's
purpose, which is finding a window by reading its title.

### Locked decisions

| Decision | Value |
|---|---|
| Distribution | Direct download, Developer ID signed and notarized |
| Minimum OS | macOS 15 |
| Architecture | Apple Silicon (arm64) only |
| Activation policy | Accessory (`LSUIElement`) |
| Default shortcut | `Command-Tab` |
| Reverse control | Shift plus the trigger key, configurable |
| Ordering | Window-level most-recently-used |
| Permissions | Accessibility only |
| Updates | Sparkle 2.9.4 with EdDSA signatures |
| License | MIT |

### Non-goals

- Window management, tiling, moving, or resizing.
- Browser or document tab enumeration.
- Thumbnails, previews, or any form of screen capture.
- Application-level switching as a separate mode.
- iCloud sync, accounts, analytics, or telemetry.
- Mac App Store distribution.
- Copying AltTab source, constants, assets, or branding.

### Success criteria

1. Every window a user can switch to appears in the list, including windows on
   other Spaces, minimized windows, and windows of hidden applications.
2. Selecting a row activates that exact window, not merely its application.
3. Missing private WindowServer capabilities degrade one setting — the "Visible
   now" scope — and nothing else.
4. Losing Accessibility permission stops all behavior cleanly and explains
   itself, without a prompt loop.
5. No window content is ever captured or written to disk.

### Performance budgets

| Metric | Budget |
|---|---:|
| Cached panel appearance | P95 below 75 ms |
| Selection movement | Inside one 16 ms frame |
| Window discovery, 100 windows | Below 120 ms |
| Activation, same Space | Normally below 250 ms |
| Activation, other Space | Below 750 ms, excluding the macOS Space animation |
| Idle CPU | Average below 0.5% over five minutes |
| Resident memory, 100 windows | Below 60 MB |

## 2. Behavior specification

### First run

Three steps: what Tab-List does, the Accessibility grant, and a ready screen
that registers the shortcut so the user can try it before finishing. Onboarding
stays open until the user explicitly finishes it; Quit remains available from
the menu bar.

### Session

**Opening.** The trigger key with its modifiers held opens a session. The panel
resolves the currently focused window, applies the user's filters, sorts by MRU,
and selects the first row that is not the current window. A cached registry
snapshot is presented immediately and reconciled against a fresh discovery.

**Cycling.** The trigger key moves forward and wraps. Shift, Shift alone, or a
configurable key moves backward. Held keys repeat at the system repeat rate
scaled by the hold-cycle-speed preference; a repeat clamps at the list boundary
instead of wrapping.

**Committing.** Releasing the modifier activates the selected window. Clicking a
row does the same.

**Cancelling.** Escape dismisses without activating and restores nothing,
because nothing was changed.

**Closing.** Delete or Forward Delete closes the selected window through its
Accessibility close button. The row shows a spinner until the registry confirms
the window is gone. When the window is an application's last one, and the
application is not a protected system process, Tab-List requests a graceful
termination instead. An unsaved-document sheet that keeps the window alive
resolves as "confirmation required": the panel dismisses and the application is
brought forward so the user can answer it.

**Failure.** A failed activation or close returns the panel to its visible
state with an inline message and a beep. Nothing silently no-ops.

### Candidate rules

A window is a candidate when its Accessibility element is a top-level window of
a `regular` application other than Tab-List, its role is `AXWindow` or
`AXDialog`, its subrole is not a known palette subrole, and its frame is finite
and at least 32×32 points.

Classification is deliberately permissive. An unfamiliar subrole from a future
macOS release is accepted rather than dropped, because a surface macOS exposes
as a top-level `AXWindow` is one the user can switch to. Only surfaces that are
provably not switchable — floating palettes, `AXUnknown`, Dock, Notification
Center, Control Center, the wallpaper agent, the Window Server itself — are
excluded. Window titles are never used to classify or group.

AppKit tab members of one tabbed window share a frame and only the selected
member is reachable, so a same-frame group whose members report a matching
`AXTabs` count collapses to the main member.

### Filters

| Filter | Default | Behavior when its input is unknown |
|---|---|---|
| Minimized windows | shown | — |
| Windows of hidden applications | shown | — |
| Fullscreen windows | shown | — |
| Excluded applications | none | — |
| Space scope | all Spaces | A window with unknown Space membership is kept |
| Display scope | all displays | A window with unknown display is kept |

Every filter fails open. A filter that cannot evaluate its input must never
empty the switcher.

### Ordering

MRU is window-level. Only a confirmed focused-window observation from the
frontmost process advances the sequence; application activation alone does not.
The initial order is seeded from the on-screen stacking order of processes,
combined with the front-to-back order `AXWindows` reports inside each process.

### Settings

| Section | Contents |
|---|---|
| Appearance | Theme, and a static preview of the list |
| Controls | Shortcut recorder, reverse control, hold-cycle speed, key reference |
| Filtering | Scope preset with an advanced Space/display pair, window-state toggles |
| Exceptions | Excluded applications, added from running apps or a file picker |
| General | Launch at login, menu-bar icon, updates, permission status, diagnostics export, reset |
| About | Version, license, and clean-room statement |

## 3. Architecture

### Modules

```
TabListCore  (portable, Sendable, no AppKit)
  Domain/         WindowKey, WindowRecord, WindowSnapshot, action targets
  Windows/        WindowClassifier, WindowFilter, MRUOrdering
  Switcher/       SwitcherSessionReducer — the session state machine
  Layout/         PanelLayoutCalculator, SelectionScrollPlanner
  Settings/       TabListSettings and versioned persistence
  Shortcut/       ShortcutDefinition and validation
  Diagnostics/    Title and bundle-identifier redaction

TabList      (AppKit/SwiftUI shell and macOS adapters)
  Services/       AccessibilityBridge, WindowServerBridge, WindowInventory,
                  WindowRegistry, WindowActionService, GlobalShortcutService,
                  AccessibilityFocusMonitor, PermissionService, AppIconCache
  App/            TabListApplication, SwitcherSessionCoordinator, SettingsStore
  UI/             SwitcherPanelController, SwitcherRowView, Settings, Onboarding
```

`TabListCore` contains no framework object that is not `Sendable`. An
`AXUIElement` or `NSImage` never enters a domain record.

### Discovery pipeline

```
NSWorkspace.runningApplications (regular only, one main-actor hop)
        │
        ▼
AccessibilityBridge.windowInventory(for: pids)
   one serial lane per process, 300 ms messaging timeout
   one AXWindows read and one metadata pass per window
   identity: _AXUIElementGetWindow when probed, else a per-process ordinal
        │
        ▼
WindowClassifier.classify  ── excluded ──▶ debug log only
        │
        ▼
WindowRecord  (+ Space IDs when the private query probed, + display from one
               CGGetActiveDisplayList snapshot)
        │
        ▼
WindowRegistry  (actor: incarnations, MRU sequences, generation counter)
        │
        ▼
WindowSelectionPipeline.candidates → SwitcherSessionReducer → panel
```

One `CGWindowListCopyWindowInfo` call per discovery supplies the process
stacking order. Accessibility is the sole source of window identity, geometry,
state, and title.

### Accessibility bridge

Every Accessibility call runs on a serial `DispatchQueue` dedicated to its
target process, so an unresponsive application times out inside its own lane
without blocking discovery for the others. Each window is read exactly once per
discovery. Resolved elements are cached by `WindowKey` for later activation and
close, and are re-resolved when a cached element stops answering.

The per-process identity table maps an `AXUIElement` to the identifier it was
first given. The mapping survives refreshes, so selection, MRU order, and a
pending close all remain attached to the same window. Ordinals are allocated
above `0x8000_0000` so they can never collide with a real WindowServer
identifier inside one process.

### WindowServer bridge

The bridge is the only place that resolves an unsupported symbol, and it holds
four capabilities:

| Capability | Symbol | Probe |
|---|---|---|
| Main connection | `SLSMainConnectionID` | Returns a non-zero connection |
| Space inventory | `SLSCopyManagedDisplaySpaces` | Reports at least one current Space |
| Window Space query | `SLSCopySpacesForWindows` | Returns Space IDs for a real window |
| Window identifier | `_AXUIElementGetWindow` | Reports an identifier for a real Accessibility window that the public window list also attributes to that process |

A probe runs once, off the main actor, from the inventory actor before its first
discovery. The identifier probe stays pending until Accessibility is trusted, so
a permission granted after launch still enables it. A capability whose probe
fails stays off for the process lifetime and its caller degrades.

Symbol presence is never sufficient. No private entry point mutates state; there
is no private activation path.

### Activation

`WindowActionService` unminimizes when needed, performs `AXRaise`, sets
`AXMain`, `AXFocused`, and the application's `AXFrontmost`, then activates the
process with `NSRunningApplication.activate()`. That combination reaches a
window on another Space, in a hidden application, or in a full-screen Space
using public API only. Success is reported only after a bounded poll confirms
that the requested `WindowKey` holds focus in the frontmost process; a first
failure invalidates the cached element and retries once.

### Session state machine

`SwitcherSessionReducer` is a pure function over
`(SwitcherSessionState, SwitcherSessionAction) -> [SwitcherSessionEffect]`. It
owns phase transitions, selection, wrapping, queued cycles that arrive before
preparation finishes, pending closes, and registry updates. The coordinator
performs the effects. Every transition is unit-testable without AppKit.

### Panel

A borderless, non-activating `NSPanel` at `.popUpMenu` level that joins all
Spaces, hosting an `NSTableView` with a single column and a fixed 44-point row
height. Rows are diffed: a same-length update reloads only rows whose rendered
content changed. Selection follows a comfort-zone policy —
`SelectionScrollPlanner` scrolls only when the selected row crosses the
directional boundary or wraps.

### Privacy

- No screen capture API is linked or called.
- Window titles are redacted in normal logs and in exported diagnostics.
- Diagnostics hash bundle identifiers with a per-export salt.
- Only preferences and normalized application icons reach disk.
- Window identifiers and MRU state never persist across launches.

## 4. Test plan

### Automated

| Suite | Covers |
|---|---|
| `WindowClassificationTests` | Eligibility, permissive subroles, system surfaces, degenerate geometry |
| `WindowFilteringTests` | Each filter, fail-open behavior, MRU pipeline ordering |
| `MRUOrderingTests` | Seeding, focus confirmation, sequence rebasing |
| `SwitcherSessionReducerTests` | Every phase transition, queued cycles, close and activation results |
| `SettingsTests` | Defaults, normalization, schema migration from retired payloads |
| `PanelLayout` / `SelectionScrollPlanTests` | Panel geometry and scroll policy |
| `ShortcutTests`, `ShortcutEventInterpreterTests` | Validation and event interpretation |
| `WindowRegistryRaceTests` | Concurrent refresh and focus-observation ordering |
| `DiagnosticsServiceTests`, `PrivacyRedactionTests` | Redaction guarantees |
| `TabListUITests` | Accessory lifetime, onboarding copy, settings sections |

`Scripts/benchmark_core.sh` runs deterministic 100-window microbenchmarks for
the candidate pipeline, the reducer, panel layout, and snapshot lookup.

### Manual matrix

Automated tests cannot prove real window behavior. Before a release, run
[docs/human-actions/05](docs/human-actions/05_MACOS_COMPATIBILITY_AND_PRIVATE_ABI.md)
and [docs/human-actions/06](docs/human-actions/06_PERFORMANCE_ACCESSIBILITY_HARDWARE_MATRIX.md)
on exact macOS 15 and macOS 26 builds, covering:

- Multiple Spaces, multiple displays, Stage Manager, and full-screen Spaces.
- Accessibility granted, denied, and revoked while running.
- Minimized windows, hidden applications, unclosable windows, and modal sheets.
- Duplicate, empty, and very long titles.
- Native tab groups.
- 10, 50, and 100 windows.
- Sleep, wake, lock, unlock, and display reconfiguration during a session.
- An unresponsive process, to confirm lane isolation.
- Firefox, Chrome, Safari, Finder, TextEdit, and one Electron application.

### Release gates

- Both macOS test jobs pass.
- The manual matrix passes twice on each exact Darwin build.
- Every performance budget passes in an optimized Release build.
- A clean-Mac installation, Gatekeeper launch, onboarding, and an update from
  the previous signed build all pass.
- No window content appears in caches, logs, diagnostics, or network traffic.
