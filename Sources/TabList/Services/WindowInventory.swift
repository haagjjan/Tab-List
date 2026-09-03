@preconcurrency import AppKit
import CoreGraphics
import Foundation
import TabListCore

public struct WindowInventoryResult: Sendable {
    public let windows: [WindowRecord]
    public let visibleSpaceIDs: Set<UInt64>

    public init(windows: [WindowRecord], visibleSpaceIDs: Set<UInt64>) {
        self.windows = windows
        self.visibleSpaceIDs = visibleSpaceIDs
    }
}

public protocol WindowInventoryProviding: Sendable {
    func discover() async -> WindowInventoryResult
    func currentFocusedWindowKey() async -> WindowKey?
}

struct RunningApplicationDescriptor: Sendable {
    let pid: pid_t
    let bundleIdentifier: String?
    let name: String
    let bundleURL: URL?
    let isHidden: Bool
    let activationPolicy: WindowOwnerActivationPolicy
}

/// Front-to-back process order taken from the public on-screen window list.
///
/// `AXWindows` is already front-to-back inside one process, so pairing the two
/// gives a complete initial ordering without needing to match individual
/// windows to compositor surfaces.
enum ProcessStackingOrder {
    struct Surface: Equatable, Sendable {
        let pid: pid_t
        let layer: Int

        init(pid: pid_t, layer: Int) {
            self.pid = pid
            self.layer = layer
        }
    }

    /// Ranks each process by where its frontmost normal-layer surface appears.
    static func order(frontToBack surfaces: [Surface]) -> [pid_t: Int] {
        var order: [pid_t: Int] = [:]
        for surface in surfaces
        where surface.layer == 0 && surface.pid > 0 && order[surface.pid] == nil {
            order[surface.pid] = order.count
        }
        return order
    }

    static func current() -> [pid_t: Int] {
        guard let info = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return [:]
        }
        return order(
            frontToBack: info.compactMap { entry in
                guard let pid = (
                    entry[kCGWindowOwnerPID as String] as? NSNumber
                )?.int32Value else {
                    return nil
                }
                return Surface(
                    pid: pid,
                    layer: (entry[kCGWindowLayer as String] as? NSNumber)?
                        .intValue ?? -1
                )
            }
        )
    }
}

/// Turns one Accessibility window plus its owning process into a domain
/// record, or explains why it is not a switchable window.
///
/// Keeping this pure is what makes the rules that decide whether a window
/// appears in the list — the rules that previously hid entire applications —
/// directly testable.
enum WindowRecordAssembly {
    enum Outcome: Equatable {
        case included(WindowRecord)
        case excluded(WindowExclusionReason)

        var record: WindowRecord? {
            guard case let .included(record) = self else { return nil }
            return record
        }

        var exclusionReason: WindowExclusionReason? {
            guard case let .excluded(reason) = self else { return nil }
            return reason
        }
    }

    static func record(
        descriptor: AccessibilityWindowDescriptor,
        application: RunningApplicationDescriptor,
        ownPID: pid_t,
        spaceIDs: [UInt64],
        displayID: CGDirectDisplayID?
    ) -> Outcome {
        let classification = WindowClassifier.classify(
            WindowClassificationInput(
                ownerBundleIdentifier: application.bundleIdentifier,
                ownerName: application.name,
                ownerActivationPolicy: application.activationPolicy,
                bounds: descriptor.bounds,
                accessibilityRole: descriptor.role,
                accessibilitySubrole: descriptor.subrole,
                isOwnedByTabList: application.pid == ownPID
            )
        )
        if case let .excluded(reason) = classification {
            return .excluded(reason)
        }

        return .included(
            WindowRecord(
                id: descriptor.key,
                bundleIdentifier: application.bundleIdentifier,
                applicationName: application.name,
                bundleURL: application.bundleURL,
                windowTitle: descriptor.title,
                bounds: descriptor.bounds,
                spaceIDs: spaceIDs,
                displayID: displayID,
                isMinimized: descriptor.isMinimized,
                isHidden: application.isHidden,
                isFullscreen: descriptor.isFullscreen,
                isClosable: descriptor.isClosable,
                identitySource: descriptor.identitySource
            )
        )
    }
}

