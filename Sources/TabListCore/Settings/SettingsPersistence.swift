import Foundation

public enum SettingsPersistenceError: Error, Equatable, Sendable {
    case unsupportedSchemaVersion(Int)
    case malformedPayload
}

public struct PersistedSettingsEnvelope: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 2

    public let schemaVersion: Int
    public let settings: SettingsV1

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        settings: SettingsV1
    ) {
        self.schemaVersion = schemaVersion
        self.settings = settings
    }
}

public enum SettingsDecodeSource: Equatable, Sendable {
    case versioned(schemaVersion: Int)
    case legacyUnversioned
}

public struct DecodedSettings: Equatable, Sendable {
    public let settings: SettingsV1
    public let source: SettingsDecodeSource

    public init(settings: SettingsV1, source: SettingsDecodeSource) {
        self.settings = settings
        self.source = source
    }
}

/// Codable helpers shared by a `UserDefaults`-backed app store and tests.
public enum SettingsPersistence {
    public static func encode(
        _ settings: SettingsV1,
        encoder: JSONEncoder = JSONEncoder()
    ) throws -> Data {
        try encoder.encode(
            PersistedSettingsEnvelope(settings: settings.normalized())
        )
    }

    public static func decode(
        _ data: Data,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> DecodedSettings {
        if let envelope = try? decoder.decode(PersistedSettingsEnvelope.self, from: data) {
            guard (1 ... PersistedSettingsEnvelope.currentSchemaVersion)
                .contains(envelope.schemaVersion) else {
                throw SettingsPersistenceError.unsupportedSchemaVersion(envelope.schemaVersion)
            }
            return DecodedSettings(
                settings: envelope.settings.normalized(),
                source: .versioned(schemaVersion: envelope.schemaVersion)
            )
        }

        // Early development builds stored SettingsV1 directly. Supporting this
        // shape makes the first public schema migration deterministic.
        if let legacy = try? decoder.decode(SettingsV1.self, from: data) {
            return DecodedSettings(
                settings: legacy.normalized(),
                source: .legacyUnversioned
            )
        }

        throw SettingsPersistenceError.malformedPayload
    }
}
