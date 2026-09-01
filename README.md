# Tab-List

Tab-List is a native macOS window switcher. It keeps the familiar `Command-Tab` interaction while showing every open window as its own row in a list instead of collapsing an application's windows into one icon.

The project targets macOS 15 and later on Apple Silicon. It is a direct-download menu-bar utility, built with AppKit and SwiftUI, and distributed under the MIT License.

## What it does

Press the shortcut and a single-column list appears. Each row is one window:

| | | |
|---|---|---|
| icon | **Firefox** — Release notes — Mozilla | |
| icon | **Xcode** — TabList.xcodeproj | |
| icon | **Notes** — Weekly plan | Minimized |

Hold the modifier and press the trigger key to move down the list, add Shift to
move up, release the modifier to activate the selected window, press Escape to
cancel, or press Delete to close the selected window. Rows are ordered by most
recent focus.

The list is the whole product. There is no thumbnail grid and no application-icon
grid; the single MVP feature is the list display.

## Features

- Window-level MRU switching across every application, Space, and display.
- Forward and reverse cycling, hold-to-repeat, release-to-activate, Escape-to-cancel, and window close.
- Filters for Spaces, displays, minimized/hidden/fullscreen windows, and excluded applications.
- Native menu bar, onboarding, settings, VoiceOver, and reduced-motion behavior.
- One permission: Accessibility. No screen capture, no analytics, nothing written to disk except preferences and application icons.
- Signed Sparkle updates from GitHub Releases.

Browser tabs are not enumerated. A browser window is one row; its active tab
normally appears through the window title macOS exposes.

## How windows are discovered

Tab-List enumerates windows through the Accessibility API — the same API it uses
to raise and close them. A window that appears in the list is therefore always a
window Tab-List can act on, including windows on other Spaces, windows of hidden
applications, and minimized windows.

Each window needs a stable identity that survives a refresh. Tab-List asks the
WindowServer for the identifier of an Accessibility element when that mapping is
available on the running system, and otherwise assigns a process-scoped ordinal
that stays attached to the same Accessibility element. Neither identity is
persisted between launches.

Two unsupported, read-only WindowServer entry points are used when a harmless
runtime probe confirms they behave as expected on the running system:

| Entry point | Used for | If the probe fails |
|---|---|---|
| `_AXUIElementGetWindow` | Exact window identifiers | Process-scoped ordinals |
| `SLSCopyManagedDisplaySpaces` / `SLSCopySpacesForWindows` | Space membership | The "Visible now" scope stops narrowing and shows all desktops |

Nothing else is loaded, and no private entry point is used to activate a window.
Discovery and activation work entirely through public APIs.

## Requirements

