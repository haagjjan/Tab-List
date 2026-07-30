# Human Action 01 — Install and Select Full Xcode 26

## Purpose

Install a complete Xcode 26.x toolchain so Tab-List can run its real XCTest and
UI-test bundles, build archives, sign code, and use Apple's notarization tools.

The current machine has only `/Library/Developer/CommandLineTools` selected.
That is sufficient for limited source checks but not for the release gates.

## Why this needs a human

Downloading Xcode may require an Apple Account. First launch installs privileged
components and presents Apple license terms. Selecting the toolchain requires
administrator authorization. Codex cannot accept a legal agreement, enter an
account credential, approve an administrator prompt, or decide to upgrade
macOS on the owner's behalf.

## Prerequisites

- An Apple Silicon Mac running a version of macOS supported by the chosen Xcode
  26 release.
- An Apple Account if the selected Apple download path requires one.
- Administrator access.
- Enough free disk space for Xcode, platform components, DerivedData, and Swift
  packages.
- A current backup before any macOS upgrade.

Do not upgrade macOS merely to obtain the newest Xcode point release without
reviewing the compatibility consequences. Any Xcode 26.x build that supplies
Swift 6.2 and the required macOS SDK is acceptable for initial local
validation. Release CI should later pin the exact toolchain it uses.

## Human action

1. Download full Xcode from the Mac App Store or
   [Apple Developer downloads](https://developer.apple.com/download/all/).
   Use only an Apple-hosted source.
2. Place the application in `/Applications`. A versioned name such as
   `/Applications/Xcode_26.3.app` is acceptable.
3. Open Xcode once.
4. Review and accept the license terms yourself.
5. Allow Xcode to install its required components.
6. If Xcode asks to install additional macOS platform support, install it.
7. Select the installation. For the standard application name:

   ```sh
   sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
   ```

   For a versioned application, substitute its exact path. The repository also
   provides `Scripts/select_xcode_26.sh`, but it invokes `sudo` and therefore
   still requires your authorization.
8. Complete first-launch setup if Xcode did not already do so:

   ```sh
   sudo xcodebuild -runFirstLaunch
   ```

9. Verify the selected installation without editing the repository:

   ```sh
   xcode-select -p
   xcodebuild -version
   xcrun swift --version
   xcrun --sdk macosx --show-sdk-version
   xcodebuild -showsdks
   ```

## Expected verification

- `xcode-select -p` ends in `.app/Contents/Developer`.
- `xcodebuild -version` reports Xcode 26.x.
- `xcrun swift --version` reports Swift 6.2.
- A macOS SDK is listed and can build with deployment target macOS 15.
- No command reports that the active developer directory is a Command Line
  Tools instance.

## Evidence to retain

Share these non-secret values with Codex:

- Selected Xcode path.
- Xcode version and build number.
- Swift version.
- macOS SDK version.
- Any first-launch error text.

Do not share the Apple Account name, password, recovery data, device serial
number, hardware UUID, or full `system_profiler` output.

## Security and safety cautions

- Read the Apple terms before accepting them.
- Enter Apple Account credentials only in Apple software or on an
  `apple.com` page.
- Confirm the exact path before running `sudo xcode-select`.
- Do not disable Gatekeeper or System Integrity Protection.
- Do not install unsigned toolchain packages from mirrors.
- Keep local signing overrides and DerivedData out of Git.

## What Codex can do afterward

Once the human action is complete, Codex can:

1. Run `Scripts/bootstrap.sh`.
2. Regenerate and compare `TabList.xcodeproj`.
3. Run `Scripts/ci.sh` and inspect the resulting `.xcresult`.
4. Run the real unit and UI tests.
5. Build the fixture and application in Debug and optimized Release
   configurations.
6. Repair test, build, or project-generation failures that do not require new
   credentials or permissions.

Completion of this task does not grant Accessibility or Screen Recording
permission; those remain explicit hands-on test actions.

## Official references

- [Xcode resources](https://developer.apple.com/xcode/resources/)
- [Apple Developer downloads](https://developer.apple.com/download/all/)
- [Apple software licensing agreements](https://developer.apple.com/support/terms/)
- [Xcode](https://developer.apple.com/xcode/)
