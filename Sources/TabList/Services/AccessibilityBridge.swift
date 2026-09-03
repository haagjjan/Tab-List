@preconcurrency import ApplicationServices
import CoreGraphics
import Foundation
import TabListCore

/// One Accessibility window with a stable, process-scoped identity.
public struct AccessibilityWindowDescriptor: Equatable, Sendable {
    public let key: WindowKey
    public let role: String?
    public let subrole: String?
    public let title: String
    public let bounds: CGRect
    public let isMinimized: Bool
    public let isFullscreen: Bool
    public let isClosable: Bool
    public let isMain: Bool
    public let identitySource: WindowIdentitySource

    public init(
        key: WindowKey,
        role: String?,
        subrole: String?,
        title: String,
        bounds: CGRect,
        isMinimized: Bool,
        isFullscreen: Bool,
        isClosable: Bool,
        isMain: Bool,
        identitySource: WindowIdentitySource
    ) {
        self.key = key
        self.role = role
        self.subrole = subrole
        self.title = title
        self.bounds = bounds
        self.isMinimized = isMinimized
        self.isFullscreen = isFullscreen
        self.isClosable = isClosable
        self.isMain = isMain
        self.identitySource = identitySource
    }
}

/// Result of one enumeration pass over the candidate applications.
public struct AccessibilityWindowInventory: Sendable {
    /// Front-to-back per process, matching the order `AXWindows` reports.
    public let windowsByProcess: [pid_t: [AccessibilityWindowDescriptor]]
    /// Processes whose Accessibility lane failed or timed out. Their absence
    /// from `windowsByProcess` says nothing about whether they have windows.
    public let unavailableProcesses: Set<pid_t>
    public let isTrusted: Bool

    public init(
        windowsByProcess: [pid_t: [AccessibilityWindowDescriptor]],
        unavailableProcesses: Set<pid_t> = [],
        isTrusted: Bool
    ) {
        self.windowsByProcess = windowsByProcess
        self.unavailableProcesses = unavailableProcesses
        self.isTrusted = isTrusted
    }
}

/// Separates an application that genuinely exposes no windows from one whose
/// Accessibility lane failed or timed out. The two used to be indistinguishable,
/// which let applications vanish from the switcher without leaving a trace.
enum AccessibilityWindowLookup: Sendable {
    case windows([AccessibilityWindowDescriptor])
    case unavailable(AXError)
}

public enum AccessibilityOperationResult: Sendable {
    case success
    case targetMissing
    case permissionDenied
    case unsupported
    case timedOut
    case failed(String)

    public var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}

private final class AXElementBox: @unchecked Sendable {
    let value: AXUIElement

    init(_ value: AXUIElement) {
        self.value = value
    }
}

/// Raw window facts read in a single Accessibility pass.
private struct RawWindow {
    let element: AXUIElement
    let role: String?
    let subrole: String?
    let title: String
    let bounds: CGRect
    let isMinimized: Bool
    let isFullscreen: Bool
    let isClosable: Bool
    let isMain: Bool
}

/// Performs Accessibility IPC on one serial lane per target process, so a slow
/// application times out without blocking Accessibility work for the others.
public final class AccessibilityBridge: @unchecked Sendable {
    private let windowServer: WindowServerBridge
    private let stateLock = NSLock()
    private var lanes: [pid_t: DispatchQueue] = [:]
    private var cachedWindows: [WindowKey: AXElementBox] = [:]
    private var identityTables: [pid_t: WindowIdentityTable<AXUIElement>] = [:]
    private let messagingTimeout: Float

    public init(
        windowServer: WindowServerBridge,
        messagingTimeout: Duration = .milliseconds(300)
    ) {
        self.windowServer = windowServer
        let components = messagingTimeout.components
        self.messagingTimeout = Float(
            Double(components.seconds)
                + Double(components.attoseconds) / 1e18
        )
    }

    public var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    public func windowInventory(
        for processIDs: Set<pid_t>
    ) async -> AccessibilityWindowInventory {
        guard AXIsProcessTrusted() else {
            return AccessibilityWindowInventory(
                windowsByProcess: [:],
                isTrusted: false
            )
        }

        return await withTaskGroup(
            of: (pid_t, AccessibilityWindowLookup).self
        ) { group in
            for pid in processIDs where pid > 0 {
                group.addTask { [self] in
                    (pid, await windows(for: pid))
                }
            }
            var result: [pid_t: [AccessibilityWindowDescriptor]] = [:]
            var unavailable: Set<pid_t> = []
            result.reserveCapacity(processIDs.count)
            for await (pid, lookup) in group {
                switch lookup {
                case let .windows(descriptors):
                    guard !descriptors.isEmpty else { continue }
                    result[pid] = descriptors
                case let .unavailable(status):
                    // Never drop this silently: an unanswered lane is why an
                    // application disappears from the switcher entirely.
                    unavailable.insert(pid)
                    TabListLog.registry.warning(
                        """
                        Accessibility lane unavailable for pid \
                        \(pid, privacy: .public) status \
                        \(status.rawValue, privacy: .public)
                        """
                    )
                }
            }
            return AccessibilityWindowInventory(
                windowsByProcess: result,
                unavailableProcesses: unavailable,
                isTrusted: true
            )
        }
    }

