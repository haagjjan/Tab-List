@preconcurrency import ApplicationServices
import CoreGraphics
import Darwin
import Foundation

public struct WindowServerCapabilities: OptionSet, Codable, Sendable {
    public let rawValue: UInt16

    public init(rawValue: UInt16) {
        self.rawValue = rawValue
    }

    public static let mainConnection = Self(rawValue: 1 << 0)
    public static let spaceInventory = Self(rawValue: 1 << 1)
    public static let windowSpaceQuery = Self(rawValue: 1 << 2)
    public static let accessibilityWindowID = Self(rawValue: 1 << 3)
}

public struct WindowServerCapabilityReport: Codable, Equatable, Sendable {
    public let detected: WindowServerCapabilities
    public let operational: WindowServerCapabilities
    public let frameworkPath: String?

    public init(
        detected: WindowServerCapabilities,
        operational: WindowServerCapabilities,
        frameworkPath: String?
    ) {
        self.detected = detected
        self.operational = operational
        self.frameworkPath = frameworkPath
    }

    /// Space scoping is the only user-visible feature that needs the private
    /// read-only queries. Window discovery and activation never do.
    public var usesPublicFallbacks: Bool {
        !operational.contains(.spaceInventory)
            || !operational.contains(.windowSpaceQuery)
    }
}

/// The sole owner of unsupported WindowServer entry points.
///
/// Every private symbol is read-only and is called only after a harmless probe
/// on the running system produced a plausible result. A symbol that fails its
/// probe stays off for the process lifetime and the caller degrades instead of
/// failing. No raw symbol or private type escapes this class.
public final class WindowServerBridge: @unchecked Sendable {
    private typealias MainConnectionFunction = @convention(c) () -> UInt32
    private typealias ManagedSpacesFunction =
        @convention(c) (UInt32) -> Unmanaged<CFArray>?
    private typealias SpacesForWindowsFunction =
        @convention(c) (UInt32, Int, CFArray) -> Unmanaged<CFArray>?
    private typealias AXWindowIDFunction =
        @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError

    private struct Symbols {
        let mainConnection: MainConnectionFunction?
        let managedSpaces: ManagedSpacesFunction?
        let spacesForWindows: SpacesForWindowsFunction?
        let axWindowID: AXWindowIDFunction?
    }

    private enum ProbeState {
        case pending
        case enabled
        case disabled
    }

    private static let frameworkCandidates = [
        "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
        "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics",
    ]
    private static let hiServicesPath =
        "/System/Library/Frameworks/ApplicationServices.framework/"
        + "Frameworks/HIServices.framework/HIServices"

    /// Verified against the compatibility fixture; kept local so the constant
    /// never leaks through the app.
    private static let allSpacesQueryMask = 7

    private let symbols: Symbols
    private let detected: WindowServerCapabilities
    private let frameworkPath: String?

    /// The identifier probe needs a trusted process with an inspectable
    /// window, which may not exist on the first attempt. It retries a few
    /// times and then gives up for the process lifetime.
    private static let maximumWindowIDProbeAttempts = 5

    /// Probes make synchronous Accessibility calls with a messaging timeout, so
    /// they run on a dedicated queue rather than blocking a cooperative thread.
    private let probeQueue = DispatchQueue(
        label: "com.haagjjan.TabList.WindowServerProbe",
        qos: .userInitiated
    )
    private let lock = NSLock()
    private var spaceProbe: ProbeState
    private var accessibilityWindowIDProbe: ProbeState
    private var windowIDProbeAttempts = 0

