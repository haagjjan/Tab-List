@preconcurrency import AppKit
@preconcurrency import ApplicationServices
import Foundation
import TabListCore

enum AccessibilityRegistryEvent: Sendable {
    case focusChanged(pid_t)
    case inventoryChanged(pid_t)
}

private final class ObservedAXElementBox: @unchecked Sendable {
    let value: AXUIElement

    init(_ value: AXUIElement) {
        self.value = value
    }
}

private final class AccessibilityEventSink: @unchecked Sendable {
    let handler: @MainActor @Sendable (AccessibilityRegistryEvent) -> Void

    init(
        handler: @escaping @MainActor @Sendable (
            AccessibilityRegistryEvent
        ) -> Void
    ) {
        self.handler = handler
    }

    func deliver(_ event: AccessibilityRegistryEvent) {
        DispatchQueue.main.async { [handler] in
            MainActor.assumeIsolated {
                handler(event)
            }
        }
    }
}

private final class AccessibilityObserverCallbackBox: @unchecked Sendable {
    let token: UUID
    let pid: pid_t
    let handler: @Sendable (
        UUID,
        pid_t,
        AXUIElement,
        String
    ) -> Void

    init(
        token: UUID,
        pid: pid_t,
        handler: @escaping @Sendable (
            UUID,
            pid_t,
            AXUIElement,
            String
        ) -> Void
    ) {
        self.token = token
        self.pid = pid
        self.handler = handler
    }

    func receive(element: AXUIElement, notification: CFString) {
        handler(token, pid, element, notification as String)
    }
}

private let accessibilityObserverCallback: AXObserverCallback = {
    _, element, notification, userInfo in
    guard let userInfo else { return }
    let box = Unmanaged<AccessibilityObserverCallbackBox>
        .fromOpaque(userInfo)
        .takeUnretainedValue()
    box.receive(element: element, notification: notification)
}

/// Owns every AX observer and notification registration on a dedicated
/// CFRunLoop. No AX setup, query, or callback executes on the main actor.
private final class AccessibilityObserverWorker: @unchecked Sendable {
    private struct WindowRegistration {
        let element: AXUIElement
        let notifications: [String]
    }

    private struct Registration {
        let token: UUID
        let observer: AXObserver
        let application: AXUIElement
        let callbackBox: AccessibilityObserverCallbackBox
        let applicationNotifications: [String]
        var windows: [WindowRegistration]
    }

    private static let applicationNotificationNames = [
        kAXFocusedWindowChangedNotification as String,
        kAXWindowCreatedNotification as String,
    ]

    private static let windowNotificationNames = [
        kAXTitleChangedNotification as String,
        kAXMovedNotification as String,
        kAXResizedNotification as String,
        kAXWindowMiniaturizedNotification as String,
        kAXWindowDeminiaturizedNotification as String,
        kAXUIElementDestroyedNotification as String,
    ]

    private let sink: AccessibilityEventSink
    private let lifecycleLock = NSLock()
    private var runLoop: CFRunLoop?
    private var keepAliveSource: CFRunLoopSource?
    private var thread: Thread?
    private var stopped = false

    /// Accessed only on the worker run loop.
    private var registrations: [pid_t: Registration] = [:]
    private var discoveryInFlight: Set<pid_t> = []

    init(sink: AccessibilityEventSink) {
        self.sink = sink
    }

    func start() -> Bool {
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [self] in
            var context = CFRunLoopSourceContext()
            guard let source = CFRunLoopSourceCreate(
                kCFAllocatorDefault,
                0,
                &context
            ) else {
                ready.signal()
                return
            }
            let currentRunLoop = CFRunLoopGetCurrent()

            lifecycleLock.lock()
            guard !stopped else {
                lifecycleLock.unlock()
                ready.signal()
                return
            }
            runLoop = currentRunLoop
            keepAliveSource = source
            lifecycleLock.unlock()

            CFRunLoopAddSource(currentRunLoop, source, .commonModes)
            ready.signal()
            CFRunLoopRun()
            removeAllRegistrations()
            CFRunLoopRemoveSource(currentRunLoop, source, .commonModes)

            lifecycleLock.lock()
            runLoop = nil
            keepAliveSource = nil
            self.thread = nil
            lifecycleLock.unlock()
        }
        thread.name = "Tab-List Accessibility observer"
        thread.qualityOfService = .userInitiated

        lifecycleLock.lock()
        stopped = false
        self.thread = thread
        lifecycleLock.unlock()
        thread.start()
        guard ready.wait(timeout: .now() + 2) == .success else {
            stop()
            return false
        }

