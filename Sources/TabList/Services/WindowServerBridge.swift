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
    public static let notifications = Self(rawValue: 1 << 3)
    public static let exactActivation = Self(rawValue: 1 << 4)
    public static let hardwareCapture = Self(rawValue: 1 << 5)
    public static let accessibilityWindowID = Self(rawValue: 1 << 6)
    public static let remoteAccessibilityElement = Self(rawValue: 1 << 7)
}

public struct WindowServerCapabilityReport: Codable, Sendable {
    public let detected: WindowServerCapabilities
    public let operational: WindowServerCapabilities
    public let frameworkPath: String?

    public var usesPublicFallbacks: Bool {
        !operational.contains(.spaceInventory)
            || !operational.contains(.windowSpaceQuery)
            || !operational.contains(.exactActivation)
            || !operational.contains(.accessibilityWindowID)
    }
}

/// The sole owner of unsupported WindowServer entry points.
///
/// Only entry points with independently verified, harmless calling conventions
/// are invoked. Other symbols are reported as detected but are intentionally not
/// called until a compatibility test validates their ABI on the running macOS
/// build. No raw symbol or private type escapes this class.
public final class WindowServerBridge: @unchecked Sendable {
    private typealias MainConnectionFunction = @convention(c) () -> UInt32
    private typealias ManagedSpacesFunction =
        @convention(c) (UInt32) -> Unmanaged<CFArray>?
    private typealias SpacesForWindowsFunction =
        @convention(c) (UInt32, Int, CFArray) -> Unmanaged<CFArray>?
    private typealias ExactActivationFunction =
        @convention(c) (
            UnsafePointer<ProcessSerialNumber>,
            CGWindowID,
            UInt32
        ) -> Void
    private typealias ProcessForPIDFunction =
        @convention(c) (
            pid_t,
            UnsafeMutablePointer<ProcessSerialNumber>
        ) -> OSStatus
    private typealias AXWindowIDFunction =
        @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError

    private struct Symbols {
        let mainConnection: MainConnectionFunction?
        let managedSpaces: ManagedSpacesFunction?
        let spacesForWindows: SpacesForWindowsFunction?
        let exactActivation: ExactActivationFunction?
        let processForPID: ProcessForPIDFunction?
        let axWindowID: AXWindowIDFunction?
    }

    private static let frameworkCandidates = [
        "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
        "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics",
    ]
    private static let hiServicesPath =
        "/System/Library/Frameworks/ApplicationServices.framework/"
        + "Frameworks/HIServices.framework/HIServices"

    /// Verified against the compatibility fixture. Keeping the mask local to the
    /// bridge prevents unsupported constants from leaking through the app.
    private static let allSpacesQueryMask = 7
    private static let userGeneratedActivationOption: UInt32 = 1 << 9

    /// Exact activation mutates global focus through a void private ABI, so
    /// symbol presence and a major OS version are insufficient proof of
    /// compatibility. Add an exact Darwin build only after the fixture's
    /// activation matrix passes on arm64 for that build.
    private static let validatedExactActivationBuilds: Set<String> = []
    /// Read-only Space APIs are still private and called in-process. Populate
    /// this independently from exact activation after structural fixture tests
    /// pass on the exact Darwin build.
    private static let validatedSpaceQueryBuilds: Set<String> = []
    /// Mapping AX elements to WindowServer IDs is also unsupported and
    /// in-process. It needs its own exact-build validation evidence.
    private static let validatedAccessibilityWindowIDBuilds: Set<String> = []

    private let handle: UnsafeMutableRawPointer?
    private let hiServicesHandle: UnsafeMutableRawPointer?
    private let symbols: Symbols
    private let capabilityLock = NSLock()
    private var didPerformStartupSelfTest = false
    private var storedCapabilityReport: WindowServerCapabilityReport

    public var capabilityReport: WindowServerCapabilityReport {
        capabilityLock.lock()
        defer { capabilityLock.unlock() }
        return storedCapabilityReport
    }

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

        handle = loadedHandle
        let hiServicesHandle = dlopen(
            Self.hiServicesPath,
            RTLD_LAZY | RTLD_LOCAL
        )
        self.hiServicesHandle = hiServicesHandle

