@preconcurrency import ApplicationServices
import CoreGraphics
import Foundation
import TabListCore

public struct AccessibilityWindowMetadata: Equatable, Sendable {
    public let role: String?
    public let subrole: String?
    public let title: String?
    public let bounds: CGRect?
    public let isMinimized: Bool
    public let isFullscreen: Bool
    public let isStandardWindow: Bool
    public let isClosable: Bool
    public let isMain: Bool
    public let nativeTabGroupID: UInt64?
    public let nativeTabCount: Int

    public init(
        role: String?,
        subrole: String?,
        title: String?,
        bounds: CGRect?,
        isMinimized: Bool,
        isFullscreen: Bool,
        isStandardWindow: Bool,
        isClosable: Bool,
        isMain: Bool = false,
        nativeTabGroupID: UInt64? = nil,
        nativeTabCount: Int = 0
    ) {
        self.role = role
        self.subrole = subrole
        self.title = title
        self.bounds = bounds
        self.isMinimized = isMinimized
        self.isFullscreen = isFullscreen
        self.isStandardWindow = isStandardWindow
        self.isClosable = isClosable
        self.isMain = isMain
        self.nativeTabGroupID = nativeTabGroupID
        self.nativeTabCount = nativeTabCount
    }
}

/// One Accessibility enumeration pass for the candidate applications. A PID in
/// `inspectedPIDs` returned its AX window list successfully, so WindowServer
/// surfaces not present in `metadata` are backing/helper surfaces rather than
/// independent selectable windows.
public struct AccessibilityWindowInventory: Sendable {
    public let metadata: [WindowKey: AccessibilityWindowMetadata]
    public let identitySources: [WindowKey: WindowIdentitySource]
    public let inspectedPIDs: Set<pid_t>
    public let unresolvedStandardWindowCounts: [pid_t: Int]
    public let isTrusted: Bool

    public init(
        metadata: [WindowKey: AccessibilityWindowMetadata],
        identitySources: [WindowKey: WindowIdentitySource],
        inspectedPIDs: Set<pid_t>,
        unresolvedStandardWindowCounts: [pid_t: Int],
        isTrusted: Bool
    ) {
        self.metadata = metadata
        self.identitySources = identitySources
        self.inspectedPIDs = inspectedPIDs
        self.unresolvedStandardWindowCounts = unresolvedStandardWindowCounts
        self.isTrusted = isTrusted
    }
}

private struct ProcessAccessibilityWindowInventory: Sendable {
    let metadata: [WindowKey: AccessibilityWindowMetadata]
    let identitySources: [WindowKey: WindowIdentitySource]
    let wasInspected: Bool
    let unresolvedStandardWindowCount: Int
}

struct AccessibilityWindowMatchDescriptor: Equatable, Sendable {
    let title: String?
    let bounds: CGRect?
    let isPreferred: Bool
    let nativeTabCount: Int

    init(
        title: String?,
        bounds: CGRect?,
        isPreferred: Bool = false,
        nativeTabCount: Int = 0
    ) {
        self.title = title
        self.bounds = bounds
        self.isPreferred = isPreferred
        self.nativeTabCount = nativeTabCount
    }
}

/// Pure, conservative scoring for the public AX-to-WindowServer fallback.
///
/// A match is usable only when one candidate has a materially better score.
/// Ties fail closed because acting on an arbitrary AX element can activate or
/// close the wrong same-app window.
enum AccessibilityGeometryMatcher {
    private struct Match {
        let index: Int
        let titlePenalty: Int
        let geometryDistance: CGFloat
    }

    private static let maximumGeometryDistance: CGFloat = 12
    private static let ambiguityTolerance: CGFloat = 0.5

