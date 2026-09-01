import AppKit
import SwiftUI
import TabListCore

private enum SettingsSection: String, CaseIterable, Identifiable {
    case appearance
    case controls
    case filtering
    case exceptions
    case general
    case about

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .appearance: "Appearance"
        case .controls: "Controls"
        case .filtering: "Filtering"
        case .exceptions: "Exceptions"
        case .general: "General"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .appearance: "paintpalette"
        case .controls: "command"
        case .filtering: "line.3.horizontal.decrease.circle"
        case .exceptions: "hand.raised"
        case .general: "gearshape"
        case .about: "info.circle"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsViewModel
    @State private var selectedSection: SettingsSection? = .appearance

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $selectedSection) { section in
                Label(section.title, systemImage: section.symbol)
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 175, ideal: 195, max: 230)
        } detail: {
            Group {
                switch selectedSection ?? .appearance {
                case .appearance:
                    AppearanceSettingsView(model: model)
                case .controls:
                    ControlsSettingsView(model: model)
                case .filtering:
                    FilteringSettingsView(model: model)
                case .exceptions:
                    ExceptionsSettingsView(model: model)
                case .general:
                    GeneralSettingsView(model: model)
                case .about:
                    AboutSettingsView()
                }
            }
            .navigationTitle((selectedSection ?? .appearance).title)
            .frame(minWidth: 610, minHeight: 520)
        }
        .frame(width: 840, height: 590)
        .accessibilityIdentifier("settings.root")
    }
}

private struct AppearanceSettingsView: View {
    @ObservedObject var model: SettingsViewModel

    var body: some View {
        Form {
            Section("Theme") {
                Picker("Appearance", selection: model.binding(\.theme)) {
                    Text("Match system").tag(ThemePreference.system)
                    Text("Light").tag(ThemePreference.light)
                    Text("Dark").tag(ThemePreference.dark)
                }
                .accessibilityIdentifier("settings.theme")
            }

            Section("Preview") {
                ListPreview()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }

            Section {
                Label(
                    "Tab‑List shows one row per window: application, window title, and state.",
                    systemImage: "list.bullet"
                )
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct ListPreview: View {
    private static let rows: [(application: String, title: String, state: String?)] = [
        ("Firefox", "Release notes — Mozilla", nil),
        ("Xcode", "TabList.xcodeproj", nil),
        ("Notes", "Weekly plan", "Minimized"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Self.rows.indices, id: \.self) { index in
                let row = Self.rows[index]
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.primary.opacity(0.18))
                        .frame(width: 22, height: 22)
                    Text(row.application)
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 78, alignment: .leading)
                    Text(row.title)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if let state = row.state {
                        Text(state)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            index == 0
                                ? Color.accentColor.opacity(0.25)
                                : Color.clear
                        )
                        .padding(.horizontal, 4)
                )
            }
        }
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.primary.opacity(0.05))
        )
        .accessibilityHidden(true)
    }
}

private struct ControlsSettingsView: View {
    @ObservedObject var model: SettingsViewModel

