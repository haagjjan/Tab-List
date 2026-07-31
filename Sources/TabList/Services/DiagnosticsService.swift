import CoreGraphics
import Foundation
import TabListCore

public struct RedactedWindowDiagnostic: Codable, Sendable {
    public let processID: pid_t
    public let windowID: CGWindowID
    public let bundleIdentifierHash: String?
    public let hasTitle: Bool
    public let isMinimized: Bool
    public let isHidden: Bool
    public let isFullscreen: Bool
    public let isStandardWindow: Bool
    public let isClosable: Bool
    public let identitySource: WindowIdentitySource
    public let identityConfidence: WindowIdentityConfidence
    public let isActionable: Bool
    public let spaceCount: Int
    public let displayID: CGDirectDisplayID?
}

public struct DiagnosticsReport: Codable, Sendable {
    public let generatedAt: Date
    public let appVersion: String
    public let appBuild: String
    public let operatingSystem: String
    public let architecture: String
    public let permissions: SystemPermissionSnapshot
    public let windowServerCapabilities: WindowServerCapabilityReport
    public let registryGeneration: UInt64
    public let visibleSpaceCount: Int
    public let windows: [RedactedWindowDiagnostic]
}

/// Creates an explicitly requested, JSON diagnostics file. Window titles are
/// never serialized and bundle identifiers are one-way hashed.
public enum DiagnosticsService {
    public static func makeReport(
        permissions: SystemPermissionSnapshot,
        capabilities: WindowServerCapabilityReport,
        snapshot: WindowSnapshot,
        bundle: Bundle = .main
    ) -> DiagnosticsReport {
        let exportSalt = UUID().uuidString
        return DiagnosticsReport(
            generatedAt: Date(),
            appVersion: bundle.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String ?? "unknown",
            appBuild: bundle.object(
                forInfoDictionaryKey: "CFBundleVersion"
            ) as? String ?? "unknown",
            operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
            architecture: architectureName(),
            permissions: permissions,
            windowServerCapabilities: capabilities,
            registryGeneration: snapshot.generation,
            visibleSpaceCount: snapshot.visibleSpaceIDs.count,
            windows: snapshot.windows.map {
                redactedWindow($0, exportSalt: exportSalt)
            }
        )
    }

    public static func encoded(_ report: DiagnosticsReport) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(report)
    }

    public static func export(
        _ report: DiagnosticsReport,
        to destination: URL
    ) async throws {
        let data = try encoded(report)
        try await Task.detached(priority: .utility) {
            try data.write(to: destination, options: [.atomic, .completeFileProtection])
        }.value
    }

    private static func redactedWindow(
        _ window: WindowRecord,
        exportSalt: String
    ) -> RedactedWindowDiagnostic {
        RedactedWindowDiagnostic(
            processID: window.id.pid,
            windowID: window.id.windowID,
            bundleIdentifierHash: window.bundleIdentifier.map {
                PrivacyRedaction.bundleIdentifier(
                    $0,
                    exportSalt: exportSalt
                )
            },
            hasTitle: !window.windowTitle.isEmpty,
            isMinimized: window.isMinimized,
            isHidden: window.isHidden,
            isFullscreen: window.isFullscreen,
            isStandardWindow: window.isStandardWindow,
            isClosable: window.isClosable,
            identitySource: window.identitySource,
            identityConfidence: window.identitySource.confidence,
            isActionable: window.isActionable,
            spaceCount: window.spaceIDs.count,
            displayID: window.displayID
        )
    }

    private static func architectureName() -> String {
#if arch(arm64)
        "arm64"
#elseif arch(x86_64)
        "x86_64"
#else
        "unknown"
#endif
    }
}
