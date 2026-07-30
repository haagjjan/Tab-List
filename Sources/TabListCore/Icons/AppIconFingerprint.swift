import CryptoKit
import Foundation

public enum AppIconFingerprint {
    public static func make(
        bundleIdentifier: String?,
        canonicalBundlePath: String?,
        bundleVersion: String?,
        modificationTime: TimeInterval?,
        targetSize: Double
    ) -> String {
        let parts: [String] = [
            bundleIdentifier ?? "",
            canonicalBundlePath ?? "",
            bundleVersion ?? "unknown",
            modificationTime.map { String($0) } ?? "",
            String(format: "%.0f", targetSize),
        ]
        let components = parts.joined(separator: "\u{1F}")

        return SHA256.hash(data: Data(components.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