    var body: some View {
        Form {
            Section("Window switcher") {
                LabeledContent("Shortcut") {
                    HStack {
                        ShortcutKeycaps(shortcut: model.settings.shortcut)
                        ShortcutRecorderView(
                            shortcut: model.settings.shortcut,
                            restingLabel: String(localized: "Change…")
                        ) {
                            model.updateShortcut($0)
                        }
                        Button("Reset") {
                            model.updateShortcut(.commandTab)
                        }
                    }
                }

                if let message = model.shortcutValidationMessage {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }

            Section("While switching") {
                keyboardRow(
                    keyLabel: "⇥",
                    action: "Move forward",
                    accessibilityDescription: "Tab, Move forward"
                )
                LabeledContent("Move backward") {
                    Picker(
                        "Move backward",
                        selection: reverseControlSelection
                    ) {
                        Text("Shift + Tab").tag(ReverseControlChoice.shiftTab)
                        Text("Shift only").tag(ReverseControlChoice.shiftOnly)
                        Text("Custom key").tag(ReverseControlChoice.customKey)
                    }
                    .labelsHidden()
                    .frame(width: 170)
                }
                if case let .key(keyCode) = model.settings.reverseControl {
                    LabeledContent("Custom reverse key") {
                        ShortcutRecorderView(
                            shortcut: ShortcutDefinition(
                                keyCode: keyCode,
                                modifiers: []
                            )
                        ) { definition in
                            if let keyCode = definition.keyCode {
                                model.updateReverseControl(.key(keyCode))
                            }
                        }
                        .frame(width: 120)
                    }
                }
                if let message = model.reverseControlValidationMessage {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                keyboardRow(
                    keyLabel: reverseKeyLabel,
                    action: "Move backward",
                    accessibilityDescription: "Configured reverse control, Move backward"
                )
                keyboardRow(
                    keyLabel: "⎋",
                    action: "Cancel",
                    accessibilityDescription: "Escape, Cancel"
                )
                keyboardRow(
                    keyLabel: "⌫",
                    action: "Close selected window",
                    accessibilityDescription: "Delete, Close selected window"
                )
                keyboardRow(
                    keyLabel: "Release modifier",
                    action: "Activate selected window",
                    accessibilityDescription:
                        "Release modifier, Activate selected window"
                )

                LabeledContent("Hold-to-cycle speed") {
                    HStack {
                        Slider(
                            value: model.binding(\.holdCycleSpeed),
                            in: 0.5 ... 2.0,
                            step: 0.1
                        )
                        .frame(width: 190)
                        Text(model.settings.holdCycleSpeed, format: .number.precision(.fractionLength(1)))
                            .monospacedDigit()
                        Text("×")
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private enum ReverseControlChoice: Hashable {
        case shiftTab
        case shiftOnly
        case customKey
    }

    private var reverseControlSelection: Binding<ReverseControlChoice> {
        Binding(
            get: {
                switch model.settings.reverseControl {
                case .shiftWithForwardKey: .shiftTab
                case .shiftOnly: .shiftOnly
                case .key: .customKey
                }
            },
            set: { choice in
                switch choice {
                case .shiftTab:
                    model.updateReverseControl(.shiftWithForwardKey)
                case .shiftOnly:
                    model.updateReverseControl(.shiftOnly)
                case .customKey:
                    model.updateReverseControl(.key(15))
                }
            }
        )
    }

    private var reverseKeyLabel: LocalizedStringKey {
        switch model.settings.reverseControl {
        case .shiftWithForwardKey: "⇧ + ⇥"
        case .shiftOnly: "⇧"
        case .key: "Custom key"
        }
    }

    private func keyboardRow(
        keyLabel: LocalizedStringKey,
        action: LocalizedStringKey,
        accessibilityDescription: LocalizedStringKey
    ) -> some View {
        LabeledContent {
            Text(action).foregroundStyle(.secondary)
        } label: {
            Text(keyLabel)
                .font(.system(.body, design: .monospaced, weight: .semibold))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityDescription))
    }
}

private struct ShortcutKeycaps: View {
    let shortcut: ShortcutDefinition

    var body: some View {
        HStack(spacing: 5) {
            ForEach(labels.indices, id: \.self) { index in
                if index > 0 {
                    Text("+").foregroundStyle(.secondary)
                }
                Text(labels[index])
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .padding(.horizontal, 8)
                    .frame(minHeight: 27)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(.separator, lineWidth: 1)
                    }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ShortcutRecorderView.displayString(shortcut))
    }

    private var labels: [String] {
        var result: [String] = []
        if shortcut.modifiers.contains(.control) { result.append("⌃") }
        if shortcut.modifiers.contains(.option) { result.append("⌥") }
        if shortcut.modifiers.contains(.command) { result.append("⌘") }
        let full = ShortcutRecorderView.displayString(shortcut)
        let modifiers = result.joined()
        result.append(String(full.dropFirst(modifiers.count)))
        return result
    }
}

private struct FilteringSettingsView: View {
    @ObservedObject var model: SettingsViewModel
    @State private var showsAdvanced = false

    var body: some View {
        Form {
            Section("Scope") {
                Picker("Show windows from", selection: scopePreset) {
                    Text("Everywhere").tag(ScopePreset.everywhere)
                    Text("Visible now").tag(ScopePreset.visibleNow)
                    Text("Pointer display").tag(ScopePreset.pointerDisplay)
                    if currentScopePreset == .custom {
                        Text("Custom").tag(ScopePreset.custom)
                    }
                }
                Text("macOS calls virtual desktops “Spaces.” Everywhere includes every desktop and display.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let warning = model.compatibilityWarning {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                DisclosureGroup("Advanced", isExpanded: $showsAdvanced) {
                    Picker("Desktops", selection: model.binding(\.spaceScope)) {
                        Text("Every desktop").tag(SpaceScope.allSpaces)
                        Text("Desktops visible now").tag(SpaceScope.visibleSpaces)
                    }
                    Picker("Displays", selection: model.binding(\.screenScope)) {
                        Text("Every display").tag(ScreenScope.allScreens)
                        Text("Display containing pointer").tag(ScreenScope.pointerScreen)
                    }
                }
            }

            Section("Window states") {
                Toggle("Show minimized windows", isOn: model.binding(\.includeMinimized))
                Toggle("Show windows from hidden apps", isOn: model.binding(\.includeHiddenApps))
                Toggle("Show fullscreen windows", isOn: model.binding(\.includeFullscreen))
            }

            Section {
                Label(
                    "Windows are always ordered by most recent focus.",
                    systemImage: "clock.arrow.circlepath"
                )
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var currentScopePreset: ScopePreset {
        ScopePreset(
            spaceScope: model.settings.spaceScope,
            screenScope: model.settings.screenScope
        )
    }

    private var scopePreset: Binding<ScopePreset> {
        Binding(
            get: { currentScopePreset },
            set: { preset in
                guard let scopes = preset.scopes else { return }
                model.updateScope(space: scopes.space, screen: scopes.screen)
            }
        )
    }
}

private struct ExceptionsSettingsView: View {
    @ObservedObject var model: SettingsViewModel
    @State private var showingRunningApps = false

    var body: some View {
        Form {
            Section {
                if model.excludedApplications.isEmpty {
                    ContentUnavailableView(
                        "No excluded applications",
                        systemImage: "hand.raised.slash",
                        description: Text("All eligible application windows can appear in Tab‑List.")
                    )
                    .frame(minHeight: 220)
                } else {
                    ForEach(model.excludedApplications) { app in
                        HStack(spacing: 12) {
                            Image(nsImage: app.icon)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 30, height: 30)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(app.localizedName)
                                Text(app.bundleIdentifier)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let bundleURL = app.bundleURL {
                                    Text(bundleURL.path)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        .help(bundleURL.path)
                                }
                            }
                            Spacer()
                            Button {
                                model.removeException(app.bundleIdentifier)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                            }
                            .buttonStyle(.plain)
                            .help("Remove exception")
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Excluded applications")
                    Spacer()
                    Menu {
                        ForEach(model.runningApplicationsAvailableForExclusion(), id: \.processIdentifier) { application in
                            let applicationName = application.localizedName
                                ?? application.bundleIdentifier
                                ?? String(
                                    localized:
                                        "settings.exceptions.fallback-application",
                                    defaultValue: "Application",
                                    comment:
                                        "Fallback name for an application whose name and bundle identifier are unavailable."
                                )
                            Button {
                                model.addRunningApplication(application)
                            } label: {
                                Text(verbatim: applicationName)
                            }
                        }
                        Divider()
                        Button("Choose Application…") {
                            model.addApplicationFromPicker()
                        }
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                    .menuStyle(.borderlessButton)
                }
            } footer: {
                Text("Every window belonging to an excluded application is hidden from the switcher.")
            }
        }
        .formStyle(.grouped)
    }
}

private struct GeneralSettingsView: View {
    @ObservedObject var model: SettingsViewModel
    @State private var isShowingResetConfirmation = false

    var body: some View {
        Form {
            if let warning = model.compatibilityWarning {
                Section {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }

            Section("Startup") {
                Toggle(
                    "Launch at login",
                    isOn: Binding(
                        get: { model.launchAtLoginEnabled },
                        set: { model.setLaunchAtLogin($0) }
                    )
                )
                if model.launchAtLoginRequiresApproval {
                    Text("macOS requires approval in System Settings → General → Login Items.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Toggle("Show menu-bar icon", isOn: model.binding(\.showMenuBarIcon))
            }

            Section("Updates") {
                Toggle(
                    "Automatically check for updates",
                    isOn: model.binding(\.automaticallyChecksForUpdates)
                )
                Button("Check for Updates…") {
                    model.onCheckForUpdates?()
                }
            }

            Section("Permissions") {
                statusRow("Accessibility", granted: model.accessibilityGranted)
#if DEBUG
                if !model.accessibilityGranted {
                    Text("Debug build: if macOS still shows Tab‑List as enabled, quit Tab‑List, run Scripts/reset_debug_accessibility.sh, relaunch, and grant Accessibility again.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
#endif
                HStack {
                    Button("Open Permissions…") { model.onOpenPermissions?() }
                    if !model.accessibilityGranted {
                        Button("Request Accessibility") { model.onRequestAccessibility?() }
                    }
                }
            }

            Section("Support") {
                Button("Export Redacted Diagnostics…") {
                    model.onExportDiagnostics?()
                }
                Button(
                    String(
                        localized: "settings.reset.button",
                        defaultValue: "Reset Preferences…",
                        comment:
                            "Button that opens confirmation before resetting preferences."
                    ),
                    role: .destructive
                ) {
                    isShowingResetConfirmation = true
                }
                .accessibilityIdentifier("settings.reset-preferences")
            }
        }
        .formStyle(.grouped)
        .alert(
            String(
                localized: "settings.reset.confirmation.title",
                defaultValue: "Reset Tab‑List preferences?",
                comment: "Title of the preference-reset confirmation alert."
            ),
            isPresented: $isShowingResetConfirmation
        ) {
            Button(
                String(
                    localized: "settings.reset.confirmation.action",
                    defaultValue: "Reset Preferences",
                    comment:
                        "Destructive action that confirms preference reset."
                ),
                role: .destructive
            ) {
                model.resetPreferences()
            }
            .accessibilityIdentifier("settings.confirm-reset-preferences")
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                String(
                    localized: "settings.reset.confirmation.message",
                    defaultValue:
                        "This restores all preferences stored by Tab‑List, including theme, shortcut, filters, exceptions, update checks, and the menu-bar icon. Launch at Login and macOS permissions are not changed.",
                    comment:
                        "Explains the exact scope of resetting preferences."
                )
            )
        }
    }

    private func statusRow(
        _ title: LocalizedStringKey,
        granted: Bool
    ) -> some View {
        let status = granted
            ? String(
                localized: "settings.permissions.status.granted",
                defaultValue: "Granted",
                comment: "Permission status when access has been granted."
            )
            : String(
                localized: "settings.permissions.status.not-granted",
                defaultValue: "Not granted",
                comment: "Permission status when access has not been granted."
            )
        return LabeledContent {
            Label {
                Text(verbatim: status)
            } icon: {
                Image(
                    systemName: granted
                        ? "checkmark.circle.fill"
                        : "exclamationmark.circle"
                )
            }
            .foregroundStyle(granted ? .green : .orange)
        } label: {
            Text(title)
        }
    }
}

private struct AboutSettingsView: View {
    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "rectangle.3.group")
                .font(.system(size: 64, weight: .medium))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("Tab‑List").font(.largeTitle.bold())
            Text(versionText)
                .foregroundStyle(.secondary)
            Text("Switch between individual macOS windows with a fast, native interface.")
                .multilineTextAlignment(.center)
                .frame(maxWidth: 390)
            Link("View on GitHub", destination: URL(string: "https://github.com/haagjjan/Tab-List")!)
            Text("Open source under the MIT License. Inspired by the window-switching concept popularized by AltTab; no AltTab code or assets are included.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 430)
            Text("No analytics. No window content is ever captured.")
                .font(.callout.weight(.medium))
            Spacer()
        }
        .padding(40)
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        let format = String(
            localized: "settings.about.version-format",
            defaultValue: "Version %1$@ (%2$@)",
            comment:
                "Application version and build. First value is version; second is build."
        )
        return String(
            format: format,
            locale: .current,
            version,
            build
        )
    }
}
