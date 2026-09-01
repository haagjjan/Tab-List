import Foundation

public enum SettingsPersistenceError: Error, Equatable, Sendable {
    case unsupportedSchemaVersion(Int)
    case malformedPayload
}

public struct PersistedSettingsEnvelope: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 3

    public let schemaVersion: Int
    public let settings: TabListSettings

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        settings: TabListSettings
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
    public let settings: TabListSettings
    public let source: SettingsDecodeSource

    public init(settings: TabListSettings, source: SettingsDecodeSource) {
        self.settings = settings
        self.source = source
    }
}

/// Codable helpers shared by the `UserDefaults`-backed store and tests.
///
/// Schema versions 1 and 2 carried retired presentation preferences. Those
/// keys are simply absent from the current payload, so an older envelope
/// decodes into current defaults and is rewritten at the new version.
public enum SettingsPersistence {
    public static func encode(
        _ settings: TabListSettings,
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
        if let envelope = try? decoder.decode(
            PersistedSettingsEnvelope.self,
            from: data
        ) {
            guard (1 ... PersistedSettingsEnvelope.currentSchemaVersion)
                .contains(envelope.schemaVersion) else {
                throw SettingsPersistenceError.unsupportedSchemaVersion(
                    envelope.schemaVersion
                )
            }
            return DecodedSettings(
                settings: envelope.settings.normalized(),
                source: .versioned(schemaVersion: envelope.schemaVersion)
            )
        }

        if let legacy = try? decoder.decode(TabListSettings.self, from: data) {
            return DecodedSettings(
                settings: legacy.normalized(),
                source: .legacyUnversioned
            )
        }

        throw SettingsPersistenceError.malformedPayload
    }
}