    public init() {
        var loadedHandle: UnsafeMutableRawPointer?
        var loadedPath: String?
        for path in Self.frameworkCandidates {
            if let candidate = dlopen(path, RTLD_LAZY | RTLD_LOCAL) {
                loadedHandle = candidate
                loadedPath = path
                break
            }
        }
        let hiServices = dlopen(Self.hiServicesPath, RTLD_LAZY | RTLD_LOCAL)

        let mainConnection: MainConnectionFunction? = Self.loadFunction(
            ["SLSMainConnectionID", "CGSMainConnectionID"],
            from: loadedHandle
        )
        let managedSpaces: ManagedSpacesFunction? = Self.loadFunction(
            ["SLSCopyManagedDisplaySpaces"],
            from: loadedHandle
        )
        let spacesForWindows: SpacesForWindowsFunction? = Self.loadFunction(
            ["SLSCopySpacesForWindows"],
            from: loadedHandle
        )
        let axWindowID: AXWindowIDFunction? = Self.loadFunction(
            ["_AXUIElementGetWindow"],
            from: hiServices
        )

        symbols = Symbols(
            mainConnection: mainConnection,
            managedSpaces: managedSpaces,
            spacesForWindows: spacesForWindows,
            axWindowID: axWindowID
        )
        frameworkPath = loadedPath

        var detected: WindowServerCapabilities = []
        if mainConnection != nil { detected.insert(.mainConnection) }
        if managedSpaces != nil { detected.insert(.spaceInventory) }
        if spacesForWindows != nil { detected.insert(.windowSpaceQuery) }
        if axWindowID != nil { detected.insert(.accessibilityWindowID) }
        self.detected = detected

        let spacesAvailable = mainConnection != nil
            && managedSpaces != nil
            && spacesForWindows != nil
        spaceProbe = spacesAvailable ? .pending : .disabled
        accessibilityWindowIDProbe = axWindowID == nil ? .disabled : .pending
    }

    public var capabilityReport: WindowServerCapabilityReport {
        lock.lock()
        let spaces = spaceProbe
        let windowID = accessibilityWindowIDProbe
        lock.unlock()

        var operational: WindowServerCapabilities = []
        if symbols.mainConnection != nil {
            operational.insert(.mainConnection)
        }
        if spaces == .enabled {
            operational.insert([.spaceInventory, .windowSpaceQuery])
        }
        if windowID == .enabled {
            operational.insert(.accessibilityWindowID)
        }
        return WindowServerCapabilityReport(
            detected: detected,
            operational: operational,
            frameworkPath: frameworkPath
        )
    }

    /// Runs any probe that has not yet reached a verdict. The inventory actor
    /// awaits this before each discovery, so no private query ever runs on the
    /// main actor and an Accessibility grant that arrives after launch still
    /// enables the window-identifier mapping.
    public func prepare() async {
        guard hasPendingProbe else { return }

        await withCheckedContinuation { continuation in
            probeQueue.async { [self] in
                runPendingProbes()
                continuation.resume()
            }
        }
    }

    private var hasPendingProbe: Bool {
        lock.lock()
        defer { lock.unlock() }
        return spaceProbe == .pending || accessibilityWindowIDProbe == .pending
    }

    private func runPendingProbes() {
        lock.lock()
        let needsSpaceProbe = spaceProbe == .pending
        let needsWindowIDProbe = accessibilityWindowIDProbe == .pending
        lock.unlock()

        if needsSpaceProbe {
            let succeeded = probeSpaceQueries()
            lock.lock()
            spaceProbe = succeeded ? .enabled : .disabled
            lock.unlock()
            TabListLog.compatibility.notice(
                "WindowServer Space queries \(succeeded ? "enabled" : "disabled", privacy: .public) after probe"
            )
        }

        if needsWindowIDProbe, AXIsProcessTrusted() {
            let succeeded = probeAccessibilityWindowID()
            lock.lock()
            windowIDProbeAttempts += 1
            if succeeded {
                accessibilityWindowIDProbe = .enabled
            } else if windowIDProbeAttempts
                >= Self.maximumWindowIDProbeAttempts {
                accessibilityWindowIDProbe = .disabled
            }
            let verdict = accessibilityWindowIDProbe
            lock.unlock()
            if verdict != .pending {
                TabListLog.compatibility.notice(
                    "Accessibility window-identifier mapping \(verdict == .enabled ? "enabled" : "disabled", privacy: .public) after probe"
                )
            }
        }
    }

    /// Maps an Accessibility element to its WindowServer identifier. Returning
    /// `nil` is a normal degraded outcome and never traps.
    public func windowID(for element: AXUIElement) -> CGWindowID? {
        lock.lock()
        let enabled = accessibilityWindowIDProbe == .enabled
        lock.unlock()
        guard enabled, let function = symbols.axWindowID else { return nil }

        var identifier: CGWindowID = 0
        guard function(element, &identifier) == .success, identifier != 0 else {
            return nil
        }
        return identifier
    }