    /// Produces a one-to-one mapping from WindowServer candidate indices to
    /// Accessibility window indices.
    ///
    /// Strong reciprocal title/geometry matches are assigned first. If several
    /// otherwise identical candidates remain, they stay unresolved: ordering
    /// alone is not identity evidence and could make a selectable item act on
    /// the wrong window. The sole grouped exception is a single AX container
    /// that explicitly reports the matching number of native tabs; that maps
    /// to the frontmost WindowServer surface so the group appears once.
    static func assignments(
        candidates: [AccessibilityWindowMatchDescriptor],
        windows: [AccessibilityWindowMatchDescriptor]
    ) -> [Int: Int] {
        var result: [Int: Int] = [:]
        var usedWindows: Set<Int> = []

        for candidateIndex in candidates.indices {
            guard let windowIndex = uniqueMatchIndex(
                target: candidates[candidateIndex],
                candidates: windows
            ),
            uniqueMatchIndex(
                target: windows[windowIndex],
                candidates: candidates
            ) == candidateIndex,
            usedWindows.insert(windowIndex).inserted
            else {
                continue
            }
            result[candidateIndex] = windowIndex
        }

        let remainingCandidates = candidates.indices.filter {
            result[$0] == nil && candidates[$0].bounds != nil
        }
        let remainingWindows = windows.indices.filter {
            !usedWindows.contains($0) && windows[$0].bounds != nil
        }
        let candidateGroups = Dictionary(
            grouping: remainingCandidates,
            by: { geometrySignature(candidates[$0].bounds) }
        )
        let windowGroups = Dictionary(
            grouping: remainingWindows,
            by: { geometrySignature(windows[$0].bounds) }
        )

        for (signature, candidateIndices) in candidateGroups {
            guard let signature,
                  let windowIndices = windowGroups[signature] else {
                continue
            }

            if windowIndices.count == 1,
               let windowIndex = windowIndices.first,
               windows[windowIndex].nativeTabCount
                == candidateIndices.count,
               candidateIndices.count > 1 {
                result[candidateIndices[0]] = windowIndex
                continue
            }
            // Multiple AX windows and multiple compositor surfaces with the
            // same title/geometry cannot be paired safely without exact IDs.
            // Fail closed until the private AX window-ID capability has been
            // validated for this macOS build.
        }
        return result
    }

    static func uniqueMatchIndex(
        target: AccessibilityWindowMatchDescriptor,
        candidates: [AccessibilityWindowMatchDescriptor]
    ) -> Int? {
        guard let targetBounds = target.bounds else { return nil }

        let matches = candidates.enumerated().compactMap {
            index,
            candidate -> Match? in
            guard let candidateBounds = candidate.bounds else {
                return nil
            }
            let distance = geometryDistance(
                targetBounds,
                candidateBounds
            )
            guard distance <= maximumGeometryDistance else {
                return nil
            }
            return Match(
                index: index,
                titlePenalty: titlePenalty(
                    target.title,
                    candidate.title
                ),
                geometryDistance: distance
            )
        }.sorted { lhs, rhs in
            if lhs.titlePenalty != rhs.titlePenalty {
                return lhs.titlePenalty < rhs.titlePenalty
            }
            if lhs.geometryDistance != rhs.geometryDistance {
                return lhs.geometryDistance < rhs.geometryDistance
            }
            return lhs.index < rhs.index
        }

        guard let best = matches.first else { return nil }
        if matches.count > 1 {
            let runnerUp = matches[1]
            if best.titlePenalty == runnerUp.titlePenalty,
               abs(best.geometryDistance - runnerUp.geometryDistance)
                <= ambiguityTolerance {
                return nil
            }
        }
        return best.index
    }

    private static func titlePenalty(
        _ lhs: String?,
        _ rhs: String?
    ) -> Int {
        let left = normalizedTitle(lhs)
        let right = normalizedTitle(rhs)
        if !left.isEmpty, !right.isEmpty {
            return left == right ? 0 : 2
        }
        return 1
    }

