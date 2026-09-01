# Human Action 07 — Signed Beta and Tab-List 1.0 Acceptance

## Purpose

Run the controlled external rollout, verify signed and notarized artifacts on
fresh Macs, prove the Sparkle update path, approve the legal and privacy
statements, and make the final human decision to publish Tab-List 1.0.

The release is not complete merely because CI creates a DMG.

## Why this needs a human

This task includes protected-environment approval, distribution to other
people, macOS permission prompts, clean-install observation, legal/policy
approval, publication, incident judgment, and rollback decisions. Codex can
prepare and verify evidence but cannot accept those risks or publish on the
owner's behalf without explicit authorization.

## Prerequisites

All earlier runbooks are complete:

- [Full Xcode](01_INSTALL_FULL_XCODE.md).
- [Apple Developer and notarization](02_APPLE_DEVELOPER_AND_NOTARIZATION.md).
- [Sparkle key custody](03_CREATE_AND_CUSTODY_SPARKLE_KEY.md).
- [GitHub repository security](04_INITIALIZE_AND_SECURE_GITHUB.md).
- [macOS/private-ABI compatibility](05_MACOS_COMPATIBILITY_AND_PRIVATE_ABI.md).
- [Performance and accessibility](06_PERFORMANCE_ACCESSIBILITY_HARDWARE_MATRIX.md).

Also require:

- Green macOS 15 and macOS 26 automated CI.
- A reviewed release commit reachable from protected `main`.
- A monotonic positive build number.
- Release notes with no private information.
- Two clean Apple Silicon test environments, or one that can be restored to a
  proven fresh snapshot between passes.
- At least one tester other than the primary developer for the private alpha.
- A documented owner for rollback and key compromise.

## Human pre-publication approval

Before producing a public beta, explicitly review:

- The MIT `LICENSE`.
- `PRIVACY.md`.
- `SECURITY.md`.
- `THIRD_PARTY_NOTICES.md` and the bundled Sparkle license.
- The copyright name in the application metadata.
- The clean-room statement and original artwork provenance.
- The absence of analytics, advertising, crash upload, accounts, and cloud
  sync.
- The statement that no window screenshots are intentionally written to disk.
- The release notes and known limitations.

If any statement is inaccurate, stop and ask Codex to repair the product or
documentation. This checklist is not legal advice; the owner is responsible for
obtaining professional advice if their jurisdiction or organization requires
it.

## No store submission is needed

Do **not** create or submit:

- A Mac App Store record.
- An App Store Connect app listing.
- Store screenshots, pricing, review notes, or an SKU.
- A GitHub App.

Tab-List 1.0 is a direct GitHub Release distributed as a notarized DMG and
updated through Sparkle.

## Human action

### A. Private alpha

1. Produce a Developer ID-signed and notarized alpha from the reviewed commit.
2. Share it privately with a small set of trusted Apple Silicon testers.
3. Require testers to use synthetic or non-sensitive windows when reporting.
4. Collect:
   - macOS version and exact build.
   - Tab-List version/build.
   - Permission state.
   - Display/Space/Stage Manager configuration.
   - Reproduction steps.
   - Redacted diagnostics.
5. Resolve every release-blocking defect before beta.

### B. GitHub pre-release beta

1. Choose a semantic prerelease version such as:

   ```text
   1.0.0-beta.1
   ```

2. Choose a build number higher than every published Sparkle build.
3. Review the exact source SHA and workflow diff.
4. Dispatch the protected **Release Candidate** workflow from `main` with
   prerelease enabled, or push a reviewed prerelease tag according to the
   current workflow.
5. Approve the `release` environment only after confirming the SHA, version,
   build, and secret-using steps.
6. Wait for both operating-system test jobs and all signing/notarization steps.
7. Confirm the resulting release is still a **draft** and contains exactly:
   - The signed, notarized DMG.
   - The Sparkle ZIP.
   - `appcast.xml`.
   - `release-manifest.json`.
   - `release-evidence.zip`.
   - `SHA256SUMS`.
8. Complete the draft review in
   `docs/release/RELEASE_CANDIDATE_AND_PROMOTION.md`.
9. Dispatch **Promote Release Candidate** with the exact tag, 40-character
   source commit, and required confirmation string.
10. Approve `release-promotion` only after reviewing the acceptance evidence.
11. Confirm the published GitHub release is marked **Pre-release** and still
    contains the exact same six assets.
12. Preserve candidate and promotion workflow run IDs plus Apple notarization
    submission IDs.

If the repository introduces a separate beta update feed, test beta-to-beta
updates. GitHub's `releases/latest` endpoint excludes prereleases, so do not
claim beta-to-beta support while the app uses only
`/releases/latest/download/appcast.xml`.

### C. Fresh-install Gatekeeper test

On a clean Mac or restored clean snapshot:

1. Download the DMG through a normal browser from the GitHub Release. Do not
   copy a local build; the download should receive normal quarantine metadata.
2. Confirm quarantine is present:

   ```sh
   xattr -p com.apple.quarantine "/path/to/TabList-1.0.0-beta.1.dmg"
   ```

3. Assess the DMG:

   ```sh
   codesign --verify --strict --verbose=2 \
     "/path/to/TabList-1.0.0-beta.1.dmg"
   xcrun stapler validate \
     "/path/to/TabList-1.0.0-beta.1.dmg"
   spctl --assess --type open \
     --context context:primary-signature \
     --verbose=2 \
     "/path/to/TabList-1.0.0-beta.1.dmg"
   ```

4. Open the DMG and drag TabList.app to Applications.
5. Verify the installed application:

   ```sh
   codesign --verify --deep --strict --verbose=2 \
     /Applications/TabList.app
   xcrun stapler validate /Applications/TabList.app
   spctl --assess --type execute --verbose=2 \
     /Applications/TabList.app
   ```