/// Display bounds captured once per discovery so that resolving the screen of
/// each window stays a pure computation.
struct DisplayGeometry: Sendable {
    private let displays: [(id: CGDirectDisplayID, bounds: CGRect)]

    init(displays: [(id: CGDirectDisplayID, bounds: CGRect)]) {
        self.displays = displays
    }

    static func current() -> Self {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0
        else {
            return Self(displays: [])
        }
        var identifiers = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(
            count,
            &identifiers,
            &count
        ) == .success else {
            return Self(displays: [])
        }
        return Self(
            displays: identifiers.prefix(Int(count)).map {
                ($0, CGDisplayBounds($0))
            }
        )
    }

    func displayID(containing bounds: CGRect) -> CGDirectDisplayID? {
        var bestID: CGDirectDisplayID?
        var bestArea: CGFloat = 0
        for display in displays {
            let intersection = display.bounds.intersection(bounds)
            guard !intersection.isNull else { continue }
            let area = max(0, intersection.width) * max(0, intersection.height)
            guard area > bestArea else { continue }
            bestArea = area
            bestID = display.id
        }
        return bestID
    }
}

/// Builds the canonical window list from Accessibility, which is the same
/// source used to activate and close windows. A window that appears here is
/// therefore always one Tab-List can act on.
public actor WindowInventory: WindowInventoryProviding {
    private let accessibility: AccessibilityBridge
    private let windowServer: WindowServerBridge
    private let ownPID: pid_t

    public init(
        accessibility: AccessibilityBridge,
        windowServer: WindowServerBridge,
        ownPID: pid_t = ProcessInfo.processInfo.processIdentifier
    ) {
        self.accessibility = accessibility
        self.windowServer = windowServer
        self.ownPID = ownPID
    }

    public func discover() async -> WindowInventoryResult {
        await windowServer.prepare()
        guard accessibility.isTrusted else {
            return WindowInventoryResult(windows: [], visibleSpaceIDs: [])
        }

        let applications = await runningApplications()
        guard !applications.isEmpty else {
            return WindowInventoryResult(windows: [], visibleSpaceIDs: [])
        }

        let inventory = await accessibility.windowInventory(
            for: Set(applications.map(\.pid))
        )
        let stacking = ProcessStackingOrder.current()
        let geometry = DisplayGeometry.current()
        let queriesSpaces = windowServer.capabilityReport.operational
            .contains(.windowSpaceQuery)

        let ordered = applications.sorted { lhs, rhs in
            let left = stacking[lhs.pid] ?? Int.max
            let right = stacking[rhs.pid] ?? Int.max
            if left != right { return left < right }
            return lhs.pid < rhs.pid
        }

        // Accessibility returns nothing at all for an application whose windows
        // all live on another Space, so the WindowServer supplies those.
        let crossSpaceWindows = Dictionary(
            grouping: windowServer.windowsAcrossSpaces(
                ownedBy: Set(applications.map(\.pid))
            ),
            by: \.pid
        )

        var records: [WindowRecord] = []
        for application in ordered {
            let descriptors = inventory
                .windowsByProcess[application.pid] ?? []
            for descriptor in descriptors {
                let spaceIDs = queriesSpaces
                    && descriptor.identitySource == .windowServerID
                    ? windowServer.spaceIDs(
                        forWindowID: descriptor.key.windowID
                    )
                    : []

                switch WindowRecordAssembly.record(
                    descriptor: descriptor,
                    application: application,
                    ownPID: ownPID,
                    spaceIDs: spaceIDs,
                    displayID: geometry.displayID(containing: descriptor.bounds)
                ) {
                case let .included(record):
                    records.append(record)
                case let .excluded(reason):
                    TabListLog.registry.debug(
                        "Excluded pid \(application.pid, privacy: .private(mask: .hash)) reason \(reason.diagnosticCode, privacy: .public)"
                    )
                }
            }

            for window in Self.windowsOnlyTheWindowServerSees(
                crossSpaceWindows[application.pid] ?? [],
                alreadyReportedBy: descriptors
            ) {
                switch WindowRecordAssembly.record(
                    descriptor: Self.descriptor(for: window),
                    application: application,
                    ownPID: ownPID,
                    spaceIDs: window.spaceIDs,
                    displayID: geometry.displayID(containing: window.bounds)
                ) {
                case let .included(record):
                    records.append(record)
                case let .excluded(reason):
                    TabListLog.registry.debug(
                        "Excluded cross-Space pid \(application.pid, privacy: .private(mask: .hash)) reason \(reason.diagnosticCode, privacy: .public)"
                    )
                }
            }
        }

        let visibleSpaceIDs = windowServer.visibleSpaceIDs()
        TabListLog.registry.debug(
            "Discovered \(records.count, privacy: .public) windows across \(visibleSpaceIDs.count, privacy: .public) visible Spaces"
        )
        return WindowInventoryResult(
            windows: records,
            visibleSpaceIDs: visibleSpaceIDs
        )
    }

    public func currentFocusedWindowKey() async -> WindowKey? {
        let frontmostPID = await MainActor.run {
            NSWorkspace.shared.frontmostApplication?.processIdentifier
        }
        guard let frontmostPID, frontmostPID != ownPID else { return nil }
        let focusedKey = await accessibility.focusedWindowKey(for: frontmostPID)
        let stillFrontmost = await MainActor.run {
            NSWorkspace.shared.frontmostApplication?
                .processIdentifier == frontmostPID
        }
        return stillFrontmost ? focusedKey : nil
    }

    /// The WindowServer windows for one process that Accessibility did not
    /// already report.
    ///
    /// Both sources key a window by its WindowServer identifier, so matching is
    /// exact whenever Accessibility resolved real identifiers. When it fell back
    /// to process-scoped ordinals the two cannot be matched at all, so a process
    /// that already reported windows is left alone rather than risking a
    /// duplicate row for every window it owns.
    static func windowsOnlyTheWindowServerSees(
        _ windows: [WindowServerWindow],
        alreadyReportedBy descriptors: [AccessibilityWindowDescriptor]
    ) -> [WindowServerWindow] {
        guard !windows.isEmpty else { return [] }
        guard descriptors.allSatisfy({
            $0.identitySource == .windowServerID
        }) else {
            return []
        }
        let claimed = Set(descriptors.map(\.key.windowID))
        return windows.filter { !claimed.contains($0.windowID) }
    }

    /// Presents a WindowServer window as an Accessibility descriptor so that one
    /// classification and assembly path serves both sources.
    ///
    /// Role and subrole are genuinely unknown here; `WindowClassifier` treats a
    /// missing role as acceptable rather than disqualifying, which is what lets
    /// these windows through. Minimized and fullscreen windows never reach this
    /// path — the WindowServer places them on no Space, so they are filtered out
    /// before this point and continue to come from Accessibility.
    static func descriptor(
        for window: WindowServerWindow
    ) -> AccessibilityWindowDescriptor {
        AccessibilityWindowDescriptor(
            key: WindowKey(pid: window.pid, windowID: window.windowID),
            role: nil,
            subrole: nil,
            title: window.title,
            bounds: window.bounds,
            isMinimized: false,
            isFullscreen: false,
            isClosable: true,
            isMain: false,
            identitySource: .windowServerID
        )
    }

    private func runningApplications() async -> [RunningApplicationDescriptor] {
        let ownPID = ownPID
        return await MainActor.run {
            NSWorkspace.shared.runningApplications.compactMap { application in
                guard application.activationPolicy == .regular,
                      !application.isTerminated,
                      application.processIdentifier > 0,
                      application.processIdentifier != ownPID else {
                    return nil
                }
                return RunningApplicationDescriptor(
                    pid: application.processIdentifier,
                    bundleIdentifier: application.bundleIdentifier,
                    name: application.localizedName ?? "",
                    bundleURL: application.bundleURL,
                    isHidden: application.isHidden,
                    activationPolicy: .regular
                )
            }
        }
    }
}
