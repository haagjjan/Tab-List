import OSLog

enum TabListLog {
    static let subsystem = "com.haagjjan.TabList"

    static let application = Logger(
        subsystem: subsystem,
        category: "application"
    )
    static let permissions = Logger(
        subsystem: subsystem,
        category: "permissions"
    )
    static let registry = Logger(
        subsystem: subsystem,
        category: "window-registry"
    )
    static let input = Logger(
        subsystem: subsystem,
        category: "shortcut-input"
    )
    static let windowActions = Logger(
        subsystem: subsystem,
        category: "window-actions"
    )
    static let updates = Logger(
        subsystem: subsystem,
        category: "updates"
    )
    static let compatibility = Logger(
        subsystem: subsystem,
        category: "windowserver-compatibility"
    )
}