    private static func normalizedTitle(_ title: String?) -> String {
        title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func geometryDistance(
        _ lhs: CGRect,
        _ rhs: CGRect
    ) -> CGFloat {
        abs(lhs.origin.x - rhs.origin.x)
            + abs(lhs.origin.y - rhs.origin.y)
            + abs(lhs.width - rhs.width)
            + abs(lhs.height - rhs.height)
    }

    private static func geometrySignature(
        _ bounds: CGRect?
    ) -> [Int]? {
        guard let bounds else { return nil }
        return [
            Int(bounds.origin.x.rounded()),
            Int(bounds.origin.y.rounded()),
            Int(bounds.width.rounded()),
            Int(bounds.height.rounded()),
        ]
    }
}

public enum AccessibilityOperationResult: Sendable {
    case success
    case targetMissing
    case permissionDenied
    case unsupported
    case timedOut
    case failed(String)
}

private final class AXElementBox: @unchecked Sendable {
    let value: AXUIElement

    init(_ value: AXUIElement) {
        self.value = value
    }
}

/// Performs AX IPC on one serial lane per target process. A slow application can
/// therefore time out without blocking AX work for every other application.
public final class AccessibilityBridge: @unchecked Sendable {
    private let windowServer: WindowServerBridge
    private let stateLock = NSLock()
    private var lanes: [pid_t: DispatchQueue] = [:]
    private var cachedWindows: [WindowKey: AXElementBox] = [:]
    private let messagingTimeout: Float

    public init(
        windowServer: WindowServerBridge,
        messagingTimeout: Duration = .milliseconds(300)
    ) {
        self.windowServer = windowServer
        let components = messagingTimeout.components
        self.messagingTimeout = Float(
            Double(components.seconds)
                + Double(components.attoseconds)
                    / 1_000_000_000_000_000_000
        )
    }

    public func metadata(
        for candidates: [PublicWindowCandidate]
    ) async -> [WindowKey: AccessibilityWindowMetadata] {
        guard AXIsProcessTrusted() else { return [:] }
        let grouped = Dictionary(grouping: candidates, by: \.key.pid)

        return await withTaskGroup(
            of: [WindowKey: AccessibilityWindowMetadata].self,
            returning: [WindowKey: AccessibilityWindowMetadata].self
        ) { group in
            for (pid, processCandidates) in grouped {
                group.addTask { [self] in
                    await metadata(for: processCandidates, pid: pid)
                }
            }

            var result: [WindowKey: AccessibilityWindowMetadata] = [:]
            for await processResult in group {
                result.merge(processResult) { _, new in new }
            }
            return result
        }
    }

    /// Enumerates Accessibility windows independently from the public
    /// WindowServer list. This is what lets minimized, hidden-application, and
    /// off-Space windows remain discoverable when
    /// `CGWindowListCopyWindowInfo` omits their surfaces.
    ///
    /// A result requires a process-scoped WindowServer identifier. Systems
    /// where the dynamically resolved AX-to-window-ID capability is unavailable
    /// simply return fewer records and continue through the public inventory
    /// fallback.
    public func windowInventory(
        for processIDs: Set<pid_t>
    ) async -> AccessibilityWindowInventory {
        guard AXIsProcessTrusted() else {
            return AccessibilityWindowInventory(
                metadata: [:],
                identitySources: [:],
                inspectedPIDs: [],
                unresolvedStandardWindowCounts: [:],
                isTrusted: false
            )
        }

        return await withTaskGroup(
            of: (pid_t, ProcessAccessibilityWindowInventory).self,
            returning: AccessibilityWindowInventory.self
        ) { group in
            for pid in processIDs where pid > 0 {
                group.addTask { [self] in
                    (pid, await discoveredWindows(for: pid))
                }
            }

            var result: [WindowKey: AccessibilityWindowMetadata] = [:]
            var sources: [WindowKey: WindowIdentitySource] = [:]
            var inspectedPIDs: Set<pid_t> = []
            var unresolved: [pid_t: Int] = [:]
            for await (pid, processResult) in group {
                result.merge(processResult.metadata) { _, new in new }
                sources.merge(processResult.identitySources) { _, new in new }
                if processResult.wasInspected {
                    inspectedPIDs.insert(pid)
                }
                if processResult.unresolvedStandardWindowCount > 0 {
                    unresolved[pid] = processResult.unresolvedStandardWindowCount
                }
            }
            return AccessibilityWindowInventory(
                metadata: result,
                identitySources: sources,
                inspectedPIDs: inspectedPIDs,
                unresolvedStandardWindowCounts: unresolved,
                isTrusted: true
            )
        }
    }

