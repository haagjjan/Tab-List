# Tab-List Release Candidate and Promotion Runbook

Tab-List releases use two deliberately separate workflows:

1. **Release Candidate** builds, tests, signs, notarizes, verifies, and uploads a
   GitHub **draft** release.
2. **Promote Release Candidate** revalidates that draft and publishes it after a
   protected manual approval.

The candidate workflow never publishes a release. The promotion workflow never
rebuilds, re-signs, replaces, or adds release assets.

## Required GitHub configuration

Create two protected GitHub Environments:

- `release` grants the candidate workflow access to signing secrets. Require at
  least one maintainer approval.
- `release-promotion` is used only by the promotion workflow. Require a
  maintainer who did not initiate the candidate build when practical.

The `release` environment must contain:

- `APPLE_DEVELOPER_ID_P12_BASE64`
- `APPLE_DEVELOPER_ID_P12_PASSWORD`
- `APPLE_DEVELOPMENT_TEAM`
- `APPLE_CODESIGN_IDENTITY`
- `APPLE_NOTARY_KEY_P8_BASE64`
- `APPLE_NOTARY_KEY_ID`
- `APPLE_NOTARY_ISSUER_ID`
- `SPARKLE_PUBLIC_ED_KEY`
- `SPARKLE_PRIVATE_ED_KEY_BASE64`

`APPLE_CODESIGN_IDENTITY` must be the certificate’s complete common name, for
example `Developer ID Application: Example Name (TEAMID)`. Do not store a
generic selector such as `Developer ID Application`.

The promotion environment needs no Apple or Sparkle secrets. Its workflow uses
only GitHub’s short-lived repository token.

## Build a candidate

Run `.github/workflows/release.yml` from the default branch and provide:

- a semantic version;
- a new positive integer Sparkle build number;
- whether the eventual release is a pre-release.

A `vX.Y.Z` tag push also starts the workflow. Pre-release suffixes always produce
pre-release candidates. The source commit must be reachable from the default
branch.

The workflow:

- executes the macOS 15 and macOS 26 Apple Silicon test jobs;
- archives and performs an explicit Developer ID export;
- notarizes and staples the exported application;
- builds, signs, notarizes, and staples the DMG;
- generates the EdDSA-signed Sparkle appcast;
- checks every Mach-O is arm64-only;
- checks the bundle identifier, Developer ID team and authority, hardened
  runtime, disabled App Sandbox, stable feed URL, legal resources, nested code
  signatures, stapling, and Gatekeeper;
- extracts and verifies the application in both the update ZIP and DMG;
- creates checksums, a release manifest, and notarization/verification evidence;
- creates a draft GitHub release.

The application’s feed remains:

`https://github.com/haagjjan/Tab-List/releases/latest/download/appcast.xml`

There is no separate or implicit beta feed. GitHub does not treat a pre-release
as the latest stable release.

## Review the draft

Before promotion:

1. Confirm both compatibility jobs passed.
2. Download the `Release-Candidate-Evidence-*` workflow artifact.
3. Review `release-manifest.json`.
4. Confirm both notarization summaries say `Accepted`.
5. Confirm the manual compatibility and performance acceptance record is
   complete.
6. Test the draft DMG on a clean Mac before publication when performing a 1.0
   or other high-risk release.
7. Record the exact tag and 40-character source commit.

Do not edit draft assets. Any asset change invalidates the candidate. Build a
new candidate with a new version or remove the failed draft and rerun only after
documenting why the previous candidate was discarded.

Promote or reject the candidate within the immutable workflow artifact’s
90-day retention window. If that evidence expires, reject the draft and build a
new candidate; do not bypass the provenance comparison.

## Promote a candidate

Run `.github/workflows/promote-release.yml` and enter:

- the draft tag;
- the exact 40-character source commit from `release-manifest.json`;
- `PROMOTE <tag>` as the confirmation value.

After the protected-environment reviewer approves, the workflow independently:

- requires the release to still be a draft;
- validates its exact six-asset set;
- checks `SHA256SUMS`;
- downloads the successful candidate run’s immutable Actions artifact and
  requires its manifest, checksums, and evidence archive to match the draft
  byte-for-byte;
- validates the release manifest, source commit, tag, and pre-release state;
- validates the app and DMG notarization evidence;
- validates the Developer ID export options;
- validates the tag-bound appcast URL;
- rechecks that draft metadata and assets did not change during validation;
- publishes the existing draft;
- verifies the published tag resolves to the validated commit.

The workflow uploads a long-retention promotion evidence artifact whether the
promotion succeeds or fails.

## Failure handling

- A failed candidate workflow does not publish anything.
- A failed notarization preserves Apple’s submission JSON and log as workflow
  evidence.
- A failed promotion leaves the release as a draft unless publication itself
  already succeeded. Inspect the promotion evidence before taking any action.
- Never bypass the promotion workflow with `gh release edit --draft=false`.
- Never paste certificate data, private keys, API keys, or decoded secrets into
  logs, issues, release notes, or evidence files.
