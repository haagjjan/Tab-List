import TabListCore

/// Pure commit rule for settings whose shortcut registration is an external,
/// fallible side effect. Unrelated requested preferences still commit when a
/// shortcut replacement fails.
enum SettingsTransaction {
    static func committed(
        previous: TabListSettings,
        requested: TabListSettings,
        shortcutRegistrationRequired: Bool,
        shortcutRegistrationSucceeded: Bool
    ) -> TabListSettings {
        guard shortcutRegistrationRequired,
              !shortcutRegistrationSucceeded else {
            return requested
        }
        var committed = requested
        committed.shortcut = previous.shortcut
        return committed
    }
}
