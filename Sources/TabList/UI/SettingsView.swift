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
            Section {
                Picker("Presentation", selection: model.binding(\.presentation)) {
                    Label("Thumbnails", systemImage: "rectangle.on.rectangle.angled").tag(TabListCore.PresentationMode.thumbnails)
                    Label("App Icons", systemImage: "app.dashed").tag(TabListCore.PresentationMode.appIcons)
                    Label("Titles", systemImage: "list.bullet.rectangle").tag(TabListCore.PresentationMode.titles)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("settings.presentation")

                resourceDisclosure
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Preview") {
                AppearancePreview(
                    presentation: model.settings.presentation,
                    panelSize: model.settings.panelSize,
                    theme: model.settings.theme,
                    opacity: model.settings.opacity
                )
                .frame(height: 190)
            }

            Section("Panel") {
                Picker("Size", selection: model.binding(\.panelSize)) {
                    Text("Small").tag(PanelSize.small)
                    Text("Medium").tag(PanelSize.medium)
                    Text("Large").tag(PanelSize.large)
                    Text("Auto").tag(PanelSize.auto)
                }
                Picker("Theme", selection: model.binding(\.theme)) {
                    Text("System").tag(ThemePreference.system)
                    Text("Light").tag(ThemePreference.light)
                    Text("Dark").tag(ThemePreference.dark)
                }
                HStack {
                    Text("Opacity")
                    Slider(value: model.binding(\.opacity), in: 0.70...1.0, step: 0.01)
                    Text(model.settings.opacity, format: .percent.precision(.fractionLength(0)))
                        .monospacedDigit()
                        .frame(width: 42, alignment: .trailing)
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var resourceDisclosure: some View {
        switch model.settings.presentation {
        case .thumbnails:
            Label(
                "Uses Screen Recording and keeps a bounded in-memory preview cache.",
                systemImage: "memorychip"
            )
        case .appIcons:
            Label("Low resource use; app icons are cached.", systemImage: "leaf")
        case .titles:
            Label("Lowest resource use; no window content is captured.", systemImage: "leaf.fill")
        }
    }
}

private struct AppearancePreview: View {
    let presentation: TabListCore.PresentationMode
    let panelSize: PanelSize
    let theme: ThemePreference
    let opacity: Double

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.blue.opacity(0.45), .purple.opacity(0.40), .green.opacity(0.30)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            previewItems
            .padding(16)
            .frame(width: previewPanelWidth)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(radius: 10, y: 5)
            .padding(24)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private var previewItems: some View {
        if presentation == .titles {
            VStack(spacing: 7) {
                ForEach(0..<3, id: \.self) { index in
                    previewItem(index)
                }
            }
        } else {
            HStack(spacing: 10) {
                ForEach(0..<3, id: \.self) { index in
                    previewItem(index)
                }
            }
        }
    }

    @ViewBuilder
    private func previewItem(_ index: Int) -> some View {
        let symbols = ["safari", "folder", "doc.text"]
        let titles = [
            String(
                localized: "settings.preview.title.research",
                defaultValue: "Research",
                comment: "Sample window title in the appearance preview."
            ),
            String(
                localized: "settings.preview.title.projects",
                defaultValue: "Projects",
                comment: "Sample window title in the appearance preview."
            ),
            String(
                localized: "settings.preview.title.notes",
                defaultValue: "Notes",
                comment: "Sample window title in the appearance preview."
            ),
        ]
        let applicationNames = [
            String(
                localized: "settings.preview.application.safari",
                defaultValue: "Safari",
                comment: "Sample application name in the appearance preview."
            ),
            String(
                localized: "settings.preview.application.finder",
                defaultValue: "Finder",
                comment: "Sample application name in the appearance preview."
            ),
            String(
                localized: "settings.preview.application.textedit",
                defaultValue: "TextEdit",
                comment: "Sample application name in the appearance preview."
            ),
        ]
        switch presentation {
        case .thumbnails:
            VStack(alignment: .leading, spacing: 5) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.quaternary)
                    .overlay {
                        Image(systemName: symbols[index])
                            .font(.title)
                    }
                Text(verbatim: titles[index])
                    .font(.caption.bold())
                    .lineLimit(1)
            }
            .padding(6)
            .frame(width: previewTileWidth, height: 100)
            .background(index == 0 ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.04))
            .overlay {
                RoundedRectangle(cornerRadius: 9)
                    .stroke(index == 0 ? Color.accentColor : .clear, lineWidth: 2)
            }
        case .appIcons:
            VStack(spacing: 7) {
                Image(systemName: symbols[index]).font(.system(size: 34))
                Text(verbatim: titles[index])
                    .font(.caption.bold())
                    .lineLimit(1)
            }
            .frame(width: previewTileWidth, height: 90)
            .background(index == 0 ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 9))
        case .titles:
            HStack(spacing: 8) {
                Image(systemName: symbols[index])
                    .frame(width: 22)
                Text(verbatim: applicationNames[index])
                    .font(.caption.bold())
                    .frame(width: 70, alignment: .leading)
                Text(verbatim: titles[index])
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 9)
            .frame(width: previewPanelWidth - 32, height: 34)
            .background(index == 0 ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var background: some ShapeStyle {
        switch theme {
        case .system:
            AnyShapeStyle(.ultraThinMaterial.opacity(opacity))
        case .light:
            AnyShapeStyle(Color.white.opacity(opacity))
        case .dark:
            AnyShapeStyle(Color.black.opacity(opacity))
        }
    }

    private var previewPanelWidth: CGFloat {
        switch panelSize {
        case .small: 300
        case .medium: 370
        case .large: 440
        case .auto: 370
        }
    }

    private var previewTileWidth: CGFloat {
        switch panelSize {
        case .small: 82
        case .medium: 105
        case .large: 126
        case .auto: 105
        }
    }
}

private struct ControlsSettingsView: View {
    @ObservedObject var model: SettingsViewModel

    var body: some View {
        Form {
            Section("Window switcher") {
                LabeledContent("Shortcut") {
                    HStack {
                        ShortcutRecorderView(shortcut: model.settings.shortcut) {
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
                    keyLabel: Text(verbatim: "⇧"),
                    action: "Move backward"
                )
                keyboardRow(
                    keyLabel: Text(verbatim: "⎋"),
                    action: "Cancel"
                )
                keyboardRow(
                    keyLabel: Text(verbatim: "⌫"),
                    action: "Close selected window"
                )
                keyboardRow(
                    keyLabel: Text("Release modifier"),
                    action: "Activate selected window"
                )
            }
        }
        .formStyle(.grouped)
    }

    private func keyboardRow(
        keyLabel: Text,
        action: LocalizedStringKey
    ) -> some View {
        LabeledContent {
            Text(action).foregroundStyle(.secondary)
        } label: {
            keyLabel
                .font(.system(.body, design: .monospaced, weight: .semibold))
        }
    }
}

private struct FilteringSettingsView: View {
    @ObservedObject var model: SettingsViewModel

    var body: some View {
        Form {
            Section("Scope") {
                Picker("Spaces", selection: model.binding(\.spaceScope)) {
                    Text("All Spaces").tag(SpaceScope.allSpaces)
                    Text("Visible Spaces").tag(SpaceScope.visibleSpaces)
                }
                Picker("Screens", selection: model.binding(\.screenScope)) {
                    Text("All Screens").tag(ScreenScope.allScreens)
                    Text("Pointer Screen").tag(ScreenScope.pointerScreen)
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

            Section("Thumbnails") {
                Toggle(
                    "Refresh thumbnails in the background",
                    isOn: model.binding(\.refreshThumbnailsInBackground)
                )
                Text("Off is recommended for the lowest idle CPU use. Cached previews still appear immediately after they have been captured once.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                statusRow("Thumbnail previews", granted: model.screenRecordingGranted)
                HStack {
                    Button("Open Permissions…") { model.onOpenPermissions?() }
                    if !model.accessibilityGranted {
                        Button("Request Accessibility") { model.onRequestAccessibility?() }
                    }
                    if !model.screenRecordingGranted {
                        Button("Enable Thumbnails") { model.onRequestScreenRecording?() }
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
                        "This restores all preferences stored by Tab‑List, including appearance, shortcut, filters, exceptions, update checks, and the menu-bar icon. Launch at Login and macOS permissions are not changed.",
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
            Text("No analytics. No window screenshots on disk.")
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
