@preconcurrency import AppKit
import CoreGraphics
import Foundation
import TabListCore

public struct PublicWindowCandidate: Equatable, Sendable {
    public let key: WindowKey
    public let ownerName: String
    public let title: String
    public let bounds: CGRect
    public let layer: Int
    public let alpha: Double
    public let isOnScreen: Bool

    public init(
        key: WindowKey,
        ownerName: String,
        title: String,
        bounds: CGRect,
        layer: Int,
        alpha: Double,
        isOnScreen: Bool
    ) {
        self.key = key
        self.ownerName = ownerName
        self.title = title
        self.bounds = bounds
        self.layer = layer
        self.alpha = alpha
        self.isOnScreen = isOnScreen
    }
}

public struct WindowInventoryResult: Sendable {
    public let windows: [WindowRecord]
    public let visibleSpaceIDs: Set<UInt64>
    public let visibleWindowKeys: Set<WindowKey>

    public init(
        windows: [WindowRecord],
        visibleSpaceIDs: Set<UInt64>,
        visibleWindowKeys: Set<WindowKey> = []
    ) {
        self.windows = windows
        self.visibleSpaceIDs = visibleSpaceIDs
        self.visibleWindowKeys = visibleWindowKeys
    }
}

public protocol WindowInventoryProviding: Sendable {
    func discover() async -> WindowInventoryResult
    func currentFocusedWindowKey() async -> WindowKey?
}

private struct ApplicationDescriptor: Sendable {
    let bundleIdentifier: String?
    let name: String
    let bundleURL: URL?
    let isHidden: Bool
}

