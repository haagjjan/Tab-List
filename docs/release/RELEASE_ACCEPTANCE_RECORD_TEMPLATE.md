# Tab-List Release Acceptance Record

Copy this template for each candidate. Do not record secrets or unredacted
window titles.

## Candidate identity

- Version:
- Build number:
- Tag:
- Source commit:
- Candidate workflow URL:
- Draft release URL:
- Reviewer:
- Review date:
- Pre-release: yes / no

## Automated evidence

- [ ] macOS 15 Apple Silicon job passed
- [ ] macOS 26 Apple Silicon job passed
- [ ] `release-manifest.json` result is `passed`
- [ ] Application notarization status is `Accepted`
- [ ] DMG notarization status is `Accepted`
- [ ] ZIP Sparkle EdDSA signature passed
- [ ] Application and DMG stapling passed
- [ ] Application and DMG Gatekeeper assessment passed
- [ ] All candidate checksums passed
- [ ] Exported, ZIP, and DMG application CDHashes match
- [ ] All Mach-O files are arm64-only

## Manual compatibility evidence

- macOS 15 machine/build:
- macOS 26 machine/build:
- Hardware:
- Display and Space configuration:
- Accessibility permission states tested:
- Detected capability mask:
- Operational capability mask:
- Degraded-scope behavior validated:
- Fixture/application matrix result:
- Firefox, Chrome, Safari, Finder, Electron discovery result:
- Redacted diagnostics attached:

## Performance evidence

- Cached panel P95:
- Selection movement:
- 100-window discovery:
- Current-Space activation:
- Cross-Space activation:
- Five-minute idle CPU:
- 100-window resident memory:

## Clean installation and update

- [ ] Clean-Mac DMG installation passed
- [ ] Fresh Gatekeeper launch passed
- [ ] Accessibility onboarding passed
- [ ] Switcher populated immediately after the Accessibility grant
- [ ] Update from previous signed beta/release to the exact candidate ZIP passed
- [ ] Temporary Sparkle feed override and staging objects were removed
- [ ] Production feed URL was restored and rechecked
- Previous version/build tested:
- Update result:

## Promotion decision

- [ ] No draft asset was edited after candidate verification
- [ ] Version, tag, source commit, and pre-release state are correct
- [ ] Privacy, license, and third-party notices are present
- [ ] Known issues are documented and acceptable
- Decision: approve / reject
- Decision rationale:
- Promotion workflow URL:
- Published release URL:
