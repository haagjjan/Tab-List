# Tab-List Human and External Action Runbooks

These runbooks cover the release gates that cannot be completed safely or
truthfully by Codex alone. They require an account owner, a legal agreement,
private-key custody, administrator authorization, physical macOS interaction,
external testers, or a final publication decision.

The files contain no credentials. Do not record secret values, Apple Account
details, private window titles, device serial numbers, hardware UUIDs, or
unredacted diagnostics in them.

## Current repository facts

At the time these runbooks were created:

- The local Apple Silicon Mac has macOS 26 but only Apple Command Line Tools
  selected. Full Xcode is not installed or selected.
- XcodeGen 2.46.0 is installed.
- GitHub CLI is installed but is not authenticated.
- `origin` points to `https://github.com/haagjjan/Tab-List.git`; the remote
  repository is public and currently has no pushed branch.
- The candidate workflow expects a protected environment named `release` and
  nine release secrets. The separate no-rebuild publisher expects a protected
  `release-promotion` environment and no long-lived secrets.
- The two unsupported read-only WindowServer capabilities are probe-gated at
  runtime; there is no private activation path and no build allowlist to edit.
- Tab-List is a direct-download application. It is not a Mac App Store app.

## What is not required

- **Do not create a Mac App Store or App Store Connect app record.** Direct
  Developer ID distribution and notarization do not require a store listing.
- **Do not create a GitHub App or OAuth app.** The workflows use GitHub
  Actions' scoped `GITHUB_TOKEN`.
- Do not enable App Sandbox merely for distribution. The project deliberately
  ships outside the Mac App Store and needs global input and Accessibility
  behavior.

## Required sequence

Complete the tasks in this order. Later tasks depend on the evidence produced
by earlier ones.

| Order | Runbook | Human outcome | What it unlocks |
|---:|---|---|---|
| 1 | [Install full Xcode](01_INSTALL_FULL_XCODE.md) | Xcode 26 and its legal terms are accepted and selected | Real builds, XCTest, archives, signing tools |
| 2 | [Apple Developer and notarization](02_APPLE_DEVELOPER_AND_NOTARIZATION.md) | Active membership and protected Developer ID/notary credentials | Signed and notarized artifacts |
| 3 | [Sparkle signing key](03_CREATE_AND_CUSTODY_SPARKLE_KEY.md) | One recoverable EdDSA update-signing root | Authenticated in-app updates |
| 4 | [Initialize and secure GitHub](04_INITIALIZE_AND_SECURE_GITHUB.md) | Source is pushed; CI, environment, and security controls are active | Hosted CI and protected releases |
| 5 | [Compatibility and private ABI](05_MACOS_COMPATIBILITY_AND_PRIVATE_ABI.md) | Exact macOS builds have reproducible fixture evidence | Confidence that discovery, activation, and degraded fallback are correct |
| 6 | [Performance, accessibility, and hardware](06_PERFORMANCE_ACCESSIBILITY_HARDWARE_MATRIX.md) | Release budgets and inclusive behavior pass on real hardware | Evidence-based release approval |
| 7 | [Signed beta and 1.0 acceptance](07_SIGNED_BETA_AND_1_0_RELEASE_ACCEPTANCE.md) | Two fresh-install passes and a verified beta-to-1.0 update | Public 1.0 publication |

## Handoff protocol

For each task:

1. Perform only the section labelled **Human action**.
2. Preserve the non-secret evidence listed under **Evidence to retain**.
3. Never paste credentials or private-key material into chat.
4. Tell Codex which numbered task is complete and provide only the safe
   evidence requested by that runbook.
5. Let Codex perform the follow-up validation or source changes.

If a step fails, stop at that task. Do not work around certificate, signature,
notarization, private-ABI, or update-verification failures.

## Authoritative references

- [Apple Developer Program enrollment](https://developer.apple.com/help/account/membership/program-enrollment)
- [Apple Developer ID](https://developer.apple.com/developer-id/)
- [Apple notarization workflow](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- [GitHub Actions deployment environments](https://docs.github.com/en/actions/concepts/workflows-and-actions/deployment-environments)
- [Sparkle documentation](https://sparkle-project.org/documentation/)
