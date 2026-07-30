import AppKit
import SwiftUI
import TabListCore

struct ExcludedApplication: Identifiable, Hashable {
    let bundleIdentifier: String
    let localizedName: String
    let bundleURL: URL?
    let icon: NSImage

    var id: String { bundleIdentifier }
}

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published private(set) var settings: SettingsV1
    @Published var accessibilityGranted = false
    @Published var screenRecordingGranted = false
    @Published var launchAtLoginEnabled = false
    @Published var launchAtLoginRequiresApproval = false
    @Published var excludedApplications: [ExcludedApplication] = []
    @Published var shortcutValidationMessage: String?
    @Published var compatibilityWarning: String?

    var onSettingsChanged: ((SettingsV1) -> Void)?
    var onShortcutChanged: ((ShortcutDefinition) async -> Bool)?
    var onLaunchAtLoginChanged: ((Bool) async -> Bool)?
    var onRequestAccessibility: (() -> Void)?
    var onRequestScreenRecording: (() -> Void)?
    var onOpenPermissions: (() -> Void)?
    var onCheckForUpdates: (() -> Void)?
    var onExportDiagnostics: (() -> Void)?

    init(settings: SettingsV1) {
        self.settings = settings.normalized()
        refreshExcludedApplications()
    }

    func binding<Value: Sendable>(
        _ keyPath: WritableKeyPath<SettingsV1, Value>
    ) -> Binding<Value> {
        Binding(
            get: { self.settings[keyPath: keyPath] },
            set: { value in
                var next = self.settings
                next[keyPath: keyPath] = value
                self.apply(next)
            }
        )
    }

    func updateShortcut(_ shortcut: ShortcutDefinition) {
        var shortcut = shortcut
        // Shift always means reverse cycling and is not persisted as part of
        // the base trigger.
        shortcut.modifiers.remove(.shift)
        let validation = ShortcutValidator.validate(shortcut)
        guard validation.isValid else {
            shortcutValidationMessage = Self.message(for: validation)
            return
        }

        Task {
            let accepted = await onShortcutChanged?(shortcut) ?? true
            if accepted {
                shortcutValidationMessage = nil
                var next = settings
                next.shortcut = shortcut
                apply(next)
            } else {
                shortcutValidationMessage = String(localized: "That shortcut is already used by macOS or another application.")
            }
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        Task {
            let accepted = await onLaunchAtLoginChanged?(enabled) ?? false
            launchAtLoginEnabled = accepted ? enabled : !enabled
        }
    }

    func addApplicationFromPicker() {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Choose an application to exclude")
        panel.prompt = String(localized: "Exclude")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK else { return }
        var next = settings
        for url in panel.urls {
            if let identifier = Bundle(url: url)?.bundleIdentifier {
                next.excludedBundleIdentifiers.insert(identifier)
            }
        }
        apply(next)
        refreshExcludedApplications()
    }

    func addRunningApplication(_ application: NSRunningApplication) {
        guard let identifier = application.bundleIdentifier else { return }
        var next = settings
        next.excludedBundleIdentifiers.insert(identifier)
        apply(next)
        refreshExcludedApplications()
    }

    func removeException(_ bundleIdentifier: String) {
        var next = settings
        next.excludedBundleIdentifiers.remove(bundleIdentifier)
        apply(next)
        refreshExcludedApplications()
    }

    func runningApplicationsAvailableForExclusion() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter {
                $0.activationPolicy == .regular &&
                $0.bundleIdentifier != Bundle.main.bundleIdentifier &&
                $0.bundleIdentifier.map { !settings.excludedBundleIdentifiers.contains($0) } == true
            }
            .sorted {
                ($0.localizedName ?? "").localizedCaseInsensitiveCompare($1.localizedName ?? "") == .orderedAscending
            }
    }

    func resetToDefaults() {
        apply(.default)
        refreshExcludedApplications()
    }

    func replaceSettingsWithoutNotification(_ value: SettingsV1) {
        settings = value.normalized()
        refreshExcludedApplications()
    }

    private func apply(_ value: SettingsV1) {
        let normalized = value.normalized()
        settings = normalized
        onSettingsChanged?(normalized)
    }

    private func refreshExcludedApplications() {
        excludedApplications = settings.excludedBundleIdentifiers.sorted().map { identifier in
            let running = NSRunningApplication.runningApplications(withBundleIdentifier: identifier).first
            let bundleURL = running?.bundleURL ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier)
            let name = running?.localizedName
                ?? bundleURL.flatMap { Bundle(url: $0)?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String }
                ?? bundleURL?.deletingPathExtension().lastPathComponent
                ?? identifier
            let icon = running?.icon
                ?? bundleURL.map { NSWorkspace.shared.icon(forFile: $0.path) }
                ?? NSImage(systemSymbolName: "app", accessibilityDescription: nil)
                ?? NSImage()
            return ExcludedApplication(
                bundleIdentifier: identifier,
                localizedName: name,
                bundleURL: bundleURL,
                icon: icon
            )
        }
    }

    private static func message(for result: ShortcutValidationResult) -> String? {
        guard case let .invalid(issue) = result else { return nil }
        switch issue {
        case .missingKey:
            return String(localized: "Choose a non-modifier key.")
        case .reservedActionKey:
            return String(
                localized:
                    "Escape and Delete are reserved for switcher actions."
            )
        case .missingModifier:
            return String(localized: "Include Command, Option, or Control.")
        case .shiftOnlyModifier:
            return String(localized: "Shift is reserved for reverse cycling; include another modifier.")
        case .unsupportedModifiers:
            return String(localized: "This modifier combination is not supported.")
        case .conflictsWithExistingShortcut:
            return String(localized: "That shortcut is already in use.")
        }
    }
}