    public func discoveredWindows(
        for processIDs: Set<pid_t>
    ) async -> [WindowKey: AccessibilityWindowMetadata] {
        await windowInventory(for: processIDs).metadata
    }

    public func focusedWindowKey(for pid: pid_t) async -> WindowKey? {
        guard AXIsProcessTrusted() else { return nil }
        return await perform(on: pid) { [self] in
            let application = configuredApplication(pid: pid)
            guard let window = copyElement(
                application,
                attribute: kAXFocusedWindowAttribute as CFString
            ) else {
                return nil
            }
            let publicCandidates = publicWindowCandidates(pid: pid)
            let applicationWindows = copyElements(
                application,
                attribute: kAXWindowsAttribute as CFString
            )
            let windowID = uniquePrivateWindowIDs(
                for: applicationWindows
            ).first(where: {
                CFEqual($0.value, window)
            })?.key
                ?? uniqueGeometryMatches(
                    candidates: publicCandidates,
                    windows: applicationWindows
                ).first(where: {
                    CFEqual($0.value, window)
                })?.key.windowID
            guard let windowID else { return nil }

            let key = WindowKey(pid: pid, windowID: windowID)
            cache(window, for: key)
            return key
        }
    }

    public func activate(_ key: WindowKey) async -> AccessibilityOperationResult {
        guard AXIsProcessTrusted() else { return .permissionDenied }

        return await perform(on: key.pid) { [self] in
            guard let window = resolveWindow(for: key) else {
                return .targetMissing
            }

            let application = configuredApplication(pid: key.pid)
            _ = AXUIElementSetAttributeValue(
                window,
                kAXMinimizedAttribute as CFString,
                kCFBooleanFalse
            )
            _ = AXUIElementSetAttributeValue(
                application,
                kAXFrontmostAttribute as CFString,
                kCFBooleanTrue
            )
            _ = AXUIElementSetAttributeValue(
                window,
                kAXMainAttribute as CFString,
                kCFBooleanTrue
            )
            _ = AXUIElementSetAttributeValue(
                window,
                kAXFocusedAttribute as CFString,
                kCFBooleanTrue
            )
            _ = AXUIElementSetAttributeValue(
                application,
                kAXFocusedWindowAttribute as CFString,
                window
            )

            let raiseResult = AXUIElementPerformAction(
                window,
                kAXRaiseAction as CFString
            )
            if raiseResult == .success {
                return .success
            }
            return map(error: raiseResult)
        }
    }

    public func unminimize(
        _ key: WindowKey
    ) async -> AccessibilityOperationResult {
        guard AXIsProcessTrusted() else { return .permissionDenied }

        return await perform(on: key.pid) { [self] in
            guard let window = resolveWindow(for: key) else {
                return .targetMissing
            }
            let result = AXUIElementSetAttributeValue(
                window,
                kAXMinimizedAttribute as CFString,
                kCFBooleanFalse
            )
            return map(error: result)
        }
    }

    public func close(_ key: WindowKey) async -> AccessibilityOperationResult {
        guard AXIsProcessTrusted() else { return .permissionDenied }

        return await perform(on: key.pid) { [self] in
            guard let window = resolveWindow(for: key) else {
                return .targetMissing
            }
            guard let closeButton = copyElement(
                window,
                attribute: kAXCloseButtonAttribute as CFString
            ) else {
                return .unsupported
            }
            guard copyBool(
                closeButton,
                attribute: kAXEnabledAttribute as CFString
            ) != false else {
                return .unsupported
            }

            let result = AXUIElementPerformAction(
                closeButton,
                kAXPressAction as CFString
            )
            if result == .success {
                removeCachedWindow(key)
                return .success
            }
            return map(error: result)
        }
    }