        lifecycleLock.lock()
        let started = runLoop != nil && !stopped
        lifecycleLock.unlock()
        return started
    }

    func observe(_ processIDs: [pid_t]) {
        perform { [weak self] in
            guard let self else { return }
            for pid in processIDs {
                observe(pid: pid)
            }
        }
    }

    func observe(pid: pid_t) {
        perform { [weak self] in
            self?.observeProcess(pid: pid)
        }
    }

    func remove(pid: pid_t) {
        perform { [weak self] in
            self?.removeRegistration(pid: pid)
        }
    }

    func stop() {
        lifecycleLock.lock()
        stopped = true
        let currentRunLoop = runLoop
        lifecycleLock.unlock()

        guard let currentRunLoop else { return }
        CFRunLoopPerformBlock(
            currentRunLoop,
            CFRunLoopMode.commonModes.rawValue
        ) { [self] in
            removeAllRegistrations()
            CFRunLoopStop(currentRunLoop)
        }
        CFRunLoopWakeUp(currentRunLoop)
    }

    private func perform(
        _ operation: @escaping @Sendable () -> Void
    ) {
        lifecycleLock.lock()
        let currentRunLoop = stopped ? nil : runLoop
        lifecycleLock.unlock()
        guard let currentRunLoop else { return }
        CFRunLoopPerformBlock(
            currentRunLoop,
            CFRunLoopMode.commonModes.rawValue,
            operation
        )
        CFRunLoopWakeUp(currentRunLoop)
    }

    /// Worker-run-loop only.
    private func observeProcess(pid: pid_t) {
        guard pid > 0,
              pid != ProcessInfo.processInfo.processIdentifier,
              registrations[pid] == nil,
              AXIsProcessTrusted()
        else {
            return
        }

        var createdObserver: AXObserver?
        guard AXObserverCreate(
            pid,
            accessibilityObserverCallback,
            &createdObserver
        ) == .success, let observer = createdObserver else {
            return
        }

        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.25)
        let token = UUID()
        let callbackBox = AccessibilityObserverCallbackBox(
            token: token,
            pid: pid
        ) { [weak self] token, pid, element, notification in
            self?.receive(
                token: token,
                pid: pid,
                element: element,
                notification: notification
            )
        }
        let context = Unmanaged.passUnretained(callbackBox).toOpaque()

        var applicationNotifications: [String] = []
        for notification in Self.applicationNotificationNames {
            let result = AXObserverAddNotification(
                observer,
                application,
                notification as CFString,
                context
            )
            if result == .success
                || result == .notificationAlreadyRegistered {
                applicationNotifications.append(notification)
            }
        }
        guard !applicationNotifications.isEmpty else { return }

        CFRunLoopAddSource(
            CFRunLoopGetCurrent(),
            AXObserverGetRunLoopSource(observer),
            .commonModes
        )
        registrations[pid] = Registration(
            token: token,
            observer: observer,
            application: application,
            callbackBox: callbackBox,
            applicationNotifications: applicationNotifications,
            windows: []
        )
        discoverAndRegisterWindows(pid: pid, token: token)
    }

    /// Worker-run-loop only.
    private func receive(
        token: UUID,
        pid: pid_t,
        element: AXUIElement,
        notification: String
    ) {
        guard registrations[pid]?.token == token else { return }

        switch notification {
        case kAXFocusedWindowChangedNotification:
            sink.deliver(.focusChanged(pid))
            discoverAndRegisterWindows(pid: pid, token: token)
        case kAXWindowCreatedNotification:
            discoverAndRegisterWindows(pid: pid, token: token)
            sink.deliver(.inventoryChanged(pid))
        case kAXUIElementDestroyedNotification:
            removeWindow(element, pid: pid)
            sink.deliver(.inventoryChanged(pid))
        default:
            sink.deliver(.inventoryChanged(pid))
        }
    }

    /// Window enumeration runs on a detached lane with an AX messaging timeout
    /// so one unresponsive application cannot stall the observer run loop.
    private func discoverAndRegisterWindows(pid: pid_t, token: UUID) {
        guard let registration = registrations[pid],
              registration.token == token,
              discoveryInFlight.insert(pid).inserted else {
            return
        }
        let application = ObservedAXElementBox(registration.application)

        Task.detached(priority: .utility) { [weak self] in
            let windows = Self.copyWindows(from: application.value).map(
                ObservedAXElementBox.init
            )
            self?.perform { [weak self] in
                guard let self else { return }
                discoveryInFlight.remove(pid)
                guard registrations[pid]?.token == token else {
                    return
                }
                for window in windows {
                    registerWindow(window.value, pid: pid)
                }
            }
        }
    }

    /// Worker-run-loop only.
    private func registerWindow(_ window: AXUIElement, pid: pid_t) {
        guard var registration = registrations[pid],
              !registration.windows.contains(where: {
                  CFEqual($0.element, window)
              })
        else {
            return
        }

        AXUIElementSetMessagingTimeout(window, 0.25)
        let context = Unmanaged.passUnretained(
            registration.callbackBox
        ).toOpaque()
        var added: [String] = []
        for notification in Self.windowNotificationNames {
            let result = AXObserverAddNotification(
                registration.observer,
                window,
                notification as CFString,
                context
            )
            if result == .success
                || result == .notificationAlreadyRegistered {
                added.append(notification)
            }
        }
        guard !added.isEmpty else { return }

        registration.windows.append(
            WindowRegistration(element: window, notifications: added)
        )
        registrations[pid] = registration
    }

    /// Worker-run-loop only.
    private func removeWindow(_ window: AXUIElement, pid: pid_t) {
        guard var registration = registrations[pid],
              let index = registration.windows.firstIndex(where: {
                  CFEqual($0.element, window)
              })
        else {
            return
        }

        let windowRegistration = registration.windows.remove(at: index)
        for notification in windowRegistration.notifications {
            _ = AXObserverRemoveNotification(
                registration.observer,
                windowRegistration.element,
                notification as CFString
            )
        }
        registrations[pid] = registration
    }

    /// Worker-run-loop only.
    private func removeRegistration(pid: pid_t) {
        discoveryInFlight.remove(pid)
        guard let registration = registrations.removeValue(forKey: pid)
        else {
            return
        }

        for window in registration.windows {
            for notification in window.notifications {
                _ = AXObserverRemoveNotification(
                    registration.observer,
                    window.element,
                    notification as CFString
                )
            }
        }
        for notification in registration.applicationNotifications {
            _ = AXObserverRemoveNotification(
                registration.observer,
                registration.application,
                notification as CFString
            )
        }
        CFRunLoopRemoveSource(
            CFRunLoopGetCurrent(),
            AXObserverGetRunLoopSource(registration.observer),
            .commonModes
        )
    }

    /// Worker-run-loop only.
    private func removeAllRegistrations() {
        for pid in Array(registrations.keys) {
            removeRegistration(pid: pid)
        }
    }

    nonisolated private static func copyWindows(
        from application: AXUIElement
    ) -> [AXUIElement] {
        AXUIElementSetMessagingTimeout(application, 0.25)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            application,
            kAXWindowsAttribute as CFString,
            &value
        ) == .success,
              let windows = value as? [AXUIElement] else {
            return []
        }
        return windows
    }
}

