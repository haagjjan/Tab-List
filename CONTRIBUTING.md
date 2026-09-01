# Contributing to Tab-List

Thank you for helping build Tab-List. Contributions should preserve fast native behavior, local-first privacy, graceful compatibility fallback, and the project’s clean-room boundary.

## Development setup

Install macOS 15 or later on Apple Silicon, full Xcode 26.x, and XcodeGen 2.46.0:

```sh
brew install xcodegen
xcodegen --version # must print: Version: 2.46.0
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
Scripts/bootstrap.sh
```

Run the complete local check with:

```sh
Scripts/ci.sh
```

The project file is generated from `project.yml`. Edit the YAML or source tree, regenerate, and include a refreshed `TabList.xcodeproj` when project structure changes.

Do not remove or casually regenerate the workspace `Package.resolved`; it pins the exact Sparkle revision used for signed update builds. Dependency upgrades must update `project.yml`, `Package.resolved`, third-party notices, and release verification together.

Read [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) before your first change. It
maps the modules, the discovery pipeline, the threading model, and which file
owns each decision.

## Engineering boundaries

- Keep domain models and pure behavior in `TabListCore`.
- Keep AppKit, Accessibility, Workspace, Carbon, and WindowServer details in the app adapters.
- Do not put `AXUIElement`, `NSImage`, or other non-Sendable framework objects into Sendable records.
- Do not perform Accessibility or WindowServer IPC synchronously on the main actor.
- Read each Accessibility window's attributes once per discovery. Repeated attribute reads are IPC round trips, not property accesses.
- Keep every Accessibility call for one process on that process's serial lane, so a slow application cannot stall the others.
- Keep the event-tap callback minimal and dispatch a small command to the main actor.
- Isolate every private symbol in the WindowServer bridge, gate it behind a runtime probe, and give it a public fallback.
- Make classification and filtering fail open. A rule that cannot evaluate its input must keep the window rather than hide it.
- Never log window titles, and never add a screen-capture dependency.
- Do not copy AltTab code, constants, assets, strings, tests, or visual branding. Behavioral inspiration is not permission to incorporate GPL-licensed implementation material.

## Testing

Add unit coverage for pure logic and typed failure paths. Use `WindowFixture` for standard, untitled, repeated, tabbed, utility, unclosable, modal, minimized, and fullscreen scenarios. For behavior touching window activation, also exercise:

- Current and other Spaces.
- One and multiple displays.
- Accessibility granted, denied, and revoked.
- A minimized window and hidden application.
- Rapid cycling and Escape cancellation.
- Sleep/wake or display reconnection when relevant.

Any change to discovery, classification, or identity must be checked against a
running Firefox, Chrome, Safari, Finder, and one Electron application. Those are
the applications whose window lists diverge most from a plain AppKit app.

UI changes should be checked with VoiceOver, Reduce Motion, Increase Contrast, Light/Dark appearance, and long titles.

### Private ABI rules

`WindowServerBridge` owns every unsupported symbol. Two rules govern additions:

1. **Read-only only.** No private entry point may mutate window, focus, or
   Space state. Activation goes through public Accessibility API.
2. **Probe before use.** A capability starts pending, runs one harmless probe
   whose result can be checked against a public source of truth, and is enabled
   only if that probe succeeds. A failed probe disables the capability for the
   process lifetime and its caller degrades.

Symbol presence is never sufficient, and a probe that only proves "the call did
not crash" is not a probe. The window-identifier probe, for example, requires
that an identifier reported for an Accessibility window also appears in the
public window list for that same process.

Confirm degraded behavior by testing with each capability forced off, and record
the exact hardware and OS build in the compatibility evidence.

## Pull requests

Keep changes focused and explain:

- The user-visible outcome.
- The macOS/API boundary changed.
- Failure and permission states considered.
- Automated and manual verification performed.
- Performance or privacy impact.

Do not commit generated screenshots containing private content, DerivedData, signing identities, exported keys, notarization credentials, or local configuration.

By contributing, you agree that your contribution is licensed under the repository’s MIT License.