    public func focusedWindowKey(for pid: pid_t) async -> WindowKey? {
        guard AXIsProcessTrusted(), pid > 0 else { return nil }
        return await perform(on: pid) { [self] in
            let application = configuredApplication(pid: pid)
            guard let focused = copyElement(
                application,
                attribute: kAXFocusedWindowAttribute as CFString
            ) else {
                return nil
            }
            let identity = assignIdentifier(
                to: focused,
                pid: pid,
                registeringAmong: copyElements(
                    application,
                    attribute: kAXWindowsAttribute as CFString
                )
            )
            let key = WindowKey(pid: pid, windowID: identity.id)
            cache(focused, for: key)
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
            let raiseResult = AXUIElementPerformAction(
                window,
                kAXRaiseAction as CFString
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
                kAXFrontmostAttribute as CFString,
                kCFBooleanTrue
            )
            return raiseResult == .success ? .success : map(error: raiseResult)
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
            return map(
                error: AXUIElementSetAttributeValue(
                    window,
                    kAXMinimizedAttribute as CFString,
                    kCFBooleanFalse
                )
            )
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
            ), copyBool(
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

    /// Drops cached elements for a process so the next operation resolves them
    /// again. The identity table is deliberately kept: it is what makes a
    /// window keep its key across a refresh, so discarding it mid-action would
    /// re-key every window of that process.
    public func invalidate(pid: pid_t) {
        stateLock.lock()
        cachedWindows = cachedWindows.filter { $0.key.pid != pid }
        stateLock.unlock()
    }

    /// Discards everything known about a process. Only correct once the
    /// process has terminated.
    public func forget(pid: pid_t) {
        stateLock.lock()
        cachedWindows = cachedWindows.filter { $0.key.pid != pid }
        identityTables[pid] = nil
        lanes[pid] = nil
        stateLock.unlock()
    }

    private func windows(
        for pid: pid_t
    ) async -> AccessibilityWindowLookup {
        await perform(on: pid) { [self] in
            let application = configuredApplication(pid: pid)
            let elements: [AXUIElement]
            switch copyWindowElements(application) {
            case let .elements(found):
                elements = found
            case let .failed(status):
                // Leave the identity table alone: the window list is unknown,
                // not empty, so pruning would discard live identities.
                return .unavailable(status)
            }
            guard !elements.isEmpty else {
                pruneIdentities(pid: pid, keeping: [])
                return .windows([])
            }

            let raw = elements.map(readWindow)
            let survivors = Self.withoutBackgroundNativeTabs(raw)
            pruneIdentities(pid: pid, keeping: elements)

            return .windows(survivors.map { window in
                let identity = assignIdentifier(
                    to: window.element,
                    pid: pid,
                    registeringAmong: nil
                )
                let key = WindowKey(pid: pid, windowID: identity.id)
                cache(window.element, for: key)
                return AccessibilityWindowDescriptor(
                    key: key,
                    role: window.role,
                    subrole: window.subrole,
                    title: window.title,
                    bounds: window.bounds,
                    isMinimized: window.isMinimized,
                    isFullscreen: window.isFullscreen,
                    isClosable: window.isClosable,
                    isMain: window.isMain,
                    identitySource: identity.source
                )
            })
        }
    }

    private static func withoutBackgroundNativeTabs(
        _ windows: [RawWindow]
    ) -> [RawWindow] {
        let retained = NativeTabCollapse.retainedIndices(
            of: windows.map {
                NativeTabCollapse.Candidate(
                    frame: NativeTabCollapse.Frame($0.bounds),
                    isMain: $0.isMain
                )
            },
            tabCount: { index in
                copyElements(
                    windows[index].element,
                    attribute: kAXTabsAttribute as CFString
                ).count
            }
        )
        return retained.map { windows[$0] }
    }

    private func readWindow(_ element: AXUIElement) -> RawWindow {
        AXUIElementSetMessagingTimeout(element, messagingTimeout)
        let titleElement = copyElement(
            element,
            attribute: kAXTitleUIElementAttribute as CFString
        )
        let closeButton = copyElement(
            element,
            attribute: kAXCloseButtonAttribute as CFString
        )
        let position = copyPoint(
            element,
            attribute: kAXPositionAttribute as CFString
        )
        let size = copySize(element, attribute: kAXSizeAttribute as CFString)

        return RawWindow(
            element: element,
            role: copyString(element, attribute: kAXRoleAttribute as CFString),
            subrole: copyString(
                element,
                attribute: kAXSubroleAttribute as CFString
            ),
            title: firstNonblankString([
                copyString(element, attribute: kAXTitleAttribute as CFString),
                titleElement.flatMap {
                    copyString($0, attribute: kAXValueAttribute as CFString)
                },
                titleElement.flatMap {
                    copyString($0, attribute: kAXTitleAttribute as CFString)
                },
            ]) ?? "",
            bounds: position.flatMap { origin in
                size.map { CGRect(origin: origin, size: $0) }
            } ?? .null,
            isMinimized: copyBool(
                element,
                attribute: kAXMinimizedAttribute as CFString
            ) ?? false,
            isFullscreen: copyBool(
                element,
                attribute: "AXFullScreen" as CFString
            ) ?? false,
            isClosable: closeButton.map {
                copyBool($0, attribute: kAXEnabledAttribute as CFString) != false
            } ?? false,
            isMain: copyBool(element, attribute: kAXMainAttribute as CFString)
                ?? false
        )
    }

    private func assignIdentifier(
        to element: AXUIElement,
        pid: pid_t,
        registeringAmong siblings: [AXUIElement]?
    ) -> (id: CGWindowID, source: WindowIdentitySource) {
        let windowServerID = windowServer.windowID(for: element)
        stateLock.lock()
        defer { stateLock.unlock() }
        var table = identityTables[pid] ?? Self.makeIdentityTable()
        if let siblings {
            table.retainOnly(siblings)
        }
        let resolved = table.identifier(
            for: element,
            windowServerID: windowServerID
        )
        identityTables[pid] = table
        return resolved
    }

    private func pruneIdentities(pid: pid_t, keeping elements: [AXUIElement]) {
        stateLock.lock()
        var table = identityTables[pid] ?? Self.makeIdentityTable()
        table.retainOnly(elements)
        identityTables[pid] = table
        stateLock.unlock()
    }

    private static func makeIdentityTable() -> WindowIdentityTable<AXUIElement> {
        WindowIdentityTable(isSameToken: { CFEqual($0, $1) })
    }

    private func resolveWindow(for key: WindowKey) -> AXUIElement? {
        if let cached = cachedWindow(for: key) {
            var pid: pid_t = 0
            if AXUIElementGetPid(cached, &pid) == .success, pid == key.pid,
               copyValue(cached, attribute: kAXRoleAttribute as CFString) != nil {
                return cached
            }
            removeCachedWindow(key)
        }

        let application = configuredApplication(pid: key.pid)
        let elements = copyElements(
            application,
            attribute: kAXWindowsAttribute as CFString
        )
        for element in elements {
            let identity = assignIdentifier(
                to: element,
                pid: key.pid,
                registeringAmong: nil
            )
            guard identity.id == key.windowID else { continue }
            cache(element, for: key)
            return element
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

    private func map(error: AXError) -> AccessibilityOperationResult {
        switch error {
        case .success:
            .success
        case .invalidUIElement:
            .targetMissing
        case .apiDisabled:
            .permissionDenied
        case .attributeUnsupported, .actionUnsupported, .notImplemented:
            .unsupported
        case .cannotComplete:
            .timedOut
        default:
            .failed("AX error \(error.rawValue)")
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

/// `AXError` does not conform to `Error`, so this carries the status directly
/// rather than through `Result`.
private enum WindowElementLookup {
    case elements([AXUIElement])
    case failed(AXError)
}

/// Like `copyElements`, but keeps the failure status instead of flattening it
/// into an empty array. `noValue` and `attributeUnsupported` are real answers
/// meaning "this process exposes no window list", not failures.
private func copyWindowElements(
    _ application: AXUIElement
) -> WindowElementLookup {
    var value: CFTypeRef?
    let status = AXUIElementCopyAttributeValue(
        application,
        kAXWindowsAttribute as CFString,
        &value
    )
    switch status {
    case .success:
        return .elements((value as? [AXUIElement]) ?? [])
    case .noValue, .attributeUnsupported:
        return .elements([])
    default:
        return .failed(status)
    }
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

private func firstNonblankString(_ values: [String?]) -> String? {
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