/// Main-actor lifecycle wrapper. Workspace observations remain on AppKit's
/// actor, while every Accessibility call is delegated to the worker.
@MainActor
final class AccessibilityFocusMonitor {
    private let sink: AccessibilityEventSink
    private var worker: AccessibilityObserverWorker?
    private var workspaceTokens: [any NSObjectProtocol] = []

    init(
        handler: @escaping @MainActor @Sendable (
            AccessibilityRegistryEvent
        ) -> Void
    ) {
        sink = AccessibilityEventSink(handler: handler)
    }

    isolated deinit {
        stop()
    }

    func start() {
        guard AXIsProcessTrusted(), worker == nil else { return }
        let worker = AccessibilityObserverWorker(sink: sink)
        guard worker.start() else { return }
        self.worker = worker

        let center = NSWorkspace.shared.notificationCenter
        workspaceTokens = [
            center.addObserver(
                forName: NSWorkspace.didLaunchApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                let pid = (
                    notification.userInfo?[
                        NSWorkspace.applicationUserInfoKey
                    ] as? NSRunningApplication
                )?.processIdentifier
                MainActor.assumeIsolated {
                    if let pid {
                        self?.worker?.observe(pid: pid)
                    }
                }
            },
            center.addObserver(
                forName: NSWorkspace.didTerminateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                let pid = (
                    notification.userInfo?[
                        NSWorkspace.applicationUserInfoKey
                    ] as? NSRunningApplication
                )?.processIdentifier
                MainActor.assumeIsolated {
                    if let pid {
                        self?.worker?.remove(pid: pid)
                    }
                }
            },
        ]

        worker.observe(
            NSWorkspace.shared.runningApplications.compactMap {
                application -> pid_t? in
                guard application.activationPolicy == .regular else {
                    return nil
                }
                return application.processIdentifier
            }
        )
    }

    func stop() {
        let center = NSWorkspace.shared.notificationCenter
        workspaceTokens.forEach(center.removeObserver)
        workspaceTokens.removeAll()
        worker?.stop()
        worker = nil
    }

    func refresh() {
        stop()
        start()
    }
}
