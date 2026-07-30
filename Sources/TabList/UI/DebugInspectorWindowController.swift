#if DEBUG
import AppKit
import SwiftUI
import TabListCore

@MainActor
private final class DebugInspectorModel: ObservableObject {
    @Published var generation: UInt64 = 0
    @Published var visibleSpaceIDs: [UInt64] = []
    @Published var windows: [WindowRecord] = []
    @Published var detectedCapabilities = WindowServerCapabilities()
    @Published var operationalCapabilities = WindowServerCapabilities()
    @Published var frameworkPath = "Unavailable"
    @Published var isRefreshing = false

    func apply(
        snapshot: WindowSnapshot,
        report: WindowServerCapabilityReport
    ) {
        generation = snapshot.generation
        visibleSpaceIDs = snapshot.visibleSpaceIDs.sorted()
        windows = snapshot.windows
        detectedCapabilities = report.detected
        operationalCapabilities = report.operational
        frameworkPath = report.frameworkPath ?? "Unavailable"
        isRefreshing = false
    }
}

@MainActor
final class DebugInspectorWindowController {
    private let model = DebugInspectorModel()
    private lazy var window: NSWindow = {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1_020, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Tab‑List Window Inspector"
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(
            rootView: DebugInspectorView(
                model: model,
                onRefresh: { [weak self] in
                    self?.refresh()
                }
            )
        )
        window.center()
        return window
    }()

    private weak var registry: WindowRegistry?
    private weak var windowServer: WindowServerBridge?
    private var refreshTask: Task<Void, Never>?

    func show(
        registry: WindowRegistry,
        windowServer: WindowServerBridge
    ) {
        self.registry = registry
        self.windowServer = windowServer
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        refresh()
    }

    private func refresh() {
        guard let registry, let windowServer else { return }
        refreshTask?.cancel()
        model.isRefreshing = true
        refreshTask = Task { [weak model] in
            let snapshot = await registry.snapshot(
                forceRefreshIfStale: true
            )
            guard !Task.isCancelled else { return }
            model?.apply(
                snapshot: snapshot,
                report: windowServer.capabilityReport
            )
        }
    }
}

private struct DebugInspectorView: View {
    @ObservedObject var model: DebugInspectorModel
    let onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(verbatim: "Registry generation \(model.generation)")
                    .font(.headline)
                Text(
                    verbatim: "\(model.windows.count) eligible windows"
                )
                .foregroundStyle(.secondary)
                Spacer()
                Button(
                    action: onRefresh,
                    label: {
                        if model.isRefreshing {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text(verbatim: "Refresh")
                        }
                    }
                )
                .disabled(model.isRefreshing)
            }

            GroupBox {
                Grid(
                    alignment: .leading,
                    horizontalSpacing: 16,
                    verticalSpacing: 6
                ) {
                    capabilityRow(
                        label: "Detected",
                        capabilities: model.detectedCapabilities
                    )
                    capabilityRow(
                        label: "Operational",
                        capabilities: model.operationalCapabilities
                    )
                    GridRow {
                        Text(verbatim: "Framework")
                            .foregroundStyle(.secondary)
                        Text(verbatim: model.frameworkPath)
                            .textSelection(.enabled)
                    }
                    GridRow {
                        Text(verbatim: "Visible Spaces")
                            .foregroundStyle(.secondary)
                        Text(
                            verbatim: model.visibleSpaceIDs.isEmpty
                                ? "Unknown"
                                : model.visibleSpaceIDs
                                    .map(String.init)
                                    .joined(separator: ", ")
                        )
                        .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Table(model.windows) {
                TableColumn("PID / Window") { window in
                    Text(
                        verbatim: "\(window.id.pid) / \(window.id.windowID)"
                    )
                    .font(.system(.body, design: .monospaced))
                }
                .width(min: 125, ideal: 145)

                TableColumn("Application") { window in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: window.applicationName)
                        Text(
                            verbatim: window.bundleIdentifier ?? "No bundle ID"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                .width(min: 150, ideal: 210)

                TableColumn("Title") { window in
                    Text(
                        verbatim: window.windowTitle.isEmpty
                            ? "Untitled"
                            : window.windowTitle
                    )
                    .lineLimit(2)
                    .help(window.windowTitle)
                }
                .width(min: 180, ideal: 300)

                TableColumn("State") { window in
                    Text(verbatim: stateSummary(window))
                        .font(.caption)
                }
                .width(min: 120, ideal: 155)

                TableColumn("Space / Display") { window in
                    Text(verbatim: locationSummary(window))
                        .font(.system(.caption, design: .monospaced))
                }
                .width(min: 130, ideal: 170)

                TableColumn("MRU") { window in
                    Text(verbatim: String(window.lastFocusSequence))
                        .font(.system(.body, design: .monospaced))
                }
                .width(min: 55, ideal: 70)
            }
        }
        .padding(16)
        .frame(minWidth: 780, minHeight: 460)
    }

    @ViewBuilder
    private func capabilityRow(
        label: String,
        capabilities: WindowServerCapabilities
    ) -> some View {
        GridRow {
            Text(verbatim: label)
                .foregroundStyle(.secondary)
            Text(verbatim: capabilityNames(capabilities))
                .textSelection(.enabled)
        }
    }

    private func capabilityNames(
        _ capabilities: WindowServerCapabilities
    ) -> String {
        let known: [(WindowServerCapabilities, String)] = [
            (.mainConnection, "main-connection"),
            (.spaceInventory, "space-inventory"),
            (.windowSpaceQuery, "window-space-query"),
            (.notifications, "notifications"),
            (.exactActivation, "exact-activation"),
            (.hardwareCapture, "hardware-capture"),
            (.accessibilityWindowID, "AX-window-ID"),
            (.remoteAccessibilityElement, "remote-AX"),
        ]
        let names = known.compactMap { capability, name in
            capabilities.contains(capability) ? name : nil
        }
        return names.isEmpty ? "None" : names.joined(separator: ", ")
    }

    private func stateSummary(_ window: WindowRecord) -> String {
        var states: [String] = []
        if window.isMinimized { states.append("minimized") }
        if window.isHidden { states.append("hidden") }
        if window.isFullscreen { states.append("fullscreen") }
        if !window.isStandardWindow { states.append("nonstandard") }
        if !window.isClosable { states.append("not closable") }
        return states.isEmpty ? "standard" : states.joined(separator: ", ")
    }

    private func locationSummary(_ window: WindowRecord) -> String {
        let spaces = window.spaceIDs.isEmpty
            ? "unknown"
            : window.spaceIDs.map(String.init).joined(separator: ",")
        let display = window.displayID.map(String.init) ?? "unknown"
        return "S:\(spaces)  D:\(display)"
    }
}
#endif
