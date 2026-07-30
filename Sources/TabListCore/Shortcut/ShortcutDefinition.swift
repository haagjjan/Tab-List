import Foundation

/// Platform-independent representation of the modifiers accepted by the global
/// shortcut service.
public struct ShortcutModifiers: OptionSet, Hashable, Codable, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let command = ShortcutModifiers(rawValue: 1 << 0)
    public static let option = ShortcutModifiers(rawValue: 1 << 1)
    public static let control = ShortcutModifiers(rawValue: 1 << 2)
    public static let shift = ShortcutModifiers(rawValue: 1 << 3)

    public static let supported: ShortcutModifiers = [.command, .option, .control, .shift]
    public static let nonShift: ShortcutModifiers = [.command, .option, .control]
}

/// A keyboard shortcut expressed using the macOS virtual key code.
///
/// `keyCode == nil` represents an incomplete modifier-only recording and is
/// retained so the recorder can validate it without manufacturing a key.
public struct ShortcutDefinition: Hashable, Codable, Sendable {
    public var keyCode: UInt16?
    public var modifiers: ShortcutModifiers

    public init(keyCode: UInt16?, modifiers: ShortcutModifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// ANSI Tab key with Command.
    public static let commandTab = ShortcutDefinition(
        keyCode: 48,
        modifiers: .command
    )
}

public enum ShortcutValidationIssue: Error, Equatable, Sendable {
    case missingKey
    case reservedActionKey
    case missingModifier
    case shiftOnlyModifier
    case unsupportedModifiers
    case conflictsWithExistingShortcut
}

public enum ShortcutValidationResult: Equatable, Sendable {
    case valid
    case invalid(ShortcutValidationIssue)

    public var isValid: Bool {
        self == .valid
    }
}

/// Pure shortcut validation. Registration conflicts discovered by Carbon can be
/// folded into this result using `registrationConflict`.
public enum ShortcutValidator {
    /// Escape cancels an active switcher; Delete and Forward Delete close its
    /// selected window. They cannot also be the session's cycling key.
    private static let reservedActionKeyCodes: Set<UInt16> = [
        53, // Escape
        51, // Delete / Backspace
        117, // Forward Delete
    ]

    public static func validate(
        _ shortcut: ShortcutDefinition,
        against existingShortcuts: Set<ShortcutDefinition> = [],
        registrationConflict: Bool = false
    ) -> ShortcutValidationResult {
        guard let keyCode = shortcut.keyCode else {
            return .invalid(.missingKey)
        }

        guard !reservedActionKeyCodes.contains(keyCode) else {
            return .invalid(.reservedActionKey)
        }

        guard shortcut.modifiers.isSubset(of: .supported) else {
            return .invalid(.unsupportedModifiers)
        }

        guard !shortcut.modifiers.isEmpty else {
            return .invalid(.missingModifier)
        }

        guard !shortcut.modifiers.intersection(.nonShift).isEmpty else {
            return .invalid(.shiftOnlyModifier)
        }

        let conflictsWithKnownShortcut = existingShortcuts.contains { existing in
            existing.keyCode == shortcut.keyCode
                && existing.modifiers.intersection(.nonShift)
                    == shortcut.modifiers.intersection(.nonShift)
        }
        guard !conflictsWithKnownShortcut, !registrationConflict else {
            return .invalid(.conflictsWithExistingShortcut)
        }

        return .valid
    }
}