    public func invalidate(pid: pid_t) {
        stateLock.lock()
        cachedWindows = cachedWindows.filter { $0.key.pid != pid }
        lanes[pid] = nil
        stateLock.unlock()
    }

    public func invalidateAll() {
        stateLock.lock()
        cachedWindows.removeAll(keepingCapacity: false)
        stateLock.unlock()
    }

    private func metadata(
        for candidates: [PublicWindowCandidate],
        pid: pid_t
    ) async -> [WindowKey: AccessibilityWindowMetadata] {
        await perform(on: pid) { [self] in
            let application = configuredApplication(pid: pid)
            let windows = copyElements(
                application,
                attribute: kAXWindowsAttribute as CFString
            )

            let byID = uniquePrivateWindowIDs(for: windows)
            let privatelyMappedElements = Array(byID.values)
            let fallbackCandidates = candidates.filter {
                byID[$0.key.windowID] == nil
            }
            let fallbackWindows = windows.filter { window in
                !privatelyMappedElements.contains {
                    CFEqual($0, window)
                }
            }
            let fallbackMatches = uniqueGeometryMatches(
                candidates: fallbackCandidates,
                windows: fallbackWindows
            )

            var result: [WindowKey: AccessibilityWindowMetadata] = [:]
            for candidate in candidates {
                let element = byID[candidate.key.windowID]
                    ?? fallbackMatches[candidate.key]
                guard let element else { continue }
                cache(element, for: candidate.key)
                result[candidate.key] = readMetadata(from: element)
            }
            return result
        }
    }

    private func discoveredWindows(
        for pid: pid_t
    ) async -> ProcessAccessibilityWindowInventory {
        await perform(on: pid) { [self] in
            let application = configuredApplication(pid: pid)
            let windowResult = copyElementsWithStatus(
                application,
                attribute: kAXWindowsAttribute as CFString
            )
            guard windowResult.error == .success else {
                return ProcessAccessibilityWindowInventory(
                    metadata: [:],
                    identitySources: [:],
                    wasInspected: false,
                    unresolvedStandardWindowCount: 0
                )
            }
            let windows = windowResult.elements
            let publicCandidates = publicWindowCandidates(pid: pid)
            let privateIDs = uniquePrivateWindowIDs(for: windows)
            let privatelyMappedElements = Array(privateIDs.values)
            let fallbackCandidates = publicCandidates.filter {
                privateIDs[$0.key.windowID] == nil
            }
            let fallbackWindows = windows.filter { window in
                !privatelyMappedElements.contains {
                    CFEqual($0, window)
                }
            }
            let fallbackMatches = uniqueGeometryMatches(
                candidates: fallbackCandidates,
                windows: fallbackWindows
            )

            var result: [WindowKey: AccessibilityWindowMetadata] = [:]
            var sources: [WindowKey: WindowIdentitySource] = [:]
            result.reserveCapacity(windows.count)
            var standardWindowCount = 0
            for window in windows {
                let metadata = readMetadata(from: window)
                guard metadata.isStandardWindow else { continue }
                standardWindowCount += 1

                let exactIdentifier = privateIDs.first(where: {
                    CFEqual($0.value, window)
                })?.key
                let fallbackIdentifier = fallbackMatches.first(where: {
                    CFEqual($0.value, window)
                })?.key.windowID
                guard let identifier = exactIdentifier ?? fallbackIdentifier,
                      identifier != 0 else {
                    continue
                }
                let key = WindowKey(pid: pid, windowID: identifier)
                cache(window, for: key)
                result[key] = metadata
                sources[key] = exactIdentifier == nil
                    ? .uniqueGeometry
                    : .exactAccessibilityID
            }
            return ProcessAccessibilityWindowInventory(
                metadata: result,
                identitySources: sources,
                wasInspected: true,
                unresolvedStandardWindowCount: max(
                    0,
                    standardWindowCount - result.count
                )
            )
        }
    }

