# Human Action 04 — Initialize and Secure the GitHub Repository

## Purpose

Publish the completed local history to the existing GitHub repository, enable
hosted CI, create protected candidate and promotion environments, provision the
nine release secrets, and activate the repository security settings referenced
by the project documentation.

At the time of this runbook's creation:

- `origin` is `https://github.com/haagjjan/Tab-List.git`.
- The GitHub repository is public and empty.
- GitHub CLI is installed locally but not authenticated.

## Why this needs a human

GitHub authentication, initial publication, repository visibility, branch
protection, release approval, secret insertion, and security settings are
external mutations. They require the repository owner or an authorized
administrator. Codex must not infer permission to publish code or upload
production credentials.

## Prerequisites

- The intended source changes are complete and reviewed.
- The working tree is clean and the owner has approved the commit to publish.
- A GitHub account with administrator access to `haagjjan/Tab-List`.
- [Apple release values](02_APPLE_DEVELOPER_AND_NOTARIZATION.md).
- [Sparkle release values](03_CREATE_AND_CUSTODY_SPARKLE_KEY.md).
- Two-factor authentication and a trusted GitHub session.

The repository must remain public for the planned unauthenticated GitHub
Release downloads and Sparkle feed. If the owner chooses private visibility,
stop and redesign update hosting before any release.

## Human action

### A. Authenticate and verify the destination

1. Authenticate GitHub CLI:

   ```sh
   gh auth login
   ```

2. Select `github.com`, HTTPS or SSH according to the owner's normal policy,
   and a secure browser/device login.
3. Verify the authenticated identity:

   ```sh
   gh auth status
   gh repo view haagjjan/Tab-List
   git remote -v
   ```

4. Confirm that the repository owner, name, visibility, and remote URL are
   correct before pushing.

### B. Publish the reviewed branch

1. Verify the exact commit:

   ```sh
   git status --short --branch
   git log -1 --show-signature --oneline
   ```

2. The working tree must be clean. If it is not, stop and return to Codex.
3. Push `main` only after reviewing the complete initial commit:

   ```sh
   git push -u origin main
   ```

4. In GitHub settings, confirm that `main` is the default branch.
5. Confirm that the push triggered `.github/workflows/ci.yml`.
6. Require both macOS 15 and macOS 26 CI jobs to pass before treating the
   repository as initialized.

### C. Configure Actions and branch protection

1. Under **Settings → Actions → General**, allow the pinned actions used by the
   repository.
2. Ensure the release workflow can request `contents: write` through its
   job-level `permissions` declaration.
3. Do not grant broader organization or pull-request write access.
4. Add a branch protection rule or ruleset for `main`:
   - Require a pull request for future non-emergency changes.
   - Require the macOS 15 and macOS 26 CI status checks.
   - Require branches to be up to date before merging.
   - Prevent force-push and branch deletion.
   - Retain an explicit, audited emergency path for the repository owner.
5. Enable Dependabot alerts and the checked-in Dependabot configuration.

### D. Create the protected release environments

1. Under **Settings → Environments**, create an environment named exactly:

   ```text
   release
   ```

2. Require a maintainer's approval before the release job can access secrets.
3. Restrict deployment branches and tags to the intended release sources:
   `main` and reviewed `v*.*.*` tags.
4. If there is only one maintainer, do not enable “prevent self-review” until a
   second trusted reviewer exists; otherwise no one can approve a release.
5. Set a reasonable approval timeout and document the reviewer.
6. Create a second environment named exactly:

   ```text
   release-promotion
   ```

7. Require a deliberate maintainer approval for `release-promotion`. When
   practical, use a reviewer other than the person who initiated the candidate
   workflow.
8. Do not add Apple, Developer ID, notarization, or Sparkle secrets to
   `release-promotion`. It uses only GitHub’s short-lived repository token to
   revalidate and publish an existing draft.

### E. Add environment secrets

Create these secrets under the `release` environment, not in workflow YAML:

```text
APPLE_DEVELOPER_ID_P12_BASE64
APPLE_DEVELOPER_ID_P12_PASSWORD
APPLE_DEVELOPMENT_TEAM
APPLE_CODESIGN_IDENTITY
APPLE_NOTARY_KEY_P8_BASE64
APPLE_NOTARY_KEY_ID
APPLE_NOTARY_ISSUER_ID
SPARKLE_PUBLIC_ED_KEY
SPARKLE_PRIVATE_ED_KEY_BASE64
```

Use GitHub's web secret form or `gh secret set --env release`. Pipe file bytes
directly. Do not put a value on the command line or in a tracked intermediary
file.

GitHub displays only secret names after creation. That is the correct evidence;
do not attempt to read values back.

### F. Enable repository security features

1. Enable private vulnerability reporting so the URL in `SECURITY.md` works:

   ```text
   https://github.com/haagjjan/Tab-List/security/advisories/new
   ```

2. Enable secret scanning and push protection if available for the account.
3. Verify that Issues are enabled and the checked-in issue forms render.
4. Confirm that release creation is limited to maintainers.

## No GitHub App is needed

Do **not** create:

- A GitHub App.
- An OAuth app.
- A long-lived personal access token for the release workflow.
- A deploy key with write access.

The workflow uses GitHub Actions' short-lived, repository-scoped
`GITHUB_TOKEN`. The release job requests only `contents: write`.

## Evidence to retain

Share with Codex:

- URL and commit SHA of remote `main`.
- CI run URL and status for both operating-system jobs.
- Confirmation that `main` is default and protected.
- Confirmation that the `release` and `release-promotion` environments exist.
- The nine secret **names only**.
- Confirmation that required review and deployment restrictions are active.
- Confirmation that private vulnerability reporting works.

Do not share secret values, authentication tokens, browser session data,
private keys, recovery codes, or screenshots that expose them.

## Security cautions

- An initial push makes all committed history public.
- Review the complete history and run secret scanning before publishing.
- Verify `gh auth status` before every secret or release command.
- Environment secrets must not be copied into repository-level variables.
- Anyone who can modify a release workflow can try to exfiltrate secrets.
  Protect workflow changes and inspect them before approval.
- Never approve a release deployment from an unfamiliar commit.
- Do not make the repository private without replacing the public Sparkle
  hosting design.

## What Codex can do afterward

After authentication and repository authorization, Codex can:

1. Inspect CI failures and repair the source or workflows.
2. Verify action pins, job permissions, and deterministic project generation.
3. Confirm that the workflow references only the expected secret names.
4. Prepare release tags and metadata for human approval.
5. Monitor candidate and promotion workflows and analyze non-secret logs.
6. Verify the draft and published artifact sets and appcast URLs.

Codex still requires explicit authorization before pushing, changing repository
settings, approving a protected environment, or publishing a release.

## Official references

- [Authenticating to GitHub](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/about-authentication-to-github)
- [Pushing commits to a remote repository](https://docs.github.com/en/get-started/using-git/pushing-commits-to-a-remote-repository)
- [Managing deployment environments](https://docs.github.com/en/actions/how-tos/deploy/configure-and-manage-deployments/manage-environments)
- [Using secrets in GitHub Actions](https://docs.github.com/en/actions/security-for-github-actions/security-guides/using-secrets-in-github-actions)
- [Managing protected branches](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches)
- [Configuring private vulnerability reporting](https://docs.github.com/en/code-security/security-advisories/working-with-repository-security-advisories/configuring-private-vulnerability-reporting-for-a-repository)