        let mainConnection: MainConnectionFunction? = Self.loadFunction(
            ["SLSMainConnectionID", "CGSMainConnectionID"],
            from: loadedHandle,
            as: MainConnectionFunction.self
        )
        let managedSpaces: ManagedSpacesFunction? = Self.loadFunction(
            ["SLSCopyManagedDisplaySpaces"],
            from: loadedHandle,
            as: ManagedSpacesFunction.self
        )
        let spacesForWindows: SpacesForWindowsFunction? = Self.loadFunction(
            ["SLSCopySpacesForWindows"],
            from: loadedHandle,
            as: SpacesForWindowsFunction.self
        )
        let exactActivation: ExactActivationFunction? = Self.loadFunction(
            ["_SLPSSetFrontProcessWithOptions"],
            from: loadedHandle,
            as: ExactActivationFunction.self
        )
        let processForPID: ProcessForPIDFunction? = Self.loadFunction(
            ["GetProcessForPID"],
            from: hiServicesHandle,
            as: ProcessForPIDFunction.self
        )
        let axWindowID: AXWindowIDFunction? = Self.loadFunction(
            ["_AXUIElementGetWindow"],
            from: hiServicesHandle,
            as: AXWindowIDFunction.self
        )
        symbols = Symbols(
            mainConnection: mainConnection,
            managedSpaces: managedSpaces,
            spacesForWindows: spacesForWindows,
            exactActivation: exactActivation,
            processForPID: processForPID,
            axWindowID: axWindowID
        )

        var detected: WindowServerCapabilities = []
        if mainConnection != nil { detected.insert(.mainConnection) }
        if managedSpaces != nil {
            detected.insert(.spaceInventory)
        }
        if spacesForWindows != nil {
            detected.insert(.windowSpaceQuery)
        }
        if Self.hasSymbol(["SLSRegisterConnectionNotifyProc"], in: loadedHandle) {
            detected.insert(.notifications)
        }
        if exactActivation != nil, processForPID != nil {
            detected.insert(.exactActivation)
        }
        if Self.hasSymbol(["SLSHWCaptureWindowList"], in: loadedHandle) {
            detected.insert(.hardwareCapture)
        }
        if axWindowID != nil { detected.insert(.accessibilityWindowID) }
        if Self.hasSymbol(
            ["_AXUIElementCreateWithRemoteToken"],
            in: hiServicesHandle
        ) {
            detected.insert(.remoteAccessibilityElement)
        }

        var operational: WindowServerCapabilities = []
        if mainConnection != nil {
            operational.insert(.mainConnection)
            if Self.isSpaceQueryABIEnabled, managedSpaces != nil {
                operational.insert(.spaceInventory)
            }
            if Self.isSpaceQueryABIEnabled, spacesForWindows != nil {
                operational.insert(.windowSpaceQuery)
            }
            if Self.isExactActivationABIEnabled,
               exactActivation != nil,
               processForPID != nil {
                operational.insert(.exactActivation)
            }
        }
        if axWindowID != nil,
           Self.isAccessibilityWindowIDABIEnabled {
            operational.insert(.accessibilityWindowID)
        }