- Apple Silicon Mac.
- macOS 15 or later.
- Full Xcode 26.x with the macOS SDK installed.
- Swift 6.2.
- [XcodeGen 2.46.0](https://github.com/yonaskolb/XcodeGen/releases/tag/2.46.0).

Tab-List needs Accessibility permission to enumerate windows, intercept the
shortcut, and activate or close the window you select. Without it the list is
empty and onboarding explains why.

## Build locally

```sh
brew install xcodegen
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
Scripts/bootstrap.sh
open TabList.xcodeproj
```

From Xcode, select the `TabList` scheme and run. The full build-and-test entry
point is:

```sh
Scripts/ci.sh
```

### Debug Accessibility permission

An ad-hoc Xcode Debug build receives a new code identity after rebuilding. macOS
may then leave the previous Tab-List entry visibly enabled under Privacy &
Security while rejecting Accessibility calls from the new binary. This does not
apply to an installed Developer ID-signed release.

If Tab-List reports that Accessibility is not granted after a rebuild:

1. Quit Tab-List.
2. Run `Scripts/reset_debug_accessibility.sh`.
3. Run Tab-List from Xcode again.
4. Choose **Request Accessibility** and approve the new prompt.

Using an Apple Development or Personal Team identity for local Debug signing
also gives rebuilds a more stable designated identity.

Command Line Tools 26.2 are sufficient for the portable validation path. It
compiles the complete application source (without bundling Sparkle or app
resources), runs the core and app-logic suites, and exercises deterministic
microbenchmarks:

```sh
swift test
Scripts/validate_clt.sh
Scripts/benchmark_core.sh
```

Full Xcode remains mandatory for XCTest UI execution, a runnable application
bundle, archiving, signing, and notarization.

`project.yml` is the source of truth for targets and build settings. Regenerate
`TabList.xcodeproj` after changing it. Do not put signing identities or update
keys in the repository; local overrides belong in ignored files or the Xcode
command line.

CI verifies that the installed XcodeGen is exactly 2.46.0 before comparing the
generated project. The Xcode workspace's committed `Package.resolved` pins
Sparkle 2.9.4 to its resolved source revision.

## Repository map

| Path | Purpose |
|---|---|
| `Sources/TabListCore` | Sendable domain models, classification, filtering, MRU, settings, layout, and session logic |
| `Sources/TabList` | AppKit/SwiftUI shell, Accessibility and WindowServer adapters, list panel, permissions, and icon cache |
| `Sources/WindowFixture` | Manual compatibility fixture with varied window types |
| `Tests` | Unit and UI tests |
| `Config` | Info plists and entitlements |
| `Scripts` | Bootstrap, CI, archive, notarization, packaging, and appcast tooling |
| `docs/ARCHITECTURE.md` | Codebase map, data flow, threading model, and where to change what |
| `docs/code-reviews` | Dated code-review records |
| `docs/release` | Candidate verification, promotion, and acceptance records |
| `docs/human-actions` | Account, legal, credential, hardware, and publication runbooks |
| `IMPLEMENTATION_PLAN.md` | Product, architecture, and acceptance specification |

## Privacy and clean-room policy

Window titles can contain sensitive material. Normal logs redact titles and
diagnostics require an explicit export. Tab-List never captures window content.
See [PRIVACY.md](PRIVACY.md).

AltTab inspired the user interaction, but Tab-List is an independent clean-room
implementation. Do not copy AltTab source, constants, assets, wording, or
branding into this repository. Reference screenshots are design evidence only
and must not ship in the application.

## Release

Releases use two separate protected workflows. `.github/workflows/release.yml`
tests, archives, signs, notarizes, staples, packages, verifies, and creates a
six-asset **draft candidate**. It never publishes. After manual compatibility,
performance, clean-install, and update acceptance, a maintainer runs
`.github/workflows/promote-release.yml`; that workflow revalidates the
immutable candidate and publishes the existing draft without rebuilding it.

Candidate creation is gated on macOS 15 and macOS 26 test jobs. Manual
candidates are accepted only from the repository's default branch; release tags
must point to a commit reachable from that branch. Versions with a pre-release
suffix, such as `1.0.0-beta.1`, are always promoted as GitHub pre-releases.
Build numbers must be greater than the newest published Sparkle build.

Create protected GitHub Environments named `release` and `release-promotion`,
each with deliberate maintainer approval. Store signing secrets only in
`release`; the promotion environment needs none. Before creating the draft, CI
verifies identities, architecture, hardened runtime, stapling, Gatekeeper,
bundled legal resources, the tag-bound appcast, package identity, and the ZIP's
EdDSA signature.

Required repository or protected-environment secrets are:

- `APPLE_DEVELOPER_ID_P12_BASE64`
- `APPLE_DEVELOPER_ID_P12_PASSWORD`
- `APPLE_DEVELOPMENT_TEAM`
- `APPLE_CODESIGN_IDENTITY`
- `APPLE_NOTARY_KEY_P8_BASE64`
- `APPLE_NOTARY_KEY_ID`
- `APPLE_NOTARY_ISSUER_ID`
- `SPARKLE_PUBLIC_ED_KEY`
- `SPARKLE_PRIVATE_ED_KEY_BASE64`

The two base64 private-key secrets contain the encoded file bytes, not a path.
Export the Sparkle key with Sparkle's `generate_keys` tool and retain an offline
backup. Never paste a secret into an issue, workflow file, build setting
committed to Git, or command-line argument that is logged.

Every `.app` and DMG includes Tab-List's license, privacy notice, third-party
notices, and Sparkle's complete upstream license. The DMG places readable copies
under `Documentation`.

See the [release candidate and promotion runbook](docs/release/RELEASE_CANDIDATE_AND_PROMOTION.md)
and [human-action index](docs/human-actions/README.md) before releasing. Also
review [CONTRIBUTING.md](CONTRIBUTING.md), [SECURITY.md](SECURITY.md), and
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

The original blue/teal layered-window icon is stored as a complete macOS asset
set. Rebuild its renditions from the reviewed source with:

```sh
Scripts/generate_app_icons.swift \
  Resources/Artwork/TabList-AppIcon-Source.png \
  Resources/TabList/Assets.xcassets/AppIcon.appiconset
```

Do not substitute AltTab artwork or other third-party branding.
