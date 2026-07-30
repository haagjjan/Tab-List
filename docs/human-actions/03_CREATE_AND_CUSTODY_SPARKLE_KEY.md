# Human Action 03 — Create and Safeguard the Sparkle Signing Key

## Purpose

Create the Ed25519 key pair that authenticates Tab-List update archives through
Sparkle 2.9.4, preserve a recoverable private-key backup, and authorize the
protected release workflow to sign updates.

This key is independent of the Apple Developer ID identity. Both signatures are
required for the planned release process.

## Why this needs a human

Codex can execute Sparkle's tooling, but the application owner must authorize
creation of a long-lived production signing root, choose its custody and backup
locations, and decide who receives CI access. Losing or leaking this key affects
every installed copy of Tab-List.

## Prerequisites

- [Full Xcode and project bootstrap](01_INSTALL_FULL_XCODE.md).
- Swift package dependencies resolved with `Scripts/bootstrap.sh`.
- Access to the Sparkle 2.9.4 `generate_keys` binary in DerivedData.
- A protected Mac login keychain.
- Two secure recovery locations, at least one offline or independently
  encrypted.
- The GitHub `release` environment may be configured afterward.

## Human action

### A. Locate the pinned Sparkle tool

From the repository root:

```sh
find build/DerivedData/SourcePackages \
  -type f \
  -path '*/Sparkle/bin/generate_keys' \
  -perm -111 \
  -print -quit
```

If no path is returned, stop and ask Codex to run `Scripts/bootstrap.sh`. Do not
download a different Sparkle binary just to generate the production key.

### B. Generate the key once

1. Run the discovered `generate_keys` binary without arguments.
2. Review its output.
3. Confirm that Sparkle stored the private key in the current login keychain.
4. Record the printed public key. The public key is safe to share; the private
   key is not.
5. Do not run key generation again in another keychain after the production key
   has been selected.

Sparkle documents `-x` for exporting and `-f` for importing a private key.
Check the pinned tool's `--help` output before exporting:

```sh
"/exact/path/to/generate_keys" --help
```

### C. Export and protect a recovery copy

1. Create a private directory outside the repository:

   ```sh
   umask 077
   mkdir -p "/secure/location/TabList-Release-Keys"
   ```

2. Export the selected key with the pinned tool:

   ```sh
   "/exact/path/to/generate_keys" \
     -x "/secure/location/TabList-Release-Keys/sparkle-private-key"
   chmod 600 \
     "/secure/location/TabList-Release-Keys/sparkle-private-key"
   ```

3. Make an encrypted offline backup.
4. Keep a second protected recovery copy under a different failure domain.
5. Record which trusted person can recover or revoke access.

### D. Verify public/private correspondence

The repository includes a verifier that derives the public key from the
exported private-key file:

```sh
Scripts/sparkle_public_key.swift \
  "/secure/location/TabList-Release-Keys/sparkle-private-key"
```

The output must exactly match the public key printed by `generate_keys`.
Mismatch means stop; do not create release secrets from that file.

### E. Prepare the two GitHub secrets

The workflow expects:

- `SPARKLE_PUBLIC_ED_KEY`: the public key text.
- `SPARKLE_PRIVATE_ED_KEY_BASE64`: base64 encoding of the **exported file
  bytes**.

The exported Sparkle file can itself contain base64 text. The workflow value is
therefore intentionally an encoding of the complete file bytes, not simply the
text displayed by Sparkle.

When GitHub authentication and the protected environment are ready, pipe the
values directly rather than printing them:

```sh
Scripts/sparkle_public_key.swift \
  "/secure/location/TabList-Release-Keys/sparkle-private-key" |
  gh secret set SPARKLE_PUBLIC_ED_KEY --env release

base64 < \
  "/secure/location/TabList-Release-Keys/sparkle-private-key" |
  tr -d '\n' |
  gh secret set SPARKLE_PRIVATE_ED_KEY_BASE64 --env release
```

Run those commands only after verifying that `gh auth status` names the correct
GitHub account and repository access.

## Evidence to retain

Retain privately:

- The protected keychain entry.
- Two recovery locations.
- Export date and custodian.
- A key-rotation and compromise contact.

Share with Codex:

- The public EdDSA key.
- Confirmation that the derived public key matched.
- Confirmation that both GitHub secret names exist.
- A pass/fail result from a disposable Sparkle sign/verify test.

Do not share the exported key file, its contents, its base64 encoding, backup
passwords, or screenshots of the keychain.

## Security cautions

- Never commit the private key, even to a private branch.
- Never put private-key text in a command argument, issue, workflow, build
  setting, paste service, chat, or release notes.
- Avoid clipboard handling; direct pipes are safer.
- Do not leave an export under the repository, Downloads, `/tmp`, or an
  unencrypted cloud folder.
- Restrict GitHub secret access with the protected `release` environment.
- Rotate only when necessary. Sparkle's supported trust transition generally
  must not change the Apple signing identity and Sparkle EdDSA key in the same
  update.
- If the key is lost or exposed, stop releases and follow Sparkle's documented
  key-rotation path before publishing another update.

## What Codex can do afterward

Codex can:

1. Confirm the public key is embedded as `SUPublicEDKey`.
2. Verify that the protected workflow derives the same public key.
3. Generate a signed appcast from a disposable archive.
4. Verify the EdDSA signature with Sparkle's `sign_update`.
5. Test that no private-key content appears in logs or artifacts.
6. Implement and test a key-rotation runbook if rotation becomes necessary.

Codex should operate on file paths and protected secret references, not display
private-key content.

## Official references

- [Sparkle basic setup and EdDSA keys](https://sparkle-project.org/documentation/)
- [Publishing an update](https://sparkle-project.org/documentation/publishing/)
- [Sparkle security and reliability updates](https://sparkle-project.org/documentation/security-and-reliability/)
- [Migrating and rotating EdDSA trust](https://sparkle-project.org/documentation/eddsa-migration/)
