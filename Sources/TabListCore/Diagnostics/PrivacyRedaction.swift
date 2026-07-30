import CryptoKit
import Foundation

/// Helpers for producing diagnostics without exposing window content or stable
/// application identifiers.
public enum PrivacyRedaction {
    public static let redactedWindowTitle = "<redacted>"

    public static func windowTitle(_ title: String) -> String {
        title.isEmpty ? "<empty>" : redactedWindowTitle
    }

    /// Produces a per-export pseudonym when supplied with a random export salt.
    /// Callers must not use a globally stable salt.
    public static func bundleIdentifier(
        _ bundleIdentifier: String?,
        exportSalt: String
    ) -> String {
        guard let bundleIdentifier, !bundleIdentifier.isEmpty else {
            return "<unknown>"
        }
        let digest = SHA256.hash(
            data: Data("\(exportSalt)\u{0}\(bundleIdentifier)".utf8)
        )
        return digest.prefix(12).map { String(format: "%02x", $0) }.joined()
    }
}
