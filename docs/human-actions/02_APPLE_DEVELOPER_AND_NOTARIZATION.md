# Human Action 02 — Apple Developer, Developer ID, and Notarization

## Purpose

Establish the legal account and cryptographic credentials needed to distribute
Tab-List directly as a Developer ID-signed and notarized macOS application.

Tab-List does not use the Mac App Store. The required Apple services are the
paid Apple Developer Program, a **Developer ID Application** certificate, and
notarization authentication.

## Why this needs a human

Apple enrollment can require identity or organization verification, legal
authority, two-factor authentication, agreement acceptance, and payment. The
Account Holder must decide which legal name signs the application and who may
use release credentials. Private-key creation, export, and custody are security
decisions that Codex cannot make autonomously.

## Prerequisites

- [Full Xcode 26 installed](01_INSTALL_FULL_XCODE.md).
- An Apple Account with two-factor authentication.
- Authority to enroll as an individual or to bind the chosen organization.
- A decision about the legal signing identity users should see.
- Secure storage for a certificate archive, API key, passwords, and recovery
  notes.
- GitHub secret provisioning will be done later through
  [Human Action 04](04_INITIALIZE_AND_SECURE_GITHUB.md).

## Human action

### A. Enroll or verify membership

1. Sign in to the
   [Apple Developer account](https://developer.apple.com/account/).
2. Enroll in or renew the Apple Developer Program.
3. Review and accept the current Apple Developer agreements.
4. Complete identity, organization, and payment steps directly with Apple.
5. Confirm that the membership is active and record the ten-character Team ID.
6. Confirm that the displayed legal name is appropriate for public
   distribution.

### B. Create the Developer ID Application identity

1. On a protected Mac, create a certificate signing request through Keychain
   Access. Keep the generated private key in the login keychain.
2. In Certificates, Identifiers & Profiles, create a
   **Developer ID Application** certificate.
3. Do not create a Developer ID Installer certificate; Tab-List distributes an
   application in a DMG, not an installer package.
4. Download and install the certificate on the same Mac that owns the private
   key.
5. Confirm that the identity appears under:

   ```sh
   security find-identity -v -p codesigning
   ```

6. Export the certificate **with its private key** as a password-protected
   `.p12`.
7. Store the `.p12` and its password separately in protected storage.
8. Record the complete identity string, normally:

   ```text
   Developer ID Application: Legal Name (TEAMID)
   ```

### C. Create notarization authentication

1. In App Store Connect, request API access if the account has not enabled it.
2. As Account Holder or Admin, create a dedicated API key for Tab-List release
   notarization using the minimum role Apple currently documents as sufficient.
3. Download the `.p8` exactly once.
4. Record its Key ID and Issuer ID.
5. Store the `.p8` in protected storage separate from the Developer ID `.p12`.
6. Define who may revoke or replace the key if it is exposed.

### D. Map values to workflow secrets

The release workflow expects these Apple values:

| Secret | Source |
|---|---|
| `APPLE_DEVELOPER_ID_P12_BASE64` | Base64 encoding of the exported `.p12` file bytes |
| `APPLE_DEVELOPER_ID_P12_PASSWORD` | Password chosen when exporting the `.p12` |
| `APPLE_DEVELOPMENT_TEAM` | Apple Developer Team ID |
| `APPLE_CODESIGN_IDENTITY` | Complete Developer ID Application identity string |
| `APPLE_NOTARY_KEY_P8_BASE64` | Base64 encoding of the downloaded `.p8` file bytes |
| `APPLE_NOTARY_KEY_ID` | App Store Connect API Key ID |
| `APPLE_NOTARY_ISSUER_ID` | App Store Connect Issuer ID |

Do not generate base64 values into a tracked file. Pipe file bytes directly
into GitHub secret input when completing Human Action 04.

## No store record is needed

Do **not** create:

- A Mac App Store listing.
- An App Store Connect app record.
- An SKU, pricing record, store metadata, or App Review submission.
- A provisioning profile solely for this application.

The project has no restricted App Store capability and its entitlements file is
empty. Direct Developer ID signing and notarization are the intended path.

## Evidence to retain

Retain privately:

- Membership status and renewal date.
- Legal signing identity and Team ID.
- Developer ID certificate serial number and expiration date.
- Secure storage locations for the `.p12` and `.p8`.
- API Key ID and Issuer ID.
- Revocation owner and recovery procedure.

Share with Codex only:

- Team ID.
- Exact codesigning identity string.
- Certificate expiration date.
- Confirmation that the seven named secrets can be provisioned.
- Error messages with account names, certificate bytes, and identifiers
  redacted as appropriate.

Never share the `.p12`, its password, `.p8`, Apple Account credential, 2FA
code, or base64-encoded key material in chat.

## Security and legal cautions

- Apple API keys and Developer ID private keys authorize production actions.
- A `.p8` file can be downloaded only once; make a protected recovery copy
  immediately.
- Do not email private keys or keep them in Downloads.
- Do not place credentials in `.env`, shell history, issue text, build
  settings, workflow YAML, or the repository.
- Use a dedicated release key rather than an unrelated all-purpose API key.
- Revoke a key immediately if its custody is uncertain.
- Renewal or certificate rotation is a release event and must be tested before
  the old identity expires.
- The human Account Holder remains responsible for the Apple agreements and
  the accuracy of the chosen legal identity.

## What Codex can do afterward

After the protected GitHub secrets exist, Codex can:

1. Validate the secret names without reading their values.
2. Run a protected signing workflow after human approval.
3. Verify the app's Team ID, Developer ID chain, Hardened Runtime, nested
   signatures, architecture, and entitlements.
4. Submit the signed app and DMG to notarization through the existing scripts.
5. Capture non-secret submission IDs and notarization results.
6. Diagnose signing or notarization failures without exposing credentials.

Codex cannot accept renewed agreements, perform 2FA, choose a legal entity, or
approve a production release.

## Official references

- [Apple Developer Program enrollment](https://developer.apple.com/help/account/membership/program-enrollment)
- [Create Developer ID certificates](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/)
- [App Store Connect API access and keys](https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-api)
- [Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- [Customizing the notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)
- [Developer ID overview](https://developer.apple.com/developer-id/)