        storedCapabilityReport = WindowServerCapabilityReport(
            detected: detected,
            operational: operational,
            frameworkPath: loadedPath
        )
    }

    /// Validates resolved private entry points with harmless calls. Inventory
    /// invokes this from its actor before using any private query, ensuring no
    /// WindowServer work is introduced on the main actor during application
    /// startup.
    public func performStartupSelfTest() {
        capabilityLock.lock()
        guard !didPerformStartupSelfTest else {
            capabilityLock.unlock()
            return
        }
        didPerformStartupSelfTest = true
        let report = storedCapabilityReport
        capabilityLock.unlock()

        var operational = report.operational
        guard let mainConnection = symbols.mainConnection else {
            operational.subtract([
                .mainConnection,
                .spaceInventory,
                .windowSpaceQuery,
                .exactActivation,
            ])
            updateOperationalCapabilities(operational, report: report)
            return
        }

        let connection = mainConnection()
        if connection == 0 {
            operational.subtract([
                .mainConnection,
                .spaceInventory,
                .windowSpaceQuery,
                .exactActivation,
            ])
            updateOperationalCapabilities(operational, report: report)
            return
        }

        if operational.contains(.spaceInventory) {
            guard let displays = symbols.managedSpaces?(
                connection
            )?.takeRetainedValue(),
                  !Self.currentSpaceIDs(from: displays).isEmpty else {
                operational.subtract([
                    .spaceInventory,
                    .windowSpaceQuery,
                ])
                updateOperationalCapabilities(
                    operational,
                    report: report
                )
                return
            }
        }
        if operational.contains(.windowSpaceQuery) {
            guard let testWindowID = Self.firstQueryableWindowID(),
                  let spaces = symbols.spacesForWindows?(
                      connection,
                      Self.allSpacesQueryMask,
                      [NSNumber(value: testWindowID)] as CFArray
                  )?.takeRetainedValue(),
                  !Self.spaceIdentifiers(from: spaces).isEmpty else {
                operational.remove(.windowSpaceQuery)
                updateOperationalCapabilities(
                    operational,
                    report: report
                )
                return
            }
        }
        if operational.contains(.exactActivation) {
            var process = ProcessSerialNumber()
            if symbols.processForPID?(getpid(), &process) != noErr {
                operational.remove(.exactActivation)
            }
        }
        updateOperationalCapabilities(operational, report: report)
    }

    /// Maps a public AX element to its WindowServer ID. Failure is a normal
    /// degraded-mode outcome and never traps.
    public func windowID(for element: AXUIElement) -> CGWindowID? {
        guard capabilityReport.operational.contains(
            .accessibilityWindowID
        ), let function = symbols.axWindowID else {
            return nil
        }
        var identifier: CGWindowID = 0
        guard function(element, &identifier) == .success, identifier != 0 else {
            return nil
        }
        return identifier
    }

    public func spaceIDs(forWindowID windowID: CGWindowID) -> [UInt64] {
        guard capabilityReport.operational.contains(.windowSpaceQuery),
              let connection = symbols.mainConnection?(),
              let function = symbols.spacesForWindows,
              let spaces = function(
                  connection,
                  Self.allSpacesQueryMask,
                  [NSNumber(value: windowID)] as CFArray
              )?.takeRetainedValue() else {
            return []
        }
        return Self.spaceIdentifiers(from: spaces)
    }

    public func visibleSpaceIDs() -> Set<UInt64> {
        guard capabilityReport.operational.contains(.spaceInventory),
              let connection = symbols.mainConnection?(),
              let function = symbols.managedSpaces,
              let displays = function(connection)?.takeRetainedValue()
        else {
            return []
        }

        return Self.currentSpaceIDs(from: displays)
    }

    public func activateExactWindow(pid: pid_t, windowID: CGWindowID) -> Bool {
        guard capabilityReport.operational.contains(.exactActivation),
              let processForPID = symbols.processForPID,
              let activate = symbols.exactActivation else {
            return false
        }

        var process = ProcessSerialNumber()
        guard processForPID(pid, &process) == noErr else { return false }
        activate(
            &process,
            windowID,
            Self.userGeneratedActivationOption
        )
        return true
    }

    /// Fails closed for the remainder of this process after an invoked private
    /// activation cannot be verified by Accessibility.
    public func disableExactActivationForProcessLifetime() {
        capabilityLock.lock()
        let report = storedCapabilityReport
        var operational = report.operational
        operational.remove(.exactActivation)
        storedCapabilityReport = WindowServerCapabilityReport(
            detected: report.detected,
            operational: operational,
            frameworkPath: report.frameworkPath
        )
        capabilityLock.unlock()
        TabListLog.compatibility.error(
            "Exact private activation was disabled for this process after focus verification failed"
        )
    }

    private static func hasSymbol(
        _ names: [String],
        in handle: UnsafeMutableRawPointer?
    ) -> Bool {
        guard let handle else { return false }
        return names.contains { dlsym(handle, $0) != nil }
    }

    private static func loadFunction<T>(
        _ names: [String],
        from handle: UnsafeMutableRawPointer?,
        as _: T.Type
    ) -> T? {
        guard let handle else { return nil }
        for name in names {
            guard let symbol = dlsym(handle, name) else { continue }
            return unsafeBitCast(symbol, to: T.self)
        }
        return nil
    }

    private static var isExactActivationABIEnabled: Bool {
#if arch(arm64)
#if DEBUG
        if ProcessInfo.processInfo.environment[
            "TABLIST_ENABLE_UNVERIFIED_EXACT_ACTIVATION"
        ] == "1" {
            return true
        }
#endif
        guard let build = darwinBuildIdentifier() else { return false }
        return validatedExactActivationBuilds.contains(build)
#else
        return false
#endif
    }

    private static var isSpaceQueryABIEnabled: Bool {
#if arch(arm64)
#if DEBUG
        if ProcessInfo.processInfo.environment[
            "TABLIST_ENABLE_UNVERIFIED_SPACE_APIS"
        ] == "1" {
            return true
        }
#endif
        guard let build = darwinBuildIdentifier() else { return false }
        return validatedSpaceQueryBuilds.contains(build)
#else
        return false
#endif
    }

    private static var isAccessibilityWindowIDABIEnabled: Bool {
#if arch(arm64)
#if DEBUG
        if ProcessInfo.processInfo.environment[
            "TABLIST_ENABLE_UNVERIFIED_AX_WINDOW_ID"
        ] == "1" {
            return true
        }
#endif
        guard let build = darwinBuildIdentifier() else { return false }
        return validatedAccessibilityWindowIDBuilds.contains(build)
#else
        return false
#endif
    }

    private static func spaceIdentifiers(from spaces: CFArray) -> [UInt64] {
        (spaces as [AnyObject]).compactMap {
            guard let value = ($0 as? NSNumber)?.uint64Value,
                  value != 0 else {
                return nil
            }
            return value
        }
    }

    private static func currentSpaceIDs(
        from displays: CFArray
    ) -> Set<UInt64> {
        var identifiers: Set<UInt64> = []
        for case let display as NSDictionary in displays as [AnyObject] {
            guard let currentSpace = display[
                "Current Space"
            ] as? NSDictionary else {
                continue
            }
            let identifier = (
                currentSpace["ManagedSpaceID"]
                    ?? currentSpace["id64"]
            ) as? NSNumber
            if let identifier, identifier.uint64Value != 0 {
                identifiers.insert(identifier.uint64Value)
            }
        }
        return identifiers
    }

    private static func darwinBuildIdentifier() -> String? {
        var size = 0
        guard sysctlbyname("kern.osversion", nil, &size, nil, 0) == 0,
              size > 1 else {
            return nil
        }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname(
            "kern.osversion",
            &bytes,
            &size,
            nil,
            0
        ) == 0 else {
            return nil
        }
        let content = bytes.prefix { $0 != 0 }.map {
            UInt8(bitPattern: $0)
        }
        return String(decoding: content, as: UTF8.self)
    }

    private func updateOperationalCapabilities(
        _ operational: WindowServerCapabilities,
        report: WindowServerCapabilityReport
    ) {
        capabilityLock.lock()
        storedCapabilityReport = WindowServerCapabilityReport(
            detected: report.detected,
            operational: operational,
            frameworkPath: report.frameworkPath
        )
        capabilityLock.unlock()
        TabListLog.compatibility.notice(
            "WindowServer self-test completed with detected mask \(report.detected.rawValue, privacy: .public) and operational mask \(operational.rawValue, privacy: .public)"
        )
    }

    /// Supplies a real, currently valid window identifier for the harmless
    /// startup space-query probe. An empty window array is ambiguous on some
    /// macOS builds, so it is not sufficient as a capability self-test.
    private static func firstQueryableWindowID() -> CGWindowID? {
        guard let info = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return nil
        }

        return info.lazy.compactMap { window -> CGWindowID? in
            let layer =
                (window[kCGWindowLayer as String] as? NSNumber)?.intValue
            guard layer == 0,
                  let number = window[
                      kCGWindowNumber as String
                  ] as? NSNumber
            else {
                return nil
            }
            let identifier = CGWindowID(number.uint32Value)
            return identifier == 0 ? nil : identifier
        }.first
    }
}
