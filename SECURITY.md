# Security Policy

## Supported versions

Security fixes are provided for the latest public release. During pre-1.0 development, fixes may be available only on `main` or in the newest pre-release.

## Report a vulnerability

Do not open a public issue for a vulnerability involving window content, permission misuse, shortcut interception, update signatures, private API boundaries, code signing, or release credentials.

Use GitHub’s private vulnerability reporting:

<https://github.com/haagjjan/Tab-List/security/advisories/new>

Include:

- The affected Tab-List version and macOS version/build.
- Reproduction steps and expected security boundary.
- Whether Accessibility or Screen Recording was granted.
- The smallest sanitized proof of concept.
- Any evidence of network transmission, persistence, privilege escalation, signature failure, or unintended window control.

Never include real credentials or unredacted private window content. If a screenshot is essential, reproduce the issue with synthetic fixture data.

You should receive an acknowledgement within seven days. Please allow time for triage, a private fix, notarized release preparation, and coordinated disclosure.

## Security invariants

- Window screenshots do not intentionally leave memory or cross the network.
- Window titles are private in normal logs.
- Release artifacts require Developer ID signing, Hardened Runtime, notarization, and Sparkle EdDSA verification.
- Release secrets stay in protected CI secret storage and are never printed.
- Unsupported WindowServer symbols are dynamically resolved and capability checked; absence or failure must degrade behavior rather than crash.
- Accessibility work is bounded and isolated so an unresponsive application cannot block the event-tap callback or main actor.
- The event-tap callback performs no AppKit, Accessibility, WindowServer, network, or heavy allocation work.

Pull requests that weaken these invariants must include an explicit threat analysis and maintainer approval.