/// Public, conservative inventory built from WindowServer metadata and enriched
/// with AX state. It remains useful when private APIs disappear.
public actor PublicWindowInventory: WindowInventoryProviding {
    /// Used only when the private Space API is unavailable. This sentinel lets
    /// "Visible Spaces" continue to mean "currently onscreen" in degraded mode.
    public static let publicVisibleSpaceSentinel: UInt64 = 0

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
        windowServer.performStartupSelfTest()
        guard let rawWindowInfo = CGWindowListCopyWindowInfo(
            [.optionAll, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            TabListLog.registry.error(
                "CGWindowListCopyWindowInfo returned no window inventory"
            )
            return WindowInventoryResult(
                windows: [],
                visibleSpaceIDs: [],
                visibleWindowKeys: []
            )
        }

        var candidates = rawWindowInfo.compactMap(parseCandidate)
        var pids = Set(candidates.map(\.key.pid))
        pids.formUnion(await regularApplicationProcessIDs())
        let applications = await applicationDescriptors(for: pids)

        let discoveredAccessibilityWindows = await accessibility
            .discoveredWindows(for: pids)
        let candidatesNeedingGeometryFallback = candidates.filter {
            discoveredAccessibilityWindows[$0.key] == nil
        }
        let fallbackAccessibilityMetadata = await accessibility.metadata(
            for: candidatesNeedingGeometryFallback
        )
        let accessibilityMetadata = discoveredAccessibilityWindows.merging(
            fallbackAccessibilityMetadata
        ) { discovered, _ in discovered }

        var knownCandidateKeys = Set(candidates.map(\.key))
        let accessibilityOnlyCandidates = discoveredAccessibilityWindows
            .sorted { lhs, rhs in
                if lhs.key.pid != rhs.key.pid {
                    return lhs.key.pid < rhs.key.pid
                }
                return lhs.key.windowID < rhs.key.windowID
            }
            .compactMap { key, metadata -> PublicWindowCandidate? in
                guard knownCandidateKeys.insert(key).inserted,
                      let bounds = metadata.bounds else {
                    return nil
                }
                return PublicWindowCandidate(
                    key: key,
                    ownerName: applications[key.pid]?.name ?? "",
                    title: metadata.title ?? "",
                    bounds: bounds,
                    layer: 0,
                    alpha: 1,
                    // AX-only records are deliberately seeded behind known
                    // WindowServer-visible records. Space membership below
                    // still makes them eligible for All Spaces.
                    isOnScreen: false
                )
            }
        candidates.append(contentsOf: accessibilityOnlyCandidates)

        let candidateByKey = candidates.reduce(
            into: [WindowKey: PublicWindowCandidate]()
        ) { result, candidate in
            result[candidate.key] = candidate
        }

        var records: [WindowRecord] = []
        records.reserveCapacity(candidates.count)
        var hasPubliclyVisibleWindow = false
        var visibleWindowKeys: Set<WindowKey> = []

        for candidate in candidates {
            let application = applications[candidate.key.pid]
            let metadata = accessibilityMetadata[candidate.key]
            let bundleIdentifier = application?.bundleIdentifier
            let ownerName = application?.name ?? candidate.ownerName
            let resolvedBounds = metadata?.bounds ?? candidate.bounds

            let classification = WindowClassifier.classify(
                WindowClassificationInput(
                    ownerBundleIdentifier: bundleIdentifier,
                    ownerName: ownerName,
                    bounds: resolvedBounds,
                    layer: candidate.layer,
                    alpha: candidate.alpha,
                    accessibilityRole: metadata?.role,
                    accessibilitySubrole: metadata?.subrole,
                    isOwnedByTabList: candidate.key.pid == ownPID,
                    isDesktopElement: false,
                    isNotification: isNotificationOwner(
                        bundleIdentifier: bundleIdentifier,
                        ownerName: ownerName
                    ),
                    isTabGroupChild: false,
                    isTransparentSurface: candidate.alpha <= 0.01
                )
            )
            guard classification.isEligible else { continue }
            if candidate.isOnScreen {
                visibleWindowKeys.insert(candidate.key)
            }

            let privateSpaces = windowServer.spaceIDs(
                forWindowID: candidate.key.windowID
            )
            let spaces: [UInt64]
            if !privateSpaces.isEmpty {
                spaces = privateSpaces
            } else if candidate.isOnScreen {
                spaces = [Self.publicVisibleSpaceSentinel]
                hasPubliclyVisibleWindow = true
            } else {
                spaces = []
            }

            records.append(
                WindowRecord(
                    id: candidate.key,
                    bundleIdentifier: bundleIdentifier,
                    applicationName: ownerName,
                    bundleURL: application?.bundleURL,
                    windowTitle: metadata?.title ?? candidate.title,
                    bounds: resolvedBounds,
                    spaceIDs: spaces,
                    displayID: displayID(containing: resolvedBounds),
                    isMinimized: metadata?.isMinimized ?? false,
                    isHidden: application?.isHidden ?? false,
                    isFullscreen: metadata?.isFullscreen ?? false,
                    isStandardWindow: true,
                    isClosable: metadata?.isClosable ?? false,
                    lastFocusSequence: 0
                )
            )
        }

        let privateVisibleSpaces = windowServer.visibleSpaceIDs()
        var visibleSpaces = privateVisibleSpaces
        if hasPubliclyVisibleWindow {
            visibleSpaces.insert(Self.publicVisibleSpaceSentinel)
        }
        let filteredRecords = Self.removingInactiveNativeTabMembers(
            from: records,
            candidates: candidateByKey
        )
        let retainedKeys = Set(filteredRecords.map(\.id))
        TabListLog.registry.debug(
            "Discovered \(filteredRecords.count, privacy: .public) eligible windows across \(visibleSpaces.count, privacy: .public) visible Spaces"
        )
        return WindowInventoryResult(
            windows: filteredRecords,
            visibleSpaceIDs: visibleSpaces,
            visibleWindowKeys: visibleWindowKeys.intersection(retainedKeys)
        )
    }

    /// Reads the currently focused window only when Accessibility is available.
    /// The registry de-duplicates this evidence so reconciliations do not
    /// artificially advance MRU.
    public func currentFocusedWindowKey() async -> WindowKey? {
        let frontmostPID = await MainActor.run {
            NSWorkspace.shared.frontmostApplication?.processIdentifier
        }
        guard let frontmostPID else { return nil }
        let focusedKey = await accessibility.focusedWindowKey(
            for: frontmostPID
        )
        let remainsFrontmost = await MainActor.run {
            NSWorkspace.shared.frontmostApplication?
                .processIdentifier == frontmostPID
        }
        return remainsFrontmost ? focusedKey : nil
    }

    private func parseCandidate(
        _ dictionary: [String: Any]
    ) -> PublicWindowCandidate? {
        guard
            let pidNumber = dictionary[kCGWindowOwnerPID as String] as? NSNumber,
            let windowNumber = dictionary[kCGWindowNumber as String] as? NSNumber,
            let boundsDictionary = dictionary[kCGWindowBounds as String]
                as? NSDictionary,
            let bounds = CGRect(
                dictionaryRepresentation: boundsDictionary as CFDictionary
            )
        else {
            return nil
        }

        let pid = pid_t(pidNumber.int32Value)
        let windowID = CGWindowID(windowNumber.uint32Value)
        guard pid > 0, windowID != 0 else { return nil }

        let ownerName = dictionary[kCGWindowOwnerName as String] as? String ?? ""
        let title = dictionary[kCGWindowName as String] as? String ?? ""
        let layer = (dictionary[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
        let alpha = (dictionary[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
        let isOnScreen =
            (dictionary[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue
            ?? false

        return PublicWindowCandidate(
            key: WindowKey(pid: pid, windowID: windowID),
            ownerName: ownerName,
            title: title,
            bounds: bounds,
            layer: layer,
            alpha: alpha,
            isOnScreen: isOnScreen
        )
    }

    private func applicationDescriptors(
        for pids: Set<pid_t>
    ) async -> [pid_t: ApplicationDescriptor] {
        await MainActor.run {
            var result: [pid_t: ApplicationDescriptor] = [:]
            result.reserveCapacity(pids.count)

            for pid in pids {
                guard let app = NSRunningApplication(processIdentifier: pid) else {
                    continue
                }
                result[pid] = ApplicationDescriptor(
                    bundleIdentifier: app.bundleIdentifier,
                    name: app.localizedName ?? "",
                    bundleURL: app.bundleURL,
                    isHidden: app.isHidden
                )
            }
            return result
        }
    }

    private func regularApplicationProcessIDs() async -> Set<pid_t> {
        await MainActor.run {
            Set(
                NSWorkspace.shared.runningApplications.compactMap {
                    application -> pid_t? in
                    guard application.activationPolicy == .regular,
                          !application.isTerminated,
                          application.processIdentifier != ownPID
                    else {
                        return nil
                    }
                    return application.processIdentifier
                }
            )
        }
    }

    private func displayID(containing bounds: CGRect) -> CGDirectDisplayID? {
        var displayIDs = Array(repeating: CGDirectDisplayID(0), count: 16)
        var count: UInt32 = 0
        let error = CGGetDisplaysWithRect(
            bounds,
            UInt32(displayIDs.count),
            &displayIDs,
            &count
        )
        guard error == .success, count > 0 else { return nil }

        return displayIDs
            .prefix(Int(count))
            .max { lhs, rhs in
                let leftArea = CGDisplayBounds(lhs)
                    .intersection(bounds)
                    .area
                let rightArea = CGDisplayBounds(rhs)
                    .intersection(bounds)
                    .area
                return leftArea < rightArea
            }
    }

    private func isNotificationOwner(
        bundleIdentifier: String?,
        ownerName: String
    ) -> Bool {
        let identifier = bundleIdentifier?.lowercased() ?? ""
        let name = ownerName.lowercased()
        return identifier.contains("notificationcenter")
            || name == "notification center"
            || identifier == "com.apple.controlcenter"
    }

    /// AppKit native tab members share process, geometry, and Space, while only
    /// the selected container has an onscreen WindowServer surface. Minimized
    /// windows are retained. This intentionally avoids title-based grouping.
    static func removingInactiveNativeTabMembers(
        from records: [WindowRecord],
        candidates: [WindowKey: PublicWindowCandidate]
    ) -> [WindowRecord] {
        struct TabSignature: Hashable {
            let pid: pid_t
            let x: Int
            let y: Int
            let width: Int
            let height: Int
            let spaces: [UInt64]
        }

        func signature(_ record: WindowRecord) -> TabSignature {
            TabSignature(
                pid: record.id.pid,
                x: Int(record.bounds.origin.x.rounded()),
                y: Int(record.bounds.origin.y.rounded()),
                width: Int(record.bounds.width.rounded()),
                height: Int(record.bounds.height.rounded()),
                spaces: record.spaceIDs.sorted()
            )
        }

        let grouped = Dictionary(grouping: records, by: signature)
        var inactiveKeys: Set<WindowKey> = []
        for group in grouped.values where group.count > 1 {
            // Unknown Space membership cannot prove a native tab relation.
            // Failing open preserves separate same-app windows on different
            // Spaces when the private Space query is unavailable.
            guard group.allSatisfy({ !$0.spaceIDs.isEmpty }) else {
                continue
            }
            let visible = group.filter {
                candidates[$0.id]?.isOnScreen == true && !$0.isMinimized
            }
            guard visible.count == 1 else { continue }
            for record in group where
                candidates[record.id]?.isOnScreen == false
                    && !record.isMinimized {
                inactiveKeys.insert(record.id)
            }
        }
        return records.filter { !inactiveKeys.contains($0.id) }
    }
}

private extension CGRect {
    var area: CGFloat {
        guard !isNull, !isInfinite else { return 0 }
        return max(0, width) * max(0, height)
    }
}