    private func readMetadata(
        from element: AXUIElement
    ) -> AccessibilityWindowMetadata {
        let role = copyString(element, attribute: kAXRoleAttribute as CFString)
        let subrole = copyString(
            element,
            attribute: kAXSubroleAttribute as CFString
        )
        let tabs = copyElements(
            element,
            attribute: kAXTabsAttribute as CFString
        )
        let selectedTab = tabs.first {
            copyBool($0, attribute: kAXSelectedAttribute as CFString) == true
        }
        let titleElement = copyElement(
            element,
            attribute: kAXTitleUIElementAttribute as CFString
        )
        let title = firstNonblankString([
            copyString(element, attribute: kAXTitleAttribute as CFString),
            selectedTab.flatMap {
                copyString($0, attribute: kAXTitleAttribute as CFString)
            },
            titleElement.flatMap {
                copyString($0, attribute: kAXValueAttribute as CFString)
            },
            titleElement.flatMap {
                copyString($0, attribute: kAXTitleAttribute as CFString)
            },
        ])
        let position = copyPoint(
            element,
            attribute: kAXPositionAttribute as CFString
        )
        let size = copySize(element, attribute: kAXSizeAttribute as CFString)
        let bounds = position.flatMap { origin in
            size.map { CGRect(origin: origin, size: $0) }
        }
        let isMinimized = copyBool(
            element,
            attribute: kAXMinimizedAttribute as CFString
        ) ?? false
        let isFullscreen = copyBool(
            element,
            attribute: "AXFullScreen" as CFString
        ) ?? false
        let isMain =
            copyBool(element, attribute: kAXMainAttribute as CFString)
                ?? copyBool(
                    element,
                    attribute: kAXFocusedAttribute as CFString
                )
                ?? false
        let closeButton = copyElement(
            element,
            attribute: kAXCloseButtonAttribute as CFString
        )
        let closeButtonIsEnabled = closeButton.flatMap {
            copyBool($0, attribute: kAXEnabledAttribute as CFString)
        }

        let isStandard = role == (kAXWindowRole as String)
            && (
                subrole == nil
                    || subrole == (kAXStandardWindowSubrole as String)
                    || subrole == (kAXDialogSubrole as String)
            )

        return AccessibilityWindowMetadata(
            role: role,
            subrole: subrole,
            title: title,
            bounds: bounds,
            isMinimized: isMinimized,
            isFullscreen: isFullscreen,
            isStandardWindow: isStandard,
            isClosable: closeButton != nil && closeButtonIsEnabled != false,
            isMain: isMain,
            nativeTabGroupID: nativeTabGroupID(for: tabs),
            nativeTabCount: tabs.count
        )
    }

    private func nativeTabGroupID(
        for tabs: [AXUIElement]
    ) -> UInt64? {
        guard tabs.count > 1 else { return nil }
        let elementHashes = tabs.map {
            UInt64(truncatingIfNeeded: CFHash($0))
        }.sorted()
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for elementHash in elementHashes {
            hash ^= elementHash
            hash &*= 0x0000_0100_0000_01b3
        }
        hash ^= UInt64(tabs.count)
        return hash
    }

    private func resolveWindow(for key: WindowKey) -> AXUIElement? {
        if let cached = cachedWindow(for: key) {
            var pid: pid_t = 0
            if AXUIElementGetPid(cached, &pid) == .success, pid == key.pid {
                return cached
            }
            removeCachedWindow(key)
        }

        let application = configuredApplication(pid: key.pid)
        let windows = copyElements(
            application,
            attribute: kAXWindowsAttribute as CFString
        )
        if let window = uniquePrivateWindowIDs(
            for: windows
        )[key.windowID] {
            cache(window, for: key)
            return window
        }
        let candidates = publicWindowCandidates(pid: key.pid)
        if let window = uniqueGeometryMatches(
            candidates: candidates,
            windows: windows
        )[key] {
            cache(window, for: key)
            return window
        }
        return nil
    }

