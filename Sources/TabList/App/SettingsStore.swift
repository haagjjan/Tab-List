import Foundation
import TabListCore

@MainActor
final class SettingsStore {
    private enum Key {
        static let payload = "settings.payload"
        static let completedOnboarding = "onboarding.completed"
    }

    private let defaults: UserDefaults
    private(set) var settings: TabListSettings

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if
            let data = defaults.data(forKey: Key.payload),
            let decoded = try? SettingsPersistence.decode(data)
        {
            settings = decoded.settings
            if decoded.source != .versioned(
                schemaVersion: PersistedSettingsEnvelope.currentSchemaVersion
            ) {
                try? Self.persist(decoded.settings, to: defaults)
            }
        } else {
            settings = .default
        }
    }

    var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: Key.completedOnboarding) }
        set { defaults.set(newValue, forKey: Key.completedOnboarding) }
    }

    func update(_ settings: TabListSettings) {
        let normalized = settings.normalized()
        self.settings = normalized
        try? Self.persist(normalized, to: defaults)
    }

    func reset() {
        update(.default)
    }

    private static func persist(
        _ settings: TabListSettings,
        to defaults: UserDefaults
    ) throws {
        defaults.set(try SettingsPersistence.encode(settings), forKey: Key.payload)
    }
}