6. Launch through Finder. Gatekeeper must not report an unidentified or damaged
   application.
7. Verify the application has no normal Dock icon.

### D. First-run and functional acceptance

Using the release checklist and synthetic data:

1. Complete onboarding.
2. Grant Accessibility and verify that denial/revocation states remain safe.
3. Verify three Firefox windows appear as three separate rows, each showing
   its own window title.
4. Repeat that check with Chrome, Safari, Finder, TextEdit, and one Electron
   application.
5. Verify:
   - Forward and reverse cycling.
   - Release-to-commit.
   - Escape cancellation.
   - Delete and close button close only the window.
   - Mouse activation.
   - Minimized, hidden, full-screen, cross-Space, and cross-display windows.
   - Browser window titles reflect the active browser tab when exposed.
6. Confirm an unsaved-document close prompt activates the app and leaves the
   decision to the user.
7. Confirm temporary disable and Quit immediately restore native
   `Command-Tab`.
8. Confirm Launch at Login reflects macOS approval state.
9. Confirm revoking Accessibility stops all switcher behavior and that granting
   it again restores the list without a relaunch.
10. Confirm no window image file appears in Caches or Application Support.
11. Confirm network traffic is limited to the GitHub-hosted Sparkle update
    check/download.
12. Review exported diagnostics before sharing.

### E. Update acceptance

The mandatory 1.0 proof is an update from a previously signed beta to the
stable 1.0 candidate:

1. Install the prior beta from its public release.
2. Confirm its Apple and Sparkle signatures.
3. Expose the exact candidate ZIP and a test copy of its appcast through an
   owner-approved temporary HTTPS staging location. Do not modify the ZIP.
   Point only the test Mac at that appcast with Sparkle’s supported
   user-default override:

   ```sh
   defaults write com.haagjjan.TabList SUFeedURL \
     "https://OWNER-CONTROLLED-STAGING.example/appcast.xml"
   ```

   The test appcast may change only its enclosure URL so it reaches the exact
   candidate ZIP; the EdDSA signature, archive length, version, and build must
   remain those produced by the candidate workflow.
4. Use **Check for Updates** in the installed beta.
5. Confirm Sparkle displays the expected version and release notes.
6. Install the update.
7. Confirm the app relaunches as the new version/build.
8. Confirm settings and exclusions migrate.
9. Repeat core switching and permission checks.
10. Confirm the update archive URL, length, and EdDSA signature match the
    staged appcast and candidate manifest.
11. Remove the test override immediately afterward:

    ```sh
    defaults delete com.haagjjan.TabList SUFeedURL
    ```

12. Delete the temporary staging objects after retaining their hashes and test
    evidence. Confirm the installed app again reads the production
    `/releases/latest/download/appcast.xml` feed.

Do not treat installing the final DMG over the beta as proof of the Sparkle
update path.

### F. Two-pass final acceptance

Run the complete release acceptance checklist twice:

- Pass 1 on a fresh macOS 15 Apple Silicon environment.
- Pass 2 on a fresh macOS 26 Apple Silicon environment.

Each pass must start from a clean installation state and use the exact candidate
artifacts intended for publication.

Only after both passes and the update test succeed may the owner approve the
stable 1.0 publication.

## Evidence to retain

For alpha, beta, and final candidate, retain:

| Evidence | Required value |
|---|---|
| Source | Commit SHA and reviewed tag |
| Release | Version and monotonically increasing build |
| Automation | Workflow run URL and job results |
| Signing | Developer ID identity, Team ID, certificate expiry |
| Notarization | Submission IDs and accepted status for app and DMG |
| Stapling/Gatekeeper | Passing command output |
| Sparkle | Public key, appcast URL, archive length, verification result |
| Compatibility | macOS 15 and 26 result-sheet references |
| Performance | Passing redacted summary |
| Fresh installs | Two signed/date-stamped checklists |
| Update | Prior-beta-to-1.0 proof |
| Approval | Named human approver and date |

Never store credential values, private keys, real window titles, private
screenshots, Apple Account data, device identifiers, or unreviewed traces in
release evidence.

## Failure and rollback rules

- Before stable publication: do not promote a failed candidate. Fix it, increase
  the build number, and issue a new candidate.
- Never replace assets silently under an existing version/tag.
- Never reuse a Sparkle build number.
- If a published build is defective but signatures are intact, publish a
  higher-build corrective update rather than a downgrade.
- If a signing key may be compromised, stop publication, restrict environment
  access, revoke the affected credential, and follow the documented Apple or
  Sparkle rotation path.
- Preserve rejected notarization logs with credentials and personal data
  redacted.
- If privacy invariants fail, remove public artifacts while investigating and
  disclose according to `SECURITY.md`.

## What Codex can do afterward

Codex can:

1. Verify release metadata, checksums, signatures, notarization, architecture,
   entitlements, appcast, and bundled notices.
2. Monitor the protected workflow after the human approves it.
3. Compare test evidence against every acceptance criterion.
4. Prepare release notes and a rollback plan.
5. Diagnose a failed install or update.
6. Confirm the remote release artifacts match the locally verified hashes.

Codex may publish, edit, or remove a GitHub Release only after the owner gives
explicit authorization for that exact external action.

## Official references

- [Apple Developer ID](https://developer.apple.com/developer-id/)
- [Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- [Safely open apps on Mac](https://support.apple.com/102445)
- [Sparkle publishing documentation](https://sparkle-project.org/documentation/publishing/)
- [Sparkle documentation](https://sparkle-project.org/documentation/)
- [GitHub Releases](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases)
- [Reviewing deployments](https://docs.github.com/en/actions/managing-workflow-runs-and-deployments/managing-deployments/reviewing-deployments)