    public func spaceIDs(forWindowID windowID: CGWindowID) -> [UInt64] {
        guard spacesAreEnabled,
              let connection = symbols.mainConnection?(),
              connection != 0,
              let spaces = symbols.spacesForWindows?(
                  connection,
                  Self.allSpacesQueryMask,
                  [NSNumber(value: windowID)] as CFArray
              )?.takeRetainedValue() else {
            return []
        }
        return Self.spaceIdentifiers(from: spaces)
    }

    public func visibleSpaceIDs() -> Set<UInt64> {
        guard spacesAreEnabled,
              let connection = symbols.mainConnection?(),
              connection != 0,
              let displays = symbols.managedSpaces?(
                  connection
              )?.takeRetainedValue() else {
            return []
        }
        return Self.currentSpaceIDs(from: displays)
    }

    private var spacesAreEnabled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return spaceProbe == .enabled
    }

    private func probeSpaceQueries() -> Bool {
        guard let connection = symbols.mainConnection?(), connection != 0,
              let displays = symbols.managedSpaces?(
                  connection
              )?.takeRetainedValue(),
              !Self.currentSpaceIDs(from: displays).isEmpty,
              let probeWindowID = Self.firstQueryableWindowID(),
              let spaces = symbols.spacesForWindows?(
                  connection,
                  Self.allSpacesQueryMask,
                  [NSNumber(value: probeWindowID)] as CFArray
              )?.takeRetainedValue() else {
            return false
        }
        return !Self.spaceIdentifiers(from: spaces).isEmpty
    }

    /// Confirms the element-to-identifier mapping end to end: an identifier it
    /// reports for a real Accessibility window must be one the public window
    /// list also attributes to that process.
    private func probeAccessibilityWindowID() -> Bool {
        guard let function = symbols.axWindowID,
              let info = CGWindowListCopyWindowInfo(
                  [.optionOnScreenOnly, .excludeDesktopElements],
                  kCGNullWindowID
              ) as? [[String: Any]] else {
            return false
        }

        var identifiersByPID: [pid_t: Set<CGWindowID>] = [:]
        for entry in info {
            guard (entry[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let pid = (entry[kCGWindowOwnerPID as String] as? NSNumber)?
                      .int32Value,
                  let identifier = (entry[kCGWindowNumber as String] as? NSNumber)?
                      .uint32Value,
                  identifier != 0 else {
                continue
            }
            identifiersByPID[pid, default: []].insert(identifier)
        }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        let inspectable = identifiersByPID
            .filter { $0.key != ownPID }
            .sorted { $0.key < $1.key }
            .prefix(4)
        for (pid, identifiers) in inspectable {
            let application = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(application, 0.3)
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(
                application,
                kAXWindowsAttribute as CFString,
                &value
            ) == .success, let windows = value as? [AXUIElement] else {
                continue
            }
            for window in windows {
                var identifier: CGWindowID = 0
                if function(window, &identifier) == .success,
                   identifiers.contains(identifier) {
                    return true
                }
            }
        }
        return false
    }

    private static func loadFunction<T>(
        _ names: [String],
        from handle: UnsafeMutableRawPointer?
    ) -> T? {
        guard let handle else { return nil }
        for name in names {
            guard let symbol = dlsym(handle, name) else { continue }
            return unsafeBitCast(symbol, to: T.self)
        }
        return nil
    }

    private static func spaceIdentifiers(from spaces: CFArray) -> [UInt64] {
        (spaces as [AnyObject]).compactMap {
            guard let value = ($0 as? NSNumber)?.uint64Value, value != 0 else {
                return nil
            }
            return value
        }
    }

    private static func currentSpaceIDs(from displays: CFArray) -> Set<UInt64> {
        var identifiers: Set<UInt64> = []
        for case let display as NSDictionary in displays as [AnyObject] {
            guard let currentSpace = display["Current Space"] as? NSDictionary
            else {
                continue
            }
            let identifier = (
                currentSpace["ManagedSpaceID"] ?? currentSpace["id64"]
            ) as? NSNumber
            if let identifier, identifier.uint64Value != 0 {
                identifiers.insert(identifier.uint64Value)
            }
        }
        return identifiers
    }

    private static func firstQueryableWindowID() -> CGWindowID? {
        guard let info = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return nil
        }
        return info.lazy.compactMap { window -> CGWindowID? in
            guard (window[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let number = window[kCGWindowNumber as String] as? NSNumber
            else {
                return nil
            }
            let identifier = CGWindowID(number.uint32Value)
            return identifier == 0 ? nil : identifier
        }.first
    }
}
