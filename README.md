# Tab-List

Tab-List is a native macOS window switcher. It keeps the familiar `Command-Tab` interaction while showing each open window as its own selectable item instead of collapsing every window into one application icon.

The project targets macOS 15 and later on Apple Silicon. It is a direct-download menu-bar utility, built with AppKit and SwiftUI, and distributed under the MIT License.

> [!IMPORTANT]
> Tab-List is under active development. Its cross-Space compatibility layer uses unsupported macOS WindowServer APIs behind a capability-checked adapter. A macOS update can degrade those capabilities; public fallbacks must remain functional and failures must never crash the app.
>
> The checked-in private-ABI allowlists are intentionally empty until the
> macOS 15/macOS 26 fixture matrices are run on exact Darwin builds. This tree
> therefore builds as a safe implementation candidate with current-Space
> public fallbacks; it is not yet the signed 1.0 release.

## Features

- Window-level MRU switching across applications.
- Thumbnail, app-icon, and compact title presentation modes.
- Forward and reverse cycling, release-to-activate, Escape-to-cancel, and window close.
- Filters for Spaces, displays, minimized/hidden/fullscreen windows, and excluded apps.
- Native menu-bar, onboarding, settings, VoiceOver, and reduced-motion/transparency behavior.
- No analytics and no window screenshots written to disk.
- Signed Sparkle updates from GitHub Releases.

Browser tabs are intentionally not enumerated. A browser window is one item; its active tab normally appears through the window title exposed by macOS.

## Requirements

- Apple Silicon Mac.
- macOS 15 or later.
- Full Xcode 26.x with the macOS SDK installed.
- Swift 6.2.
- [XcodeGen 2.46.0](https://github.com/yonaskolb/XcodeGen/releases/tag/2.46.0).

The application needs Accessibility permission to intercept the shortcut and activate or close exact windows. Screen Recording is optional and used only in Thumbnail mode.

## Build locally

```sh
brew install xcodegen
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
Scripts/bootstrap.sh
open TabList.xcodeproj
```

From Xcode, select the `TabList` scheme and run. The command-line build and test entry point is:

```sh
Scripts/ci.sh
```

With full Xcode selected, the framework-neutral core can also be tested through
Swift Package Manager:

```sh
swift test
```

`project.yml` is the source of truth for targets and build settings. Regenerate `TabList.xcodeproj` after changing it. Do not put signing identities or update keys in the repository; local overrides belong in ignored files or the Xcode command line.

CI verifies that the installed XcodeGen is exactly 2.46.0 before comparing the generated project. The Xcode workspace’s committed `Package.resolved` pins Sparkle 2.9.4 to its resolved source revision.

## Repository map

| Path | Purpose |
|---|---|
| `Sources/TabListCore` | Sendable domain models, filtering, MRU, settings, and session logic |
| `Sources/TabList` | AppKit/SwiftUI shell, macOS adapters, panel, permissions, and caches |
| `Sources/WindowFixture` | Manual compatibility fixture with varied window types |
| `Tests` | Unit and UI tests |
| `Config` | Info plists and entitlements |
| `Scripts` | Bootstrap, CI, archive, notarization, packaging, and appcast tooling |
| `IMPLEMENTATION_PLAN.md` | Product, architecture, rollout, and acceptance specification |

## Privacy and clean-room policy

Window titles and previews may contain sensitive material. Normal logs redact titles, diagnostics require an explicit export, and thumbnail pixels remain in a bounded in-memory cache. See [PRIVACY.md](PRIVACY.md).

AltTab inspired the user interaction, but Tab-List is an independent clean-room implementation. Do not copy AltTab source, constants, assets, wording, or branding into this repository. Reference screenshots are design evidence only and must not ship in the application.

## Release

Tagged and manually dispatched releases run the signing workflow in `.github/workflows/release.yml`. Maintainers must configure Developer ID, App Store Connect notarization, and Sparkle EdDSA secrets before publishing. The workflow tests, archives, signs, notarizes, staples, packages, generates the appcast, and creates the GitHub Release.

The workflow gates publication on macOS 15 and macOS 26 test jobs. Manual releases are accepted only from the repository’s default branch; release tags must point to a commit reachable from that branch. Versions with a pre-release suffix, such as `1.0.0-beta.1`, are always published as GitHub pre-releases. Build numbers must be greater than the newest published Sparkle build.

Create a protected GitHub Environment named `release`, require maintainer approval, and store the release secrets there. Before upload, CI verifies the archived version/build/public key, legal resources, appcast URL and length, and the ZIP’s EdDSA signature.

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

The two base64 private-key secrets contain the encoded file bytes, not a path. Export the Sparkle key with Sparkle’s `generate_keys` tool and retain an offline backup. Never paste a secret into an issue, workflow file, build setting committed to Git, or command-line argument that is logged.

Every `.app` and DMG includes Tab-List’s license, privacy notice, third-party notices, and Sparkle’s complete upstream license. The DMG places readable copies under `Documentation`.

See [CONTRIBUTING.md](CONTRIBUTING.md), [SECURITY.md](SECURITY.md), and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) before contributing or releasing.

The original blue/teal layered-window icon is stored as a complete macOS asset set. Rebuild its renditions from the reviewed source with:

```sh
Scripts/generate_app_icons.swift \
  Resources/Artwork/TabList-AppIcon-Source.png \
  Resources/TabList/Assets.xcassets/AppIcon.appiconset
```

Do not substitute AltTab artwork or other third-party branding.
