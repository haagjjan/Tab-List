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

## Engineering boundaries

- Keep domain models and pure behavior in `TabListCore`.
- Keep AppKit, Accessibility, ScreenCaptureKit, Workspace, Carbon, and WindowServer details in the app/adapters.
- Do not put `AXUIElement`, `NSImage`, `SCWindow`, or other non-Sendable framework objects into Sendable records.
- Do not perform Accessibility or WindowServer IPC synchronously on the main actor.
- Keep the event-tap callback minimal and dispatch a small command to the main actor.
- Isolate every private symbol in the WindowServer bridge and add a public fallback.
- Never persist thumbnail pixels or log window titles.
- Do not initialize ScreenCaptureKit in Icon or Title mode.
- Do not copy AltTab code, constants, assets, strings, tests, or visual branding. Behavioral inspiration is not permission to incorporate GPL-licensed implementation material.

## Testing

Add unit coverage for pure logic and typed failure paths. Use `WindowFixture` for standard, untitled, repeated, tabbed, utility, unclosable, modal, minimized, and fullscreen scenarios. For behavior touching window activation, also exercise:

- Current and other Spaces.
- One and multiple displays.
- Accessibility and Screen Recording granted, denied, and revoked.
- A minimized window and hidden application.
- Rapid cycling and Escape cancellation.
- Sleep/wake or display reconnection when relevant.

UI changes should be checked with VoiceOver, Reduce Transparency, Reduce Motion, Increase Contrast, Light/Dark appearance, and long titles.

### Private ABI validation

Private capabilities are release-disabled unless the exact Darwin build from
`sysctl -n kern.osversion` appears in the corresponding compatibility allowlist
inside `WindowServerBridge`. For fixture work only, a Debug launch may opt in
with `TABLIST_ENABLE_UNVERIFIED_SPACE_APIS=1` and/or
`TABLIST_ENABLE_UNVERIFIED_EXACT_ACTIVATION=1` and/or
`TABLIST_ENABLE_UNVERIFIED_AX_WINDOW_ID=1`.

Never set those variables in Release, CI publication, or a user build. Exercise
the complete Space/display/minimized/fullscreen activation matrix, confirm the
bridge's structural probes and redacted diagnostics, record the exact hardware
and OS build in the compatibility test evidence, and only then add that build
to an allowlist. Symbol presence or a macOS major version is not validation.

## Pull requests

Keep changes focused and explain:

- The user-visible outcome.
- The macOS/API boundary changed.
- Failure and permission states considered.
- Automated and manual verification performed.
- Performance or privacy impact.

Do not commit generated screenshots containing private content, DerivedData, signing identities, exported keys, notarization credentials, or local configuration.

By contributing, you agree that your contribution is licensed under the repository’s MIT License.