    private func configuredApplication(pid: pid_t) -> AXUIElement {
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, messagingTimeout)
        return application
    }

    private func perform<T: Sendable>(
        on pid: pid_t,
        operation: @escaping @Sendable () -> T
    ) async -> T {
        let queue = lane(for: pid)
        return await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: operation())
            }
        }
    }

    private func lane(for pid: pid_t) -> DispatchQueue {
        stateLock.lock()
        defer { stateLock.unlock() }
        if let lane = lanes[pid] {
            return lane
        }
        let lane = DispatchQueue(
            label: "com.haagjjan.TabList.Accessibility.\(pid)",
            qos: .userInitiated
        )
        lanes[pid] = lane
        return lane
    }

    private func cache(_ element: AXUIElement, for key: WindowKey) {
        stateLock.lock()
        cachedWindows[key] = AXElementBox(element)
        stateLock.unlock()
    }

    private func cachedWindow(for key: WindowKey) -> AXUIElement? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return cachedWindows[key]?.value
    }

    private func removeCachedWindow(_ key: WindowKey) {
        stateLock.lock()
        cachedWindows[key] = nil
        stateLock.unlock()
    }

    private func uniqueGeometryMatches(
        candidates: [PublicWindowCandidate],
        windows: [AXUIElement]
    ) -> [WindowKey: AXUIElement] {
        let eligibleWindows = windows.compactMap {
            window -> (
                element: AXUIElement,
                descriptor: AccessibilityWindowMatchDescriptor
            )? in
            let metadata = readMetadata(from: window)
            guard metadata.isStandardWindow else { return nil }
            return (
                window,
                AccessibilityWindowMatchDescriptor(
                    title: metadata.title,
                    bounds: metadata.bounds,
                    isPreferred: metadata.isMain,
                    nativeTabCount: metadata.nativeTabCount
                )
            )
        }
        let candidateDescriptors = candidates.map {
            AccessibilityWindowMatchDescriptor(
                title: $0.title,
                bounds: $0.bounds
            )
        }
        let windowDescriptors = eligibleWindows.map(\.descriptor)
        var result: [WindowKey: AXUIElement] = [:]
        let assignments = AccessibilityGeometryMatcher.assignments(
            candidates: candidateDescriptors,
            windows: windowDescriptors
        )
        for (candidateIndex, windowIndex) in assignments {
            let candidate = candidates[candidateIndex]
            result[candidate.key] = eligibleWindows[windowIndex].element
        }
        return result
    }

    private func uniquePrivateWindowIDs(
        for windows: [AXUIElement]
    ) -> [CGWindowID: AXUIElement] {
        var result: [CGWindowID: AXUIElement] = [:]
        var ambiguousIDs: Set<CGWindowID> = []

        for window in windows {
            guard let identifier = windowServer.windowID(for: window),
                  !ambiguousIDs.contains(identifier) else {
                continue
            }
            if result[identifier] != nil {
                result[identifier] = nil
                ambiguousIDs.insert(identifier)
            } else {
                result[identifier] = window
            }
        }
        return result
    }

    private func publicWindowCandidates(
        pid: pid_t
    ) -> [PublicWindowCandidate] {
        guard let dictionaries = CGWindowListCopyWindowInfo(
            [.optionAll, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return []
        }
        return dictionaries.compactMap { dictionary in
            guard let ownerPID = (
                dictionary[kCGWindowOwnerPID as String] as? NSNumber
            )?.int32Value,
                  ownerPID == pid,
                  let identifier = (
                      dictionary[kCGWindowNumber as String] as? NSNumber
                  )?.uint32Value,
                  identifier != 0,
                  (
                      dictionary[kCGWindowLayer as String] as? NSNumber
                  )?.intValue == 0,
                  let boundsDictionary = dictionary[
                      kCGWindowBounds as String
                  ] as? NSDictionary,
                  let bounds = CGRect(
                      dictionaryRepresentation:
                          boundsDictionary as CFDictionary
                  ) else {
                return nil
            }
            return PublicWindowCandidate(
                key: WindowKey(pid: pid, windowID: identifier),
                ownerName: dictionary[
                    kCGWindowOwnerName as String
                ] as? String ?? "",
                title: dictionary[
                    kCGWindowName as String
                ] as? String ?? "",
                bounds: bounds,
                layer: (
                    dictionary[kCGWindowLayer as String] as? NSNumber
                )?.intValue ?? 0,
                alpha: (
                    dictionary[kCGWindowAlpha as String] as? NSNumber
                )?.doubleValue ?? 1,
                isOnScreen: (
                    dictionary[kCGWindowIsOnscreen as String] as? NSNumber
                )?.boolValue ?? false
            )
        }
    }

    private func map(error: AXError) -> AccessibilityOperationResult {
        switch error {
        case .success:
            return .success
        case .invalidUIElement:
            return .targetMissing
        case .apiDisabled:
            return .permissionDenied
        case .attributeUnsupported, .actionUnsupported, .notImplemented:
            return .unsupported
        case .cannotComplete:
            return .timedOut
        default:
            return .failed("AX error \(error.rawValue)")
        }
    }
}

