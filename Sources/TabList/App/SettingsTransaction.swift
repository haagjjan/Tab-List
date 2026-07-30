import TabListCore

/// Pure commit rule for settings whose shortcut registration is an external,
/// fallible side effect. Unrelated requested preferences still commit when a
/// shortcut replacement fails.
enum SettingsTransaction {
    static func committed(
        previous: SettingsV1,
        requested: SettingsV1,
        shortcutRegistrationRequired: Bool,
        shortcutRegistrationSucceeded: Bool
    ) -> SettingsV1 {
        guard shortcutRegistrationRequired,
              !shortcutRegistrationSucceeded else {
            return requested
        }
        var committed = requested
        committed.shortcut = previous.shortcut
        return committed
    }
}