private func copyValue(
    _ element: AXUIElement,
    attribute: CFString
) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success
    else {
        return nil
    }
    return value
}

private func copyElement(
    _ element: AXUIElement,
    attribute: CFString
) -> AXUIElement? {
    guard let value = copyValue(element, attribute: attribute),
          CFGetTypeID(value) == AXUIElementGetTypeID() else {
        return nil
    }
    return unsafeDowncast(value, to: AXUIElement.self)
}

private func copyElements(
    _ element: AXUIElement,
    attribute: CFString
) -> [AXUIElement] {
    guard let value = copyValue(element, attribute: attribute),
          let array = value as? [AXUIElement] else {
        return []
    }
    return array
}

private func copyElementsWithStatus(
    _ element: AXUIElement,
    attribute: CFString
) -> (error: AXError, elements: [AXUIElement]) {
    var value: CFTypeRef?
    let error = AXUIElementCopyAttributeValue(element, attribute, &value)
    guard error == .success,
          let value,
          let elements = value as? [AXUIElement] else {
        return (error, [])
    }
    return (error, elements)
}

private func firstNonblankString(
    _ values: [String?]
) -> String? {
    for value in values {
        let trimmed = value?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty {
            return trimmed
        }
    }
    return nil
}

private func copyString(
    _ element: AXUIElement,
    attribute: CFString
) -> String? {
    copyValue(element, attribute: attribute) as? String
}

private func copyBool(
    _ element: AXUIElement,
    attribute: CFString
) -> Bool? {
    copyValue(element, attribute: attribute) as? Bool
}

private func copyPoint(
    _ element: AXUIElement,
    attribute: CFString
) -> CGPoint? {
    guard let value = copyValue(element, attribute: attribute),
          CFGetTypeID(value) == AXValueGetTypeID() else {
        return nil
    }
    let axValue = unsafeDowncast(value, to: AXValue.self)
    var point = CGPoint.zero
    guard AXValueGetType(axValue) == .cgPoint,
          AXValueGetValue(axValue, .cgPoint, &point) else {
        return nil
    }
    return point
}

private func copySize(
    _ element: AXUIElement,
    attribute: CFString
) -> CGSize? {
    guard let value = copyValue(element, attribute: attribute),
          CFGetTypeID(value) == AXValueGetTypeID() else {
        return nil
    }
    let axValue = unsafeDowncast(value, to: AXValue.self)
    var size = CGSize.zero
    guard AXValueGetType(axValue) == .cgSize,
          AXValueGetValue(axValue, .cgSize, &size) else {
        return nil
    }
    return size
}
